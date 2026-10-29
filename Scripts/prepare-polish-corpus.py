#!/usr/bin/env python3
"""Prepare six independent Polish pools from pinned literal dictionary forms.

Source preparation requires Unicode 15.0.0 and msgpack 1.1.2. No downloads,
dependency installation or reference words. Bundled checks use stdlib only.
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

SOURCE_URL = "https://kaikki.org/dictionary/downloads/pl/pl-extract.jsonl.gz"
SOURCE_SHA = "15bfa944d77f8cc25b3597c4c08c26025f33fbdc60b9f68be16b84874042453e"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/large_pl.msgpack.gz"
MEMBER_SHA = "fac63e49c49ea2e39dd8a48152d7e54cec0920abbc59993088063ed5d9b528c2"
REVISION = "kaikki-pl-20261029-wordfreq-3.1.1-v1"
COUNTS = {"2k": 2338, "5k": 5000, "10k": 10000, "20k": 20000, "40k": 40000, "200k": 199979}
LIMITS = dict(zip(COUNTS, [17, 18, 18, 21, 21, 33]))
UPPERCASE = dict(zip(COUNTS, [50, 0, 0, 0, 0, 38649]))
CASED_LIMITS = {"2k": 10, "200k": 22}
ABBREVIATIONS = ["np.", "m.in.", "itd."]
REQUIRED_NAMES = ["Polska", "Warszawa", "Kraków", "Łódź"]
PARTS = frozenset("noun name verb adj adv article pron det conj intj prep postp num particle phrase abbrev prefix suffix affix infix participle contraction onomatopoeia interfix prep_phrase".split())
SWIFT = Path("Sources/Typebar/PolishCorpus.generated.swift")
MANIFEST = Path("Compatibility/polish-corpus.json")
NOTICES = Path("Resources/PolishCorpusNotices.txt")
SOURCES = Path("Resources/PolishCorpusSources.txt")
ATTRIBUTION_PINS = {
    str(NOTICES): "0fbf25994170d9616c82a1379643a826f27c3783ee39c03ecff5daa4dd7d1a99",
    str(SOURCES): "ab2970669aefae320181ddba3d516fb1f240298635797aabbf33e9262162f523",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def spelling(word, limit=33):
    return (type(word) is str and 1 <= len(word) <= limit
            and word == unicodedata.normalize("NFC", word)
            and all(c.isalpha() and unicodedata.name(c, "").startswith("LATIN ") for c in word))


def collect_entry(item, pools):
    require(type(item) is dict, "dictionary entry must be an object")
    if item.get("lang_code") != "pl" or item.get("pos") not in PARTS:
        return
    lemma = item.get("word")
    require(type(lemma) is str and lemma and not any(c in lemma for c in "\t\r\n"), "invalid source page title")
    forms = item.get("forms", [])
    require(type(forms) is list, "dictionary forms must be an array")
    for form in [{"form": lemma, "tags": []}] + forms:
        require(type(form) is dict and type(form.get("form")) is str, "invalid dictionary form")
        tags = form.get("tags", [])
        require(type(tags) is list and all(type(t) is str for t in tags), "invalid form tags")
        if any(t in {"table-tags", "inflection-template", "romanization", "class"} or t.startswith("error-") for t in tags):
            continue
        word = form["form"]
        kind = None
        if spelling(word):
            if word == word.lower():
                kind = "lower"
            elif any(c.isupper() for c in word):
                kind = "cased"
        elif word == lemma and word in ABBREVIATIONS:
            kind = "abbreviations"
        if kind:
            old = pools[kind].get(word)
            if old is None or (len(lemma), lemma) < (len(old), old):
                pools[kind][word] = lemma


def read_dictionary(path):
    require(unicodedata.unidata_version == "15.0.0", "source preparation requires Unicode 15.0.0")
    require(file_digest(path) == SOURCE_SHA, "Polish dictionary snapshot SHA-256 mismatch")
    pools = {"lower": {}, "cased": {}, "abbreviations": {}}
    with gzip.open(path, "rt", encoding="utf-8") as source:
        for line in source:
            collect_entry(json.loads(line), pools)
    return pools


def frequency_bands(bins):
    require(type(bins) is list, "frequency bins must be an array")
    result = {}
    for band, words in enumerate(bins):
        require(type(words) is list and all(type(w) is str for w in words), "frequency bins must contain strings")
        require(words == sorted(set(words)), "frequency bins must be sorted and unique")
        for word in words:
            require(word not in result, "frequency token occurs in multiple bins")
            result[word] = band
    return result


def read_frequency(path):
    require(file_digest(path) == WHEEL_SHA, "wordfreq wheel SHA-256 mismatch")
    import msgpack
    require(msgpack.__version__ == "1.1.2", "source preparation requires msgpack==1.1.2")
    with zipfile.ZipFile(path) as archive:
        packed = archive.read(MEMBER)
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode()
    require(digest(packed) == MEMBER_SHA, "Polish frequency member SHA-256 mismatch")
    data = msgpack.unpackb(gzip.decompress(packed), raw=False)
    require(type(data) is list and data and data[0] == {"format": "cB", "version": 1}, "unsupported frequency format")
    require("## License" in metadata, "wordfreq release notices missing")
    return frequency_bands(data[1:]), metadata[metadata.index("## License"):].strip() + "\n"


def priority(word, bands):
    band = bands.get(word.casefold())
    if band is None:
        band = max((bands.get(w.casefold(), 10**9) for w in word.split(".") if w), default=10**9)
    return band, word


def select(pools, bands, count, limit, uppercase, abbreviations, names, case_limit=None):
    case_limit = limit if case_limit is None else case_limit
    require(all(type(n) is int and n >= 0 for n in [count, limit, uppercase])
            and count > uppercase + len(abbreviations) and limit > 0
            and type(case_limit) is int and 0 < case_limit <= limit, "invalid selection limits")
    require(len(names) == len(set(names)) and len(names) <= uppercase
            and all(w in pools["cased"] and len(w) <= case_limit for w in names), "required proper-name spelling not attested")
    require(len(abbreviations) == len(set(abbreviations))
            and all(w in pools["abbreviations"] and len(w) <= limit for w in abbreviations), "abbreviation spelling not attested")
    ranked = {k: sorted((w for w in pools[k] if len(w) <= (case_limit if k == "cased" else limit)),
                       key=lambda w: priority(w, bands)) for k in ["lower", "cased"]}
    needed = count - uppercase - len(abbreviations)
    require(len(ranked["lower"]) >= needed and len(ranked["cased"]) >= uppercase, "insufficient literal dictionary forms; never pad")
    words = ranked["lower"][:needed]
    longest = min(ranked["lower"], key=lambda w: (-len(w), priority(w, bands)))
    if len(longest) > max(map(len, words)):
        words[-1] = longest
    cased = names + [w for w in ranked["cased"] if w not in names][:uppercase - len(names)]
    if uppercase > len(names):
        longest_cased = min(ranked["cased"], key=lambda w: (-len(w), priority(w, bands)))
        if len(longest_cased) > max(map(len, cased)):
            cased[-1] = longest_cased
    words += cased + abbreviations
    require(len(words) == len(set(words)) == count, "selection must be exact and unique")
    return sorted(words, key=lambda w: priority(w, bands))


def native_source(scales):
    text = ("// Generated by Scripts/prepare-polish-corpus.py; do not edit.\n"
            "// Literal Polish Wiktionary forms; independent wordfreq ordering.\n"
            "// CC BY-SA 4.0 adapted selection; notices and entry mapping accompany the app.\n"
            "enum PolishCorpus {\n" + f'  static let revision = "{REVISION}"\n')
    for scale, words in scales.items():
        text += f'  static let words{scale}: [String] = """\n' + "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    return (text + "}\n").encode()


def shape(words):
    return {"count": len(words), "uniqueCount": len(set(words)), "minimumLength": min(map(len, words)),
            "maximumLength": max(map(len, words)), "uppercaseCount": sum(any(c.isupper() for c in w) for w in words),
            "maximumCasedLength": max((len(w) for w in words if any(c.isupper() for c in w)), default=0),
            "punctuationCount": sum("." in w for w in words), "periodCount": sum(w.count(".") for w in words),
            "nonASCIICount": sum(not w.isascii() for w in words)}


def check_attribution_pins(hashes):
    require(set(ATTRIBUTION_PINS) == {str(NOTICES), str(SOURCES)}
            and all(hashes.get(name) == sha for name, sha in ATTRIBUTION_PINS.items()),
            "published attribution pin mismatch; mutable manifest hashes are insufficient")


def artifacts(pools, bands, release_notices):
    scales = {k: select(pools, bands, n, LIMITS[k], UPPERCASE[k],
                        ABBREVIATIONS if k == "2k" else [], REQUIRED_NAMES if UPPERCASE[k] else [],
                        CASED_LIMITS.get(k, LIMITS[k])) for k, n in COUNTS.items()}
    require(all(shape(scales[k])["maximumCasedLength"] == n for k, n in CASED_LIMITS.items()),
            "no attested maximum-length proper-name practice form")
    union = {w for words in scales.values() for w in words}
    owners = {w: min((pool[w] for pool in pools.values() if w in pool), key=lambda t: (len(t), t)) for w in union}
    sources = ("# Literal practice form\tPolish Wiktionary source page title\n"
               "# Page: https://pl.wiktionary.org/wiki/<URL-encoded title>\n"
               "# Contributors: https://pl.wiktionary.org/w/index.php?title=<URL-encoded title>&action=history\n"
               + "".join(w + "\t" + owners[w] + "\n" for w in sorted(union))).encode()
    notices = ("Typebar independent Polish corpus — revision 1\n"
               "Polish-language headwords and inflected forms from Polish Wiktionary\n"
               "(Wikisłownik) contributors, extracted by Kaikki.org / Wiktextract.\n"
               "Selection and ordering adapted by Typebar contributors (2026), CC BY-SA 4.0.\n"
               "https://creativecommons.org/licenses/by-sa/4.0/\n"
               "https://pl.wiktionary.org/wiki/Wikisłownik:Prawa_autorskie\n"
               "https://kaikki.org/dictionary/rawdata.html\n\n"
               "Raw dictionary snapshot retrieved 2026-10-29:\n" + SOURCE_URL + "\nSHA-256: " + SOURCE_SHA + "\n\n"
               "Changes: lang_code=pl, applicable lexical parts of speech, literal NFC Latin\n"
               "letter headwords and inflected forms up to 33 characters. Keep lowercase\n"
               "and existing cased forms separate; never capitalize a lowercase observation\n"
               "to manufacture a proper name. Exclude metadata / romanization / error tags.\n"
               "2k keeps three literally attested period abbreviations: np., m.in., itd.\n"
               "The cased pools reserve Polska, Warszawa, Kraków and Łódź; each spelling\n"
               "must already be supplied by the dictionary. Keep a literal longest eligible\n"
               "lowercase form per scale, never repeated-letter or concatenated filler.\n"
               "Also retain literal cased length boundaries: 2k reaches 10 characters,\n"
               "200k reaches 22. Overall length alone cannot prove proper-name coverage.\n"
               "PolishCorpusSources.txt maps every practice spelling to its source entry\n"
               "lemma with page / contributor-history URL templates. Definitions, examples,\n"
               "images, audio, phonetics and raw JSONL are not bundled.\n"
               "Ordering uses case-folded wordfreq observations; absent whole-form ranks\n"
               "use the rarest period-delimited part as an estimate, unknown last. Not a\n"
               "pure frequency cutoff or a quality/difficulty/distribution parity claim.\n"
               "Extraction errors, archaic forms, names, loans or offensive words may remain.\n"
               "Basic Polish and captured historical prompts/metrics remain unchanged.\n\n"
               "Tatu Ylonen, Wiktextract: Wiktionary as Machine-Readable Structured Data,\n"
               "LREC 2022, pp. 1317–1325. https://aclanthology.org/2022.lrec-1.140/\n\n"
               "=== wordfreq 3.1.1 release metadata ===\n" + release_notices).encode()
    generated = {SWIFT: native_source(scales), NOTICES: notices, SOURCES: sources}
    manifest = {"schemaVersion": 1, "revision": REVISION,
                "dictionary": {"url": SOURCE_URL, "sha256": SOURCE_SHA, "languageCode": "pl", "edition": "pl", "postprocessed": False, "retrievedDate": "2026-10-29"},
                "wordfreq": {"version": "3.1.1", "wheelSHA256": WHEEL_SHA, "member": MEMBER, "memberSHA256": MEMBER_SHA},
                "preparation": {"unicodeVersion": "15.0.0", "msgpackVersion": "1.1.2", "runtimeDependencies": []},
                "available": {k: len(v) for k, v in pools.items()}, "requiredLiteralNames": REQUIRED_NAMES, "literalAbbreviations": ABBREVIATIONS,
                "casedLengthLimits": CASED_LIMITS,
                "scales": {k: {"shape": shape(w), "wordsSHA256": digest(("\n".join(w) + "\n").encode())} for k, w in scales.items()},
                "sourceMapCount": len(union), "filesSHA256": {str(k): digest(v) for k, v in generated.items()},
                "dataLicense": "CC-BY-SA-4.0 adapted selection; retain notices and entry map",
                "limits": "Literal spelling and aggregate counts are not extraction quality, frequency, difficulty or distribution parity."}
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
    m = json.loads((root / MANIFEST).read_text())
    require(type(m["schemaVersion"]) is int and m["schemaVersion"] == 1 and m["revision"] == REVISION, "unsupported manifest")
    require(m["dictionary"]["url"] == SOURCE_URL and m["dictionary"]["sha256"] == SOURCE_SHA
            and m["dictionary"]["languageCode"] == "pl" and m["dictionary"]["edition"] == "pl" and m["dictionary"]["postprocessed"] is False
            and m["wordfreq"]["wheelSHA256"] == WHEEL_SHA and m["wordfreq"]["member"] == MEMBER and m["wordfreq"]["memberSHA256"] == MEMBER_SHA, "source pin mismatch")
    require(set(m["filesSHA256"]) == {str(SWIFT), str(NOTICES), str(SOURCES)}, "file inventory mismatch")
    check_attribution_pins(m["filesSHA256"])
    for name, sha in m["filesSHA256"].items():
        require(file_digest(root / name) == sha, "bundled file hash mismatch: " + name)
    data = (root / SWIFT).read_text()
    matches = re.findall(r'  static let words(2k|5k|10k|20k|40k|200k): \[String\] = """\n(.*?)"""', data, re.S)
    scales = {k: body.splitlines() for k, body in matches}
    require(len(matches) == len(scales) == len(COUNTS) and list(scales) == list(COUNTS)
            and set(m["scales"]) == set(COUNTS) and native_source(scales) == data.encode(), "native template mismatch")
    require(m["requiredLiteralNames"] == REQUIRED_NAMES and m["literalAbbreviations"] == ABBREVIATIONS
            and m["casedLengthLimits"] == CASED_LIMITS, "practice evidence changed")
    for k, words in scales.items():
        abbreviations = ABBREVIATIONS if k == "2k" else []
        require(len(words) == len(set(words)) == COUNTS[k] and all(spelling(w, LIMITS[k]) or w in abbreviations for w in words), "invalid native selection")
        require(shape(words) == m["scales"][k]["shape"] and digest(("\n".join(words) + "\n").encode()) == m["scales"][k]["wordsSHA256"], "native data mismatch")
        require(shape(words)["uppercaseCount"] == UPPERCASE[k]
                and {w for w in words if "." in w} == set(abbreviations), "practice sections changed")
        if UPPERCASE[k]:
            require(set(REQUIRED_NAMES) <= set(words), "literal proper-name examples missing")
            require(shape(words)["maximumCasedLength"] == CASED_LIMITS[k], "proper-name length boundary missing")
    rows = [r.split("\t") for r in (root / SOURCES).read_text().splitlines() if not r.startswith("#")]
    require(all(len(r) == 2 and all(r) for r in rows), "invalid source mapping")
    require(len(rows) == len({r[0] for r in rows}) == m["sourceMapCount"]
            and {r[0] for r in rows} == {w for words in scales.values() for w in words}, "source mapping coverage mismatch")
    print("Polish bundled integrity passed (six pools; source reproduction is stronger)")


class Contracts(unittest.TestCase):
    def test_language_gate_and_metadata_are_not_words(self):
        p = {"lower": {}, "cased": {}, "abbreviations": {}}
        collect_entry({"word": "świat", "lang_code": "pl", "pos": "noun", "forms": [
            {"form": "metadata", "tags": ["table-tags"]}, {"form": "template", "tags": ["inflection-template"]},
            {"form": "filler", "tags": ["error-unrecognized-form"]}, {"form": "świata"}]}, p)
        collect_entry({"word": "world", "lang_code": "en", "pos": "noun"}, p)
        self.assertEqual(p, {"lower": {"świat": "świat", "świata": "świat"}, "cased": {}, "abbreviations": {}})

    def test_literal_case_and_abbreviation_are_never_invented(self):
        p = {"lower": {}, "cased": {}, "abbreviations": {}}
        for w in ["Polska", "polska", "Łódź", "np.", "m.in.", "itd."]:
            collect_entry({"word": w, "lang_code": "pl", "pos": "noun"}, p)
        self.assertEqual(set(p["cased"]), {"Polska", "Łódź"})
        self.assertEqual(set(p["abbreviations"]), set(ABBREVIATIONS))
        self.assertEqual(set(p["lower"]), {"polska"})

    def test_literal_nfc_letter_limits(self):
        for w in ["świat", "Polska", "Łódź"]:
            self.assertTrue(spelling(w))
        for w in ["s\u0301wiat", "a b", "x3", "-", "np.", ""]:
            self.assertFalse(spelling(w))

    def test_no_padding_when_source_is_short(self):
        with self.assertRaisesRegex(ValueError, "never pad"):
            select({"lower": {"a": "a"}, "cased": {}, "abbreviations": {}}, {}, 2, 10, 0, [], [])

    def test_counts_and_unattested_edits_are_rejected(self):
        p = {"lower": {"a": "a"}, "cased": {}, "abbreviations": {}}
        with self.assertRaises(ValueError):
            select(p, {}, True, 10, 0, [], [])
        with self.assertRaisesRegex(ValueError, "not attested"):
            select(p, {}, 3, 10, 1, [], ["Polska"])
        with self.assertRaisesRegex(ValueError, "not attested"):
            select(p, {}, 3, 10, 0, ["np."], [])

    def test_longest_form_is_literal_and_casefold_is_only_ranking(self):
        p = {"lower": {"a": "a", "ab": "ab", "abcdef": "abcdef"}, "cased": {"Łódź": "Łódź"}, "abbreviations": {}}
        self.assertEqual(set(select(p, {"a": 1, "ab": 2, "łódź": 1}, 3, 6, 1, [], ["Łódź"])), {"a", "abcdef", "Łódź"})

    def test_frequency_bins_validate_order_types_and_duplicates(self):
        for bins in [[[1]], [["b", "a"]], [["a", "a"]], [["a"], ["a"]], "invalid"]:
            with self.assertRaises(ValueError):
                frequency_bands(bins)
        self.assertEqual(priority("m.in.", {"m": 1, "in": 3})[0], 3)

    def test_cased_length_boundary_is_separate_from_lowercase_boundary(self):
        p = {"lower": {"a": "a", "ab": "ab", "abcdef": "abcdef"},
             "cased": {"A": "A", "Ab": "Ab", "Abcdef": "Abcdef"}, "abbreviations": {}}
        words = select(p, {"a": 1, "ab": 2, "A": 1, "Ab": 2}, 4, 6, 2, [], ["A"], case_limit=6)
        self.assertEqual(set(words), {"a", "abcdef", "A", "Abcdef"})
        with self.assertRaises(ValueError):
            select(p, {}, 4, 6, 2, [], ["A"], case_limit=True)

    def test_attribution_cannot_be_redefined_by_manifest(self):
        check_attribution_pins(dict(ATTRIBUTION_PINS))
        for name in ATTRIBUTION_PINS:
            with self.assertRaises(ValueError):
                check_attribution_pins(dict(ATTRIBUTION_PINS, **{name: "0" * 64}))


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
    publish(artifacts(read_dictionary(args.dictionary), bands, notices), args.output_root, args.check)
    print("Polish source reproduction " + ("checked" if args.check else "prepared"))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, OSError) as error:
        print("Polish preparation failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
