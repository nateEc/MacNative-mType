#!/usr/bin/env python3
"""Prepare literal German Wiktionary forms ranked with independent observations.

No downloads or reference words. Source preparation needs Unicode 15.0.0 and
msgpack==1.1.2. Self-tests / bundled verification use the standard library.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys
import unicodedata
import unittest
import zipfile

SOURCE_URL = "https://kaikki.org/dictionary/downloads/de/de-extract.jsonl.gz"
SOURCE_SHA = "04f07bd9d54277d79e0c6e1478fe86a13ac9db7c292cdec13b961b59a505f79b"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/large_de.msgpack.gz"
MEMBER_SHA = "8ef04d3f4a28fb48d800d25fa80a96d90a5f80c8496c9a453f99f887c6ad3c12"
REVISION = "kaikki-de-20261029-wordfreq-3.1.1-v1"
COUNTS = {"1k": 988, "10k": 9994, "250k": 239243}
LIMITS = {"1k": 17, "10k": 27, "250k": 35}
PHRASES = {"1k": 8, "10k": 40, "250k": 0}
PUNCTUATED = {"1k": 3, "10k": 25, "250k": 0}
# Independent editorial practice examples. Every exact spelling must exist as
# a dictionary headword; these are not separately measured usage frequencies.
PUNCTUATION_CHOICES = {
    "1k": ["E-Mail", "usw.", "wenn’s"],
    "10k": ["E-Mail", "U-Bahn", "S-Bahn", "U-Boot", "T-Shirt", "CD-ROM", "Know-how",
            "Make-up", "O-Beine", "X-Beine", "i-Punkt", "usw.", "z.B.", "u.a.", "bzw.",
            "Dr.", "Prof.", "wenn’s", "wird’s", "E-Mails", "U-Bahnen", "S-Bahnen",
            "U-Boote", "T-Shirts", "E-Bike"],
    "250k": [],
}
SMALL = Path("Sources/Typebar/GermanFrequencyCorpus.generated.swift")
LARGE = Path("Sources/Typebar/GermanLargeCorpus.generated.swift")
MANIFEST = Path("Compatibility/german-frequency-corpus.json")
NOTICES = Path("Resources/GermanFrequencyCorpusNotices.txt")
SOURCES = Path("Resources/GermanCorpusSources.txt")
ATTRIBUTION_PINS = {
    str(NOTICES): "4a1b02e3cc09ed9a2d78d26511b181fbdf68f280ab2ccf8abe2beed060f13136",
    str(SOURCES): "431443cbaf20c9351b8a6ad2cf42ddf09a1e75c6b2067872116bd8a95a00eee6",
}
PARTS = frozenset("noun name verb adj adv article pron det conj intj prep postp num particle phrase abbrev".split())
PHRASE_PARTS = frozenset("noun name adv phrase".split())


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def letters(word):
    return bool(word) and all(c.isalpha() and unicodedata.name(c, "").startswith("LATIN ") for c in word)


def literal(word, limit=35):
    return (type(word) is str and 2 <= len(word) <= limit
            and word == unicodedata.normalize("NFC", word) and letters(word))


def remember(pool, word, lemma):
    previous = pool.get(word)
    if previous is None or (len(lemma), lemma) < (len(previous), previous):
        pool[word] = lemma


def collect_entry(item, pools):
    require(type(item) is dict, "dictionary entry must be an object")
    if item.get("lang_code") != "de" or item.get("pos") not in PARTS:
        return
    lemma = item.get("word")
    require(type(lemma) is str and not any(c in lemma for c in "\t\r\n"), "invalid source title")
    if literal(lemma):
        remember(pools["letters"], lemma, lemma)
    if lemma == unicodedata.normalize("NFC", lemma) and 2 <= len(lemma) <= 27:
        if item.get("pos") in PHRASE_PARTS and " " in lemma and all(letters(w) for w in lemma.split(" ")):
            remember(pools["phrases"], lemma, lemma)
        # Only existing headwords; never append punctuation or concatenate words.
        segments = re.split("[-'.’]", lemma[:-1] if lemma.endswith(".") else lemma)
        if " " not in lemma and any(c in lemma for c in "-'.’") and all(letters(w) for w in segments):
            remember(pools["punctuated"], lemma, lemma)
    forms = item.get("forms", [])
    require(type(forms) is list, "dictionary forms must be an array")
    for form in forms:
        require(type(form) is dict and type(form.get("form")) is str, "invalid dictionary form")
        word = form["form"]
        if literal(word):
            remember(pools["letters"], word, lemma)


def read_dictionary(path):
    require(unicodedata.unidata_version == "15.0.0", "source preparation requires Unicode 15.0.0")
    require(file_digest(path) == SOURCE_SHA, "German dictionary snapshot SHA-256 mismatch")
    pools = {name: {} for name in ["letters", "phrases", "punctuated"]}
    with gzip.open(path, "rt", encoding="utf-8") as source:
        for line in source:
            collect_entry(json.loads(line), pools)
    return pools


def read_frequency(path):
    require(file_digest(path) == WHEEL_SHA, "wordfreq wheel SHA-256 mismatch")
    import msgpack
    require(msgpack.__version__ == "1.1.2", "source preparation requires msgpack==1.1.2")
    with zipfile.ZipFile(path) as archive:
        packed = archive.read(MEMBER)
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode("utf-8")
    require(digest(packed) == MEMBER_SHA, "German frequency member SHA-256 mismatch")
    data = msgpack.unpackb(gzip.decompress(packed), raw=False)
    require(type(data) is list and data and data[0] == {"format": "cB", "version": 1}, "unsupported frequency format")
    require("## License" in metadata, "wordfreq source notices missing")
    return frequency_bands(data[1:]), metadata[metadata.index("## License"):].strip() + "\n"


def frequency_bands(bins):
    require(type(bins) is list, "frequency bins must be an array")
    result = {}
    for band, words in enumerate(bins):
        require(type(words) is list and all(type(w) is str for w in words), "frequency bin must contain strings")
        require(words == sorted(set(words)), "frequency bins must be sorted and unique")
        for word in words:
            require(word not in result, "frequency token occurs in multiple bins")
            result[word] = band
    return result


def select(pools, bands, count, limit, phrases, punctuated):
    require(all(type(n) is int and n >= 0 for n in [count, limit, phrases, punctuated])
            and count > phrases + punctuated and limit >= 2, "invalid selection limits")
    def priority(word):
        # The pinned German observations use Unicode case-folding (ß -> ss).
        # Keep that lookup separate from the literal selected spelling.
        band = bands.get(word.casefold())
        if band is None:
            parts = [w for w in re.split("[ \\-'.’]", word) if w]
            band = max((bands.get(w.casefold(), 10**9) for w in parts), default=10**9)
        return band, word.lower(), word
    selected = []
    for name, needed in [("letters", count - phrases - punctuated), ("phrases", phrases), ("punctuated", punctuated)]:
        available = sorted((w for w in pools[name] if len(w) <= limit), key=priority)
        require(len(available) >= needed, "insufficient attested " + name + "; never pad")
        chosen = available[:needed]
        if name == "letters" and not any(len(w) == limit for w in chosen):
            # Keep long-word practice at the original choice's length bound,
            # using an existing form, never a repeated-character placeholder.
            longest = next((w for w in available if len(w) == limit), None)
            require(longest is not None, "no attested maximum-length practice form")
            chosen[-1] = longest
        selected += chosen
    require(len(selected) == len(set(selected)) == count, "selection must be unique")
    return sorted(selected, key=priority)


def native_source(name, scales):
    value = ("// Generated by Scripts/prepare-german-frequency-corpus.py; do not edit.\n"
             "// Literal German Wiktionary forms; independent wordfreq ranking.\n"
             "// CC BY-SA 4.0 adapted selection; full notices / entry titles accompany the app.\n"
             f"enum {name} {{\n  static let revision = \"{REVISION}\"\n")
    for scale, words in scales.items():
        value += f'  static let words{scale}: [String] = """\n' + "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    return (value + "}\n").encode()


def shape(words):
    return {"count": len(words), "uniqueCount": len(set(words)), "minimumLength": min(map(len, words)),
            "maximumLength": max(map(len, words)), "uppercaseCount": sum(any(c.isupper() for c in w) for w in words),
            "nonLetterCount": sum(not w.isalpha() for w in words), "spaceCount": sum(" " in w for w in words),
            "punctuationCount": sum(any(unicodedata.category(c).startswith("P") for c in w) for w in words),
            "nonASCIICount": sum(not w.isascii() for w in words)}


def check_attribution_pins(hashes):
    require(all(hashes.get(name) == sha for name, sha in ATTRIBUTION_PINS.items()),
            "published attribution pin mismatch; mutable manifest hashes are insufficient")


def artifacts(pools, bands, source_notice):
    scales = {}
    for key, count in COUNTS.items():
        choices = PUNCTUATION_CHOICES[key]
        require(len(choices) == len(set(choices)) == PUNCTUATED[key]
                and all(w in pools["punctuated"] for w in choices), "editorial punctuation must be literally attested")
        practice_pools = dict(pools, punctuated={w: pools["punctuated"][w] for w in choices})
        scales[key] = select(practice_pools, bands, count, LIMITS[key], PHRASES[key], PUNCTUATED[key])
    source_map = {}
    for words in scales.values():
        for word in words:
            owners = [pool[word] for pool in pools.values() if word in pool]
            source_map[word] = min(owners, key=lambda w: (len(w), w))
    sources = ("# Literal selected form\tGerman Wiktionary source page title\n"
               "# Page: https://de.wiktionary.org/wiki/<URL-encoded title>\n"
               "# Contributors: https://de.wiktionary.org/w/index.php?title=<URL-encoded title>&action=history\n"
               + "".join(word + "\t" + source_map[word] + "\n" for word in sorted(source_map))).encode()
    notices = ("Typebar independent German corpus — revision 1\n"
               "Literal headwords and inflected forms from German Wiktionary contributors,\n"
               "extracted by Kaikki.org / Wiktextract. Selection and ordering adapted by\n"
               "Typebar contributors (2026), CC BY-SA 4.0.\n"
               "https://creativecommons.org/licenses/by-sa/4.0/\n\n"
               "Dictionary snapshot retrieved 2026-10-29:\n" + SOURCE_URL + "\nSHA-256: " + SOURCE_SHA + "\n"
               "https://kaikki.org/dictionary/rawdata.html\n"
               "https://kaikki.org/dewiktionary/\n"
               "https://de.wiktionary.org/wiki/Wiktionary:Lizenzbestimmungen\n"
               "Wiktionary text is shared under CC BY-SA; historical source notices also\n"
               "refer to CC BY-SA 3.0 and GFDL. This adapted selection uses CC BY-SA 4.0.\n"
               "https://creativecommons.org/licenses/by-sa/3.0/\n\n"
               "Entry-level attribution is in the accompanying GermanCorpusSources.txt.\n"
               "Each selected literal form maps to its original German Wiktionary page\n"
               "title; the file gives page and contributor-history URL templates.\n"
               "No definitions, examples, images or audio are included.\n\n"
               "Changes: select NFC Latin-letter forms with existing case, at most\n"
               "17 / 27 / 35 characters. The small choices also include existing\n"
               "multiword and punctuated headwords. Never manufacture case, inflections,\n"
               "phrases or filler. Rank with case-folded wordfreq observations (ß -> ss\n"
               "in the lookup key only). When no exact observation exists, phrase or\n"
               "punctuated-form rank is estimated from the rarest constituent, not\n"
               "measured whole-form frequency. Literal spellings remain unchanged.\n"
               "Retain one existing maximum-length form per choice for long-word practice;\n"
               "the selection is therefore not a pure frequency cutoff.\n"
               "Punctuated practice examples are independent editorial selections of\n"
               "existing dictionary headwords, not measured frequency cutoffs.\n"
               "Unknown ranks sort last; case variants share observation evidence.\n"
               "Dictionary extraction can contain errors, archaic forms, names, loans\n"
               "and offensive words. No quality, difficulty or distribution parity claim.\n\n"
               "Kaikki / Wiktextract: Tatu Ylonen, Wiktextract: Wiktionary as\n"
               "Machine-Readable Structured Data, LREC 2022, pp. 1317–1325.\n"
               "https://aclanthology.org/2022.lrec-1.140/\n\n"
               "=== wordfreq 3.1.1 release metadata ===\n" + source_notice).encode()
    small = native_source("GermanFrequencyCorpus", {k: scales[k] for k in ["1k", "10k"]})
    large = native_source("GermanLargeCorpus", {"250k": scales["250k"]})
    generated = {SMALL: small, LARGE: large, NOTICES: notices, SOURCES: sources}
    check_attribution_pins({str(k): digest(v) for k, v in generated.items()})
    manifest = {"schemaVersion": 1, "revision": REVISION,
                "dictionary": {"url": SOURCE_URL, "sha256": SOURCE_SHA, "retrievedDate": "2026-10-29", "languageCode": "de"},
                "wordfreq": {"version": "3.1.1", "wheelSHA256": WHEEL_SHA, "member": MEMBER, "memberSHA256": MEMBER_SHA},
                "preparation": {"unicodeVersion": "15.0.0", "msgpackVersion": "1.1.2", "runtimeDependencies": []},
                "available": {k: len(v) for k, v in pools.items()},
                "editorialPunctuation": PUNCTUATION_CHOICES,
                "longFormCoverage": {k: next(w for w in words if len(w) == LIMITS[k] and letters(w)) for k, words in scales.items()},
                "scales": {k: {"shape": shape(w), "wordsSHA256": digest(("\n".join(w) + "\n").encode())} for k, w in scales.items()},
                "filesSHA256": {str(k): digest(v) for k, v in generated.items()},
                "sourceMapCount": len(source_map), "dataLicense": "CC-BY-SA-4.0 adapted selection; retain source credits and entry map",
                "limits": "Literal dictionary attestation and aggregate counts do not prove extraction quality, difficulty or distribution parity."}
    generated[MANIFEST] = (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
    return generated


def publish(outputs, root, check):
    if check:
        for name, data in outputs.items():
            require((root / name).read_bytes() == data, "artifact mismatch: " + str(name))
    else:
        require(not any((root / name).exists() for name in outputs), "refusing to overwrite artifacts")
        for name, data in outputs.items():
            destination = root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)


def verify_bundled(root):
    manifest = json.loads((root / MANIFEST).read_text())
    require(manifest["schemaVersion"] == 1 and manifest["revision"] == REVISION, "unsupported corpus manifest")
    require(manifest["dictionary"]["sha256"] == SOURCE_SHA and manifest["dictionary"]["url"] == SOURCE_URL
            and manifest["wordfreq"]["wheelSHA256"] == WHEEL_SHA and manifest["wordfreq"]["memberSHA256"] == MEMBER_SHA,
            "source pin mismatch")
    require(set(manifest["filesSHA256"]) == {str(p) for p in [SMALL, LARGE, NOTICES, SOURCES]}, "file inventory mismatch")
    check_attribution_pins(manifest["filesSHA256"])
    for name, sha in manifest["filesSHA256"].items():
        require(file_digest(root / name) == sha, "bundled file hash mismatch: " + name)
    scales = {}
    for path in [SMALL, LARGE]:
        text = (root / path).read_text()
        found = dict((k, body.splitlines()) for k, body in re.findall(r'  static let words(1k|10k|250k): \[String\] = """\n(.*?)"""', text, re.S))
        require(len(found) == (2 if path == SMALL else 1), "missing native word section")
        require(native_source("GermanFrequencyCorpus" if path == SMALL else "GermanLargeCorpus", found) == (root / path).read_bytes(), "native template mismatch")
        scales.update(found)
    require(set(scales) == set(COUNTS) == set(manifest["scales"]), "scale inventory mismatch")
    for key, words in scales.items():
        expected = manifest["scales"][key]
        require(len(words) == len(set(words)) == COUNTS[key] and shape(words) == expected["shape"], "scale shape mismatch")
        require(digest(("\n".join(words) + "\n").encode()) == expected["wordsSHA256"], "word data hash mismatch")
        require(all(2 <= len(w) <= LIMITS[key] and w == unicodedata.normalize("NFC", w) for w in words), "invalid word limit")
        require(manifest["longFormCoverage"][key] in words
                and len(manifest["longFormCoverage"][key]) == LIMITS[key]
                and letters(manifest["longFormCoverage"][key]), "maximum-length practice form missing")
        require(sum(" " in w for w in words) == PHRASES[key]
                and sum(any(unicodedata.category(c).startswith("P") for c in w) for w in words) == PUNCTUATED[key], "practice sections missing")
        require(set(w for w in words if any(unicodedata.category(c).startswith("P") for c in w)) == set(PUNCTUATION_CHOICES[key])
                and manifest["editorialPunctuation"][key] == PUNCTUATION_CHOICES[key], "editorial punctuation changed")
    pairs = [line.split("\t") for line in (root / SOURCES).read_text().splitlines() if not line.startswith("#")]
    require(all(len(pair) == 2 and all(pair) for pair in pairs), "invalid source attribution map")
    source_map = dict(pairs)
    require(len(pairs) == len(source_map) == manifest["sourceMapCount"]
            and set(source_map) == {w for words in scales.values() for w in words}, "source attribution coverage mismatch")
    print("German bundled integrity passed (988 / 9994 / 239243; source reproduction is stronger)")


class Contracts(unittest.TestCase):
    def test_literal_case_forms_and_language_gate(self):
        pools = {k: {} for k in ["letters", "phrases", "punctuated"]}
        collect_entry({"lang_code": "de", "pos": "noun", "word": "Haus", "forms": [{"form": "Häuser"}]}, pools)
        collect_entry({"lang_code": "la", "pos": "noun", "word": "ordo"}, pools)
        collect_entry({"lang_code": "de", "pos": "suffix", "word": "-heit"}, pools)
        self.assertEqual(pools["letters"], {"Haus": "Haus", "Häuser": "Haus"})
        self.assertNotIn("haus", pools["letters"])

    def test_only_existing_phrases_and_internal_punctuation(self):
        pools = {k: {} for k in ["letters", "phrases", "punctuated"]}
        for word in ["zu Hause", "so  etwas", "Nord-Süd", "-heit", "usw.", "—"]:
            collect_entry({"lang_code": "de", "pos": "phrase", "word": word}, pools)
        self.assertEqual(set(pools["phrases"]), {"zu Hause"})
        self.assertEqual(set(pools["punctuated"]), {"Nord-Süd", "usw."})

    def test_missing_attested_forms_are_never_padded(self):
        pools = {k: {} for k in ["letters", "phrases", "punctuated"]}
        pools["letters"] = {"Haus": "Haus"}
        with self.assertRaisesRegex(ValueError, "never pad"):
            select(pools, {}, 2, 17, 0, 0)

    def test_frequency_validation_and_estimated_phrase_rank(self):
        for bins in [[["b", "a"]], [["a", "a"]], [["a"], ["a"]], [[1]], "invalid"]:
            with self.assertRaises(ValueError): frequency_bands(bins)
        pools = {"letters": {"Haus": "Haus", "Weg": "Weg", "Außergewöhnliches": "außergewöhnlich"}, "phrases": {"zu Hause": "zu Hause"}, "punctuated": {}}
        bands = {"haus": 10, "weg": 20, "zu": 1, "hause": 15, "außergewöhnliches": 30}
        self.assertEqual(select(pools, bands, 3, 17, 1, 0), ["Haus", "zu Hause", "Außergewöhnliches"])

    def test_missing_long_word_coverage_is_not_replaced_with_filler(self):
        pools = {"letters": {"Haus": "Haus", "Weg": "Weg"}, "phrases": {}, "punctuated": {}}
        with self.assertRaisesRegex(ValueError, "maximum-length"):
            select(pools, {}, 2, 17, 0, 0)

    def test_provenance_selection_is_order_independent(self):
        for order in [["Häuser", "Haus"], ["Haus", "Häuser"]]:
            pool = {}
            for lemma in order: remember(pool, "Häusern", lemma)
            self.assertEqual(pool, {"Häusern": "Haus"})

    def test_casefolded_observations_keep_literal_eszett(self):
        pools = {"letters": {"Straße": "Straße", "Groß": "groß"}, "phrases": {}, "punctuated": {}}
        self.assertEqual(select(pools, {"strasse": 10, "gross": 20}, 2, 6, 0, 0), ["Straße", "Groß"])

    def test_published_attribution_is_not_redefined_by_mutable_manifest_checksums(self):
        check_attribution_pins(dict(ATTRIBUTION_PINS))
        for name in ATTRIBUTION_PINS:
            hashes = dict(ATTRIBUTION_PINS, **{name: "0" * 64})
            with self.assertRaisesRegex(ValueError, "attribution pin mismatch"):
                check_attribution_pins(hashes)

    def test_invalid_forms_and_non_nfc_are_not_silently_rewritten(self):
        self.assertFalse(literal("Ha\u0308user"))
        self.assertFalse(literal("Haus123"))
        self.assertFalse(literal("a"))
        self.assertFalse(literal("дом"))
        pools = {k: {} for k in ["letters", "phrases", "punctuated"]}
        with self.assertRaises(ValueError): collect_entry({"lang_code": "de", "pos": "noun", "word": "Haus", "forms": [42]}, pools)
        for count in [True, 0, -1]:
            with self.assertRaises(ValueError): select(pools, {}, count, 17, 0, 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dictionary", type=Path)
    parser.add_argument("--wordfreq-wheel", type=Path)
    parser.add_argument("--output-root", type=Path, default=Path.cwd())
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--self-test", action="store_true")
    mode.add_argument("--check-bundled", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return 0 if unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Contracts)).wasSuccessful() else 1
    if args.check_bundled:
        verify_bundled(args.output_root)
        return 0
    require(args.dictionary is not None and args.wordfreq_wheel is not None, "provide --dictionary and --wordfreq-wheel")
    bands, notice = read_frequency(args.wordfreq_wheel)
    pools = read_dictionary(args.dictionary)
    publish(artifacts(pools, bands, notice), args.output_root, args.check)
    print("German source reproduction " + ("checked" if args.check else "prepared"))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, OSError) as error:
        print("German preparation failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
