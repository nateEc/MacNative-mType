#!/usr/bin/env python3
"""Prepare independent French 600k forms, without reference words or downloads.

Source preparation requires Unicode 15.0.0 and msgpack==1.1.2. Bundled
verification and self-tests use the standard library; no native dependency.
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

SOURCE_URL = "https://kaikki.org/dictionary/downloads/fr/fr-extract.jsonl.gz"
SOURCE_SHA = "823fa6f488e23850075747762d946c730c798d971e93b37fe645863b8f25e377"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/large_fr.msgpack.gz"
MEMBER_SHA = "6f16cd80b9b66c5698ed002becea83ae30d0584c3205f1cf01714ad562c00c8b"
COUNT, MAXIMUM, APOSTROPHES = 633941, 33, 34
REVISION = "kaikki-fr-20261029-wordfreq-3.1.1-large-v1"
SWIFT = Path("Sources/Typebar/FrenchLargeCorpus.generated.swift")
MANIFEST = Path("Compatibility/french-large-corpus.json")
NOTICES = Path("Resources/FrenchLargeCorpusNotices.txt")
SOURCES = Path("Resources/FrenchLargeCorpusSources.txt")
ATTRIBUTION_PINS = {
    str(NOTICES): "e2d4a87a95d12baa8d237ef255238a6d182ebb599291fe6f69b4e6a72e4dd34d",
    str(SOURCES): "5368a9228f493cdb70bd0f9ce60d88828a6e0b5f66ca268296ab5cd3b2cf4a31",
}
PARTS = frozenset("noun verb adj adv name article pron det conj intj prep postp num particle phrase abbrev".split())


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def letters(word):
    return bool(word) and all(c.isalpha() and unicodedata.name(c, "").startswith("LATIN ") for c in word)


def literal(word, maximum=MAXIMUM):
    return (type(word) is str and 1 <= len(word) <= maximum
            and word == word.lower() and word == unicodedata.normalize("NFC", word))


def title(value):
    require(type(value) is str and value and not any(c in value for c in "\t\r\n"), "invalid source title")
    return value


def remember(pool, word, owner):
    old = pool.get(word)
    if old is None or (len(owner), owner) < (len(old), old):
        pool[word] = owner


def collect_entry(item, pools):
    require(type(item) is dict, "dictionary entry must be an object")
    if item.get("lang_code") != "fr" or item.get("pos") not in PARTS:
        return
    lemma = title(item.get("word"))
    if literal(lemma):
        if letters(lemma):
            remember(pools["letters"], lemma, lemma)
        elif lemma.count("'") + lemma.count("’") == 1 and all(letters(w) for w in re.split("['’]", lemma)):
            remember(pools["apostropheHeadwords"], lemma, lemma)
    forms = item.get("forms", [])
    require(type(forms) is list, "forms must be an array")
    for form in forms:
        require(type(form) is dict and type(form.get("form")) is str, "invalid dictionary form")
        word = form["form"]
        if literal(word) and letters(word):
            remember(pools["letters"], word, title(form.get("source") or lemma))


def read_dictionary(path):
    require(unicodedata.unidata_version == "15.0.0", "source preparation requires Unicode 15.0.0")
    require(file_digest(path) == SOURCE_SHA, "French dictionary snapshot SHA-256 mismatch")
    pools = {"letters": {}, "apostropheHeadwords": {}}
    with gzip.open(path, "rt", encoding="utf-8") as source:
        for line in source:
            collect_entry(json.loads(line), pools)
    return pools


def frequency_bands(bins):
    require(type(bins) is list, "frequency bins must be an array")
    result = {}
    for band, words in enumerate(bins):
        require(type(words) is list and all(type(w) is str for w in words), "frequency bin must contain strings")
        require(words == sorted(set(words)), "frequency bins must be sorted and unique")
        for word in words:
            require(word not in result, "token occurs in multiple frequency bins")
            result[word] = band
    return result


def read_frequency(path):
    require(file_digest(path) == WHEEL_SHA, "wordfreq wheel SHA-256 mismatch")
    import msgpack
    require(msgpack.__version__ == "1.1.2", "source preparation requires msgpack==1.1.2")
    with zipfile.ZipFile(path) as archive:
        packed = archive.read(MEMBER)
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode("utf-8")
    require(digest(packed) == MEMBER_SHA, "French frequency member SHA-256 mismatch")
    decoded = msgpack.unpackb(gzip.decompress(packed), raw=False)
    require(type(decoded) is list and decoded and decoded[0] == {"format": "cB", "version": 1}, "unsupported frequency format")
    require("## License" in metadata, "wordfreq release notices missing")
    return frequency_bands(decoded[1:]), metadata[metadata.index("## License"):].strip() + "\n"


def matched_apostrophes(headwords, bands):
    # Match typography for provenance, never manufacture the practice spelling.
    # The actual ASCII form must independently exist in the fixed observations.
    candidates = {}
    for spelling, owner in headwords.items():
        key = spelling.replace("’", "'")
        if key.count("'") == 1 and key in bands:
            row = (spelling, owner)
            if key not in candidates or row < candidates[key]:
                candidates[key] = row
    return candidates


def select(pools, bands, count=COUNT, maximum=MAXIMUM, punctuation_count=APOSTROPHES):
    require(all(type(n) is int for n in [count, maximum, punctuation_count])
            and count > punctuation_count >= 0 and maximum >= 1, "invalid selection limits")
    def priority(word):
        return bands.get(word.casefold(), 10**9), word
    ranked = sorted((w for w in pools["letters"] if len(w) <= maximum), key=priority)
    needed = count - punctuation_count
    require(len(ranked) >= needed, "insufficient literal letter forms; never pad")
    words = ranked[:needed]
    if not any(len(w) == maximum for w in words):
        witness = next((w for w in ranked if len(w) == maximum), None)
        require(witness is not None, "no attested maximum-length form")
        words[-1] = witness
    matches = matched_apostrophes(pools["apostropheHeadwords"], bands)
    punctuated = sorted((w for w in matches if len(w) <= maximum), key=priority)
    require(len(punctuated) >= punctuation_count, "insufficient observed ASCII apostrophe forms; never pad")
    chosen = punctuated[:punctuation_count]
    words += chosen
    require(len(words) == len(set(words)) == count, "selection must be unique")
    return sorted(words, key=priority), {w: matches[w] for w in chosen}, len(matches)


def native_source(words):
    return ("// Generated by Scripts/prepare-french-large-corpus.py; do not edit.\n"
            "// Independent French Wiktionary forms and wordfreq observations.\n"
            "// CC BY-SA 4.0 adapted selection; full notices and source titles accompany the app.\n"
            "enum FrenchLargeCorpus {\n"
            f'  static let revision = "{REVISION}"\n'
            '  static let words: [String] = """\n' + "\n".join(words)
            + '\n""".split(separator: "\\n").map(String.init)\n}\n').encode()


def shape(words):
    return {"count": len(words), "uniqueCount": len(set(words)), "minimumLength": min(map(len, words)),
            "maximumLength": max(map(len, words)), "uppercaseCount": sum(w != w.lower() for w in words),
            "nonASCIICount": sum(not w.isascii() for w in words), "punctuationEntries": sum("'" in w for w in words),
            "asciiApostrophes": sum(w.count("'") for w in words), "spaceEntries": sum(" " in w for w in words)}


def check_attribution_pins(hashes):
    require(set(ATTRIBUTION_PINS) == {str(NOTICES), str(SOURCES)}
            and all(hashes.get(name) == sha for name, sha in ATTRIBUTION_PINS.items()),
            "published attribution pin mismatch; mutable manifest hashes are insufficient")


def artifacts(pools, bands, release_notices):
    words, apostrophes, matched_count = select(pools, bands)
    owners = {w: apostrophes[w][1] if w in apostrophes else pools["letters"][w] for w in words}
    source_map = ("# Practice spelling\tFrench Wiktionary source page title\n"
                  "# Page: https://fr.wiktionary.org/wiki/<URL-encoded title>\n"
                  "# Contributors: https://fr.wiktionary.org/w/index.php?title=<URL-encoded title>&action=history\n"
                  "# Letter forms are literal dictionary forms; 34 ASCII apostrophe forms are literal\n"
                  "# wordfreq observations matched to dictionary typography (details in manifest).\n"
                  + "".join(w + "\t" + owners[w] + "\n" for w in sorted(owners))).encode()
    notices = ("Typebar independent French 600k corpus — revision 1\n"
               "French Wiktionary / Wiktionnaire contributors; Kaikki.org / Wiktextract.\n"
               "Selection and ordering adapted by Typebar contributors (2026), CC BY-SA 4.0.\n"
               "https://creativecommons.org/licenses/by-sa/4.0/\n"
               "https://fr.wiktionary.org/wiki/Wiktionnaire:Licence\n"
               "https://fr.wiktionary.org/wiki/Wiktionnaire:Réutilisation_du_contenu_du_Wiktionnaire\n\n"
               "Dictionary snapshot retrieved 2026-10-29:\n" + SOURCE_URL + "\nSHA-256: " + SOURCE_SHA + "\n"
               "https://kaikki.org/dictionary/rawdata.html\n"
               "https://kaikki.org/frwiktionary/\n\n"
               "Entry titles and contributor-history URL templates accompany this app in\n"
               "FrenchLargeCorpusSources.txt. Inflection tables retain their supplied source\n"
               "page when present. No definitions, examples, images or audio are included.\n\n"
               "Changes: retain existing lowercase NFC Latin-letter forms, lengths 1–33;\n"
               "633,907 literal dictionary forms and 34 literal French wordfreq ASCII\n"
               "apostrophe observations matched to existing dictionary headwords by apostrophe\n"
               "typography only. The original dictionary spelling, observed spelling, source\n"
               "title and frequency band are recorded in the manifest for those 34 forms.\n"
               "Never create a spelling by replacing its punctuation. Rank using case-folded\n"
               "observations; unknown ranks sort last. Retain one actually attested maximum-\n"
               "length form for long-word practice. No filler or invented inflections.\n"
               "Not a pure frequency cutoff or a quality / difficulty / distribution parity\n"
               "claim. Data can include extraction errors, archaic forms, names, loans,\n"
               "colloquial or offensive words.\n\n"
               "Kaikki / Wiktextract: Tatu Ylonen, Wiktextract: Wiktionary as Machine-Readable\n"
               "Structured Data, LREC 2022, pp. 1317–1325.\n"
               "https://aclanthology.org/2022.lrec-1.140/\n\n"
               "=== wordfreq 3.1.1 release metadata ===\n" + release_notices).encode()
    swift = native_source(words)
    generated = {SWIFT: swift, NOTICES: notices, SOURCES: source_map}
    manifest = {"schemaVersion": 1, "revision": REVISION,
                "dictionary": {"url": SOURCE_URL, "sha256": SOURCE_SHA, "retrievedDate": "2026-10-29", "languageCode": "fr"},
                "wordfreq": {"version": "3.1.1", "wheelSHA256": WHEEL_SHA, "member": MEMBER, "memberSHA256": MEMBER_SHA},
                "preparation": {"unicodeVersion": "15.0.0", "msgpackVersion": "1.1.2", "runtimeDependencies": []},
                "available": {"letters": len(pools["letters"]), "apostropheHeadwords": len(pools["apostropheHeadwords"]), "matchedApostropheObservations": matched_count},
                "shape": shape(words), "wordsSHA256": digest(("\n".join(words) + "\n").encode()),
                "maximumLengthWitness": next(w for w in words if len(w) == MAXIMUM and letters(w)),
                "apostropheObservations": [{"word": w, "dictionarySpelling": row[0], "sourceTitle": row[1], "band": bands[w]} for w, row in apostrophes.items()],
                "filesSHA256": {str(k): digest(v) for k, v in generated.items()},
                "sourceMapCount": len(owners), "dataLicense": "CC-BY-SA-4.0 adapted selection; retain notices and entry map",
                "limits": "Source attestation and counts do not prove extraction quality, difficulty or distribution parity."}
    generated[MANIFEST] = (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    return generated


def publish(outputs, root, check):
    check_attribution_pins({str(k): digest(v) for k, v in outputs.items()})
    if check:
        for name, data in outputs.items():
            require((root / name).read_bytes() == data, "artifact mismatch: " + str(name))
    else:
        require(not any((root / name).exists() for name in outputs), "refusing to overwrite artifacts")
        for name, data in outputs.items():
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)


def verify_bundled(root):
    manifest = json.loads((root / MANIFEST).read_text())
    require(type(manifest["schemaVersion"]) is int and manifest["schemaVersion"] == 1
            and manifest["revision"] == REVISION, "unsupported manifest")
    require(manifest["dictionary"]["sha256"] == SOURCE_SHA and manifest["dictionary"]["url"] == SOURCE_URL
            and manifest["wordfreq"]["wheelSHA256"] == WHEEL_SHA and manifest["wordfreq"]["memberSHA256"] == MEMBER_SHA, "source pin mismatch")
    hashes = manifest["filesSHA256"]
    require(set(hashes) == {str(SWIFT), str(NOTICES), str(SOURCES)}, "file inventory mismatch")
    check_attribution_pins(hashes)
    for name, sha in hashes.items():
        require(file_digest(root / name) == sha, "bundled file hash mismatch: " + name)
    swift = (root / SWIFT).read_bytes()
    match = re.search(rb'  static let words: \[String\] = """\n(.*?)"""', swift, re.S)
    require(match is not None, "missing native data section")
    body = match.group(1)
    words = body.decode("utf-8").splitlines()
    require(native_source(words) == swift and digest(body) == manifest["wordsSHA256"], "native data mismatch")
    require(len(words) == len(set(words)) == COUNT and shape(words) == manifest["shape"], "word shape mismatch")
    require(all(literal(w) and (letters(w) or w.count("'") == 1 and all(letters(p) for p in w.split("'"))) for w in words), "invalid native spelling")
    require(manifest["shape"]["asciiApostrophes"] == manifest["shape"]["punctuationEntries"] == APOSTROPHES
            and manifest["shape"]["uppercaseCount"] == manifest["shape"]["spaceEntries"] == 0
            and manifest["shape"]["minimumLength"] == 1 and manifest["shape"]["maximumLength"] == MAXIMUM, "practice limits changed")
    rows = manifest["apostropheObservations"]
    require(type(rows) is list and len(rows) == APOSTROPHES, "missing apostrophe evidence")
    require({r["word"] for r in rows} == {w for w in words if "'" in w}
            and all(r["word"] == r["dictionarySpelling"].replace("’", "'") and type(r["band"]) is int and r["band"] >= 0 for r in rows), "invalid apostrophe provenance")
    pairs = [line.split("\t") for line in (root / SOURCES).read_text().splitlines() if not line.startswith("#")]
    require(all(len(row) == 2 and all(row) for row in pairs), "invalid source map")
    require(len(pairs) == len(dict(pairs)) == manifest["sourceMapCount"] == COUNT and set(dict(pairs)) == set(words), "source map coverage mismatch")
    require(manifest["maximumLengthWitness"] in words and len(manifest["maximumLengthWitness"]) == MAXIMUM, "long-word practice witness missing")
    print("French large bundled integrity passed (633941 forms; source reproduction is stronger)")


class Contracts(unittest.TestCase):
    def test_literal_lowercase_nfc_and_language_gate(self):
        p = {"letters": {}, "apostropheHeadwords": {}}
        collect_entry({"lang_code": "fr", "pos": "noun", "word": "cœur", "forms": [{"form": "cœurs"}]}, p)
        collect_entry({"lang_code": "de", "pos": "noun", "word": "haus"}, p)
        collect_entry({"lang_code": "fr", "pos": "noun", "word": "France"}, p)
        self.assertEqual(p["letters"], {"cœur": "cœur", "cœurs": "cœur"})
        self.assertFalse(literal("e\u0301cole"))

    def test_explicit_inflection_source_is_retained(self):
        p = {"letters": {}, "apostropheHeadwords": {}}
        collect_entry({"lang_code": "fr", "pos": "verb", "word": "lire", "forms": [{"form": "lisant", "source": "Conjugaison:français/lire"}]}, p)
        self.assertEqual(p["letters"]["lisant"], "Conjugaison:français/lire")

    def test_ascii_practice_spellings_must_exist_in_observations(self):
        headwords = {"quelqu’un": "quelqu’un"}
        self.assertEqual(matched_apostrophes(headwords, {}), {})
        self.assertEqual(matched_apostrophes(headwords, {"quelqu'un": 10}), {"quelqu'un": ("quelqu’un", "quelqu’un")})

    def test_no_padding_or_fabricated_long_word(self):
        p = {"letters": {"le": "le"}, "apostropheHeadwords": {}}
        with self.assertRaisesRegex(ValueError, "never pad"): select(p, {}, count=2, maximum=2, punctuation_count=0)
        with self.assertRaisesRegex(ValueError, "maximum-length"): select(p, {}, count=1, maximum=3, punctuation_count=0)

    def test_selection_uses_literal_forms_and_keeps_long_word(self):
        p = {"letters": {"le": "le", "être": "être", "écoles": "école"}, "apostropheHeadwords": {}}
        self.assertEqual(select(p, {"le": 1, "être": 2, "écoles": 3}, count=2, maximum=6, punctuation_count=0)[0], ["le", "écoles"])

    def test_frequency_and_numeric_validation(self):
        for bins in [[["b", "a"]], [["a", "a"]], [["a"], ["a"]], [[1]], "invalid"]:
            with self.assertRaises(ValueError): frequency_bands(bins)
        for count in [True, 0, -1]:
            with self.assertRaises(ValueError): select({"letters": {}, "apostropheHeadwords": {}}, {}, count=count, punctuation_count=0)

    def test_entry_attribution_is_independent_of_input_order(self):
        for owners in [["écoles", "école"], ["école", "écoles"]]:
            p = {}
            for owner in owners: remember(p, "écoles", owner)
            self.assertEqual(p, {"écoles": "école"})

    def test_attribution_pins_cannot_be_redefined_by_manifest(self):
        check_attribution_pins(dict(ATTRIBUTION_PINS))
        for name in ATTRIBUTION_PINS:
            changed = dict(ATTRIBUTION_PINS, **{name: "0" * 64})
            with self.assertRaises(ValueError): check_attribution_pins(changed)


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
    bands, notices = read_frequency(args.wordfreq_wheel)
    pools = read_dictionary(args.dictionary)
    publish(artifacts(pools, bands, notices), args.output_root, args.check)
    print("French large source reproduction " + ("checked" if args.check else "prepared"))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, OSError) as error:
        print("French large preparation failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
