#!/usr/bin/env python3
"""Prepare seven independent Romanian pools from pinned literal dictionary forms.

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

SOURCE_URL = "https://kaikki.org/dictionary/Romanian/kaikki.org-dictionary-Romanian.jsonl"
SOURCE_SHA = "ffe246750b41118a22f10f9a3e38fd2811528b6a850bf433104da297d1767b9d"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/small_ro.msgpack.gz"
MEMBER_SHA = "c17fe82952ed209bb45b95c56cb5c7f077ca921a84578c3807d48ddc1dd842e2"
REVISION = "kaikki-en-ro-20261029-wordfreq-3.1.1-v1"
COUNTS = {"1k": 1000, "5k": 5000, "10k": 10000, "25k": 25000, "50k": 50000, "100k": 100000, "200k": 200000}
LIMITS = dict(zip(COUNTS, [19, 23, 25, 34, 25, 31, 50]))
PUNCTUATION_TARGETS = dict(zip(COUNTS, [21, 95, 202, 474, 957, 1912, 3891]))
# Independently selected, literally attested examples retain contractions,
# imperatives, an open prefix and multiple hyphens; no spelling is invented.
REQUIRED_HYPHENS = ["într-o", "s-a", "mi-a", "dă-mi", "n-am", "anti-", "cha-cha-cha-uri"]
PARTS = frozenset("noun name verb adj adv article pron det conj intj prep postp num particle phrase abbrev prefix suffix affix infix participle contraction onomatopoeia interfix prep_phrase".split())
SWIFT = Path("Sources/Typebar/RomanianCorpus.generated.swift")
MANIFEST = Path("Compatibility/romanian-corpus.json")
NOTICES = Path("Resources/RomanianCorpusNotices.txt")
SOURCES = Path("Resources/RomanianCorpusSources.txt")
ATTRIBUTION_PINS = {
    str(NOTICES): "10f2182bae65b351531bd71fabff0f2cb5b9d7d9265b397c8f00f2bbc5c5a36b",
    str(SOURCES): "6e09fd1384e5a807584b21a573298c195593bcc707f8c88d1db35013b1f76d15",
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


def spelling(word, limit=50):
    if not (type(word) is str and 1 <= len(word) <= limit and word == word.lower()
            and word == unicodedata.normalize("NFC", word)):
        return False
    if not all(c == "-" or c.isalpha() and unicodedata.name(c, "").startswith("LATIN ") for c in word):
        return False
    return (not word.startswith("-") and not word.endswith("--")
            and all(part and part.isalpha() for part in word.rstrip("-").split("-")))


def collect_entry(item, pools):
    require(type(item) is dict, "dictionary entry must be an object")
    if item.get("lang_code") != "ro" or item.get("pos") not in PARTS:
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
        if spelling(word):
            pool = pools["hyphen" if "-" in word else "letters"]
            old = pool.get(word)
            # English-extractor source labels such as "declension" identify
            # table kinds, not wiki page titles. Attribute to the entry lemma.
            if old is None or (len(lemma), lemma) < (len(old), old):
                pool[word] = lemma


def read_dictionary(path):
    require(unicodedata.unidata_version == "15.0.0", "source preparation requires Unicode 15.0.0")
    require(file_digest(path) == SOURCE_SHA, "Romanian dictionary snapshot SHA-256 mismatch")
    pools = {"letters": {}, "hyphen": {}}
    with path.open(encoding="utf-8") as source:
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
    require(digest(packed) == MEMBER_SHA, "Romanian frequency member SHA-256 mismatch")
    data = msgpack.unpackb(gzip.decompress(packed), raw=False)
    require(type(data) is list and data and data[0] == {"format": "cB", "version": 1}, "unsupported frequency format")
    require("## License" in metadata, "wordfreq release notices missing")
    return frequency_bands(data[1:]), metadata[metadata.index("## License"):].strip() + "\n"


def priority(word, bands):
    band = bands.get(word.casefold())
    if band is None:
        band = max((bands.get(w.casefold(), 10**9) for w in word.split("-") if w), default=10**9)
    return band, word


def select(pools, bands, count, limit, punctuation_target, required):
    require(all(type(n) is int and n > 0 for n in [count, limit, punctuation_target]), "invalid selection limits")
    ranked = {k: sorted((w for w in pool if len(w) <= limit), key=lambda w: priority(w, bands)) for k, pool in pools.items()}
    require(len(required) == len(set(required)) and all(w in ranked["hyphen"] for w in required), "required hyphen example not attested")
    punctuation_count = min(punctuation_target, len(ranked["hyphen"]))
    require(punctuation_count >= len(required) and count > punctuation_count, "invalid punctuation section")
    chosen_hyphens = required + [w for w in ranked["hyphen"] if w not in required][:punctuation_count - len(required)]
    needed = count - punctuation_count
    require(len(ranked["letters"]) >= needed, "insufficient literal dictionary forms; never pad")
    words = ranked["letters"][:needed]
    longest = min(ranked["letters"], key=lambda w: (-len(w), priority(w, bands)))
    if len(longest) > max(map(len, words)):
        words[-1] = longest
    words += chosen_hyphens
    require(len(words) == len(set(words)) == count, "selection must be exact and unique")
    return sorted(words, key=lambda w: priority(w, bands))


def native_source(scales):
    text = ("// Generated by Scripts/prepare-romanian-corpus.py; do not edit.\n"
            "// Literal Romanian Wiktionary forms; independent wordfreq ordering.\n"
            "// CC BY-SA 4.0 adapted selection; notices and entry mapping accompany the app.\n"
            "enum RomanianCorpus {\n" + f'  static let revision = "{REVISION}"\n')
    for scale, words in scales.items():
        text += f'  static let words{scale}: [String] = """\n' + "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    return (text + "}\n").encode()


def shape(words):
    return {"count": len(words), "uniqueCount": len(set(words)), "minimumLength": min(map(len, words)),
            "maximumLength": max(map(len, words)), "punctuationCount": sum("-" in w for w in words),
            "nonASCIICount": sum(not w.isascii() for w in words),
            "trailingHyphenCount": sum(w.endswith("-") for w in words),
            "maximumHyphens": max(w.count("-") for w in words)}


def check_attribution_pins(hashes):
    require(set(ATTRIBUTION_PINS) == {str(NOTICES), str(SOURCES)}
            and all(hashes.get(name) == sha for name, sha in ATTRIBUTION_PINS.items()),
            "published attribution pin mismatch; mutable manifest hashes are insufficient")


def artifacts(pools, bands, release_notices):
    scales = {k: select(pools, bands, n, LIMITS[k], PUNCTUATION_TARGETS[k], REQUIRED_HYPHENS) for k, n in COUNTS.items()}
    union = {w for words in scales.values() for w in words}
    sources = ("# Literal practice form\tEnglish Wiktionary source page title\n"
               "# Page: https://en.wiktionary.org/wiki/<URL-encoded title>#Romanian\n"
               "# Contributors: https://en.wiktionary.org/w/index.php?title=<URL-encoded title>&action=history\n"
               + "".join(w + "\t" + pools["hyphen" if "-" in w else "letters"][w] + "\n" for w in sorted(union))).encode()
    notices = ("Typebar independent Romanian corpus — revision 1\n"
               "Romanian-language headwords and inflected forms from English Wiktionary\n"
               "contributors, extracted and postprocessed by Kaikki.org / Wiktextract.\n"
               "Selection and ordering adapted by Typebar contributors (2026), CC BY-SA 4.0.\n"
               "https://creativecommons.org/licenses/by-sa/4.0/\n"
               "https://en.wiktionary.org/wiki/Wiktionary:Copyrights\n"
               "https://kaikki.org/dictionary/Romanian/index.html\n\n"
               "Postprocessed snapshot retrieved 2026-10-29:\n" + SOURCE_URL + "\nSHA-256: " + SOURCE_SHA + "\n"
               "Kaikki reports extraction 2026-10-25 from enwiktionary dump 2026-10-01.\n"
               "This is the postprocessed language-specific dataset, not the raw dump.\n\n"
               "Changes: lang_code=ro, applicable lexical parts of speech, literal lowercase\n"
               "NFC Latin forms, ASCII internal or trailing hyphens, length at most 50.\n"
               "Exclude table tags, inflection templates, romanization, class and error tags.\n"
               "English source labels (declension/conjugation) are not page titles: map each\n"
               "form to its actual entry lemma in RomanianCorpusSources.txt, with contributor\n"
               "history URL templates. No definitions, examples, images, audio or phonetics.\n"
               "Rank with wordfreq observations; absent whole-form ranks use the rarest\n"
               "hyphen component as an estimate, unknown last. Reserve seven literally\n"
               "attested hyphen examples and a literal longest eligible letter form per scale.\n"
               "Punctuation counts may be below reference targets; never generate filler.\n"
               "Not a pure frequency cutoff or a quality/difficulty/distribution parity claim.\n"
               "Extraction errors, archaic forms, names, loans or offensive words may remain.\n"
               "Basic Romanian and captured historical prompts/metrics remain unchanged.\n\n"
               "Tatu Ylonen, Wiktextract: Wiktionary as Machine-Readable Structured Data,\n"
               "LREC 2022, pp. 1317–1325. https://aclanthology.org/2022.lrec-1.140/\n\n"
               "=== wordfreq 3.1.1 release metadata ===\n" + release_notices).encode()
    generated = {SWIFT: native_source(scales), NOTICES: notices, SOURCES: sources}
    manifest = {"schemaVersion": 1, "revision": REVISION,
                "dictionary": {"url": SOURCE_URL, "sha256": SOURCE_SHA, "languageCode": "ro", "edition": "en", "postprocessed": True, "retrievedDate": "2026-10-29"},
                "wordfreq": {"version": "3.1.1", "wheelSHA256": WHEEL_SHA, "member": MEMBER, "memberSHA256": MEMBER_SHA},
                "preparation": {"unicodeVersion": "15.0.0", "msgpackVersion": "1.1.2", "runtimeDependencies": []},
                "available": {k: len(v) for k, v in pools.items()}, "requiredLiteralHyphens": REQUIRED_HYPHENS,
                "scales": {k: {"shape": shape(w), "wordsSHA256": digest(("\n".join(w) + "\n").encode())} for k, w in scales.items()},
                "sourceMapCount": len(union), "filesSHA256": {str(k): digest(v) for k, v in generated.items()},
                "dataLicense": "CC-BY-SA-4.0 adapted selection; retain notices and entry map",
                "limits": "Literal spelling is not extraction quality, frequency, difficulty or distribution parity; 200k longest field remains below reference 50."}
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
            and m["dictionary"]["languageCode"] == "ro" and m["dictionary"]["edition"] == "en" and m["dictionary"]["postprocessed"] is True
            and m["wordfreq"]["wheelSHA256"] == WHEEL_SHA and m["wordfreq"]["member"] == MEMBER and m["wordfreq"]["memberSHA256"] == MEMBER_SHA, "source pin mismatch")
    require(set(m["filesSHA256"]) == {str(SWIFT), str(NOTICES), str(SOURCES)}, "file inventory mismatch")
    check_attribution_pins(m["filesSHA256"])
    for name, sha in m["filesSHA256"].items():
        require(file_digest(root / name) == sha, "bundled file hash mismatch: " + name)
    data = (root / SWIFT).read_text()
    matches = re.findall(r'  static let words(1k|5k|10k|25k|50k|100k|200k): \[String\] = """\n(.*?)"""', data, re.S)
    scales = {k: body.splitlines() for k, body in matches}
    require(len(matches) == len(scales) == len(COUNTS) and list(scales) == list(COUNTS)
            and set(m["scales"]) == set(COUNTS) and native_source(scales) == data.encode(), "native template mismatch")
    require(m["requiredLiteralHyphens"] == REQUIRED_HYPHENS, "required practice examples changed")
    for k, words in scales.items():
        require(len(words) == len(set(words)) == COUNTS[k] and all(spelling(w, LIMITS[k]) for w in words), "invalid native selection")
        require(shape(words) == m["scales"][k]["shape"] and digest(("\n".join(words) + "\n").encode()) == m["scales"][k]["wordsSHA256"], "native data mismatch")
        require(set(REQUIRED_HYPHENS) <= set(words), "hyphen practice examples missing")
    rows = [r.split("\t") for r in (root / SOURCES).read_text().splitlines() if not r.startswith("#")]
    require(all(len(r) == 2 and all(r) for r in rows), "invalid source mapping")
    require(len(rows) == len({r[0] for r in rows}) == m["sourceMapCount"]
            and {r[0] for r in rows} == {w for words in scales.values() for w in words}, "source mapping coverage mismatch")
    print("Romanian bundled integrity passed (seven pools; source reproduction is stronger)")


class Contracts(unittest.TestCase):
    def test_metadata_errors_and_other_languages_are_not_words(self):
        p = {"letters": {}, "hyphen": {}}
        collect_entry({"word": "țară", "lang_code": "ro", "pos": "noun", "forms": [
            {"form": "no-table-tags", "tags": ["table-tags"]}, {"form": "ro-noun", "tags": ["inflection-template"]},
            {"form": "inventat", "tags": ["error-unrecognized-form"]}, {"form": "țări", "source": "declension"}]}, p)
        collect_entry({"word": "house", "lang_code": "en", "pos": "noun"}, p)
        self.assertEqual(p, {"letters": {"țară": "țară", "țări": "țară"}, "hyphen": {}})

    def test_literal_lowercase_nfc_and_hyphen_boundaries(self):
        for w in ["școală", "într-o", "anti-", "cha-cha-cha-uri"]:
            self.assertTrue(spelling(w), w)
        for w in ["-ism", "anti--", "a--b", "a b", "România", "s\u0326coala", "x3", ""]:
            self.assertFalse(spelling(w), w)

    def test_no_padding_when_source_is_short(self):
        with self.assertRaisesRegex(ValueError, "never pad"):
            select({"letters": {"a": "a"}, "hyphen": {"anti-": "anti-"}}, {}, 3, 10, 1, ["anti-"])

    def test_counts_reject_bool_and_missing_evidence(self):
        with self.assertRaises(ValueError):
            select({"letters": {}, "hyphen": {}}, {}, True, 10, 1, [])
        with self.assertRaisesRegex(ValueError, "not attested"):
            select({"letters": {"a": "a"}, "hyphen": {}}, {}, 2, 10, 1, ["anti-"])

    def test_short_punctuation_source_is_not_padded_and_longest_is_literal(self):
        p = {"letters": {"a": "a", "ab": "ab", "abcdef": "abcdef"}, "hyphen": {"anti-": "anti-"}}
        self.assertEqual(set(select(p, {"a": 1, "ab": 2, "abcdef": 3}, 3, 6, 2, ["anti-"])), {"a", "abcdef", "anti-"})

    def test_priority_is_explicit_component_estimate(self):
        self.assertEqual(priority("mi-a", {"mi": 2, "a": 1})[0], 2)
        self.assertEqual(priority("mi-a", {"mi-a": 3, "mi": 2})[0], 3)

    def test_frequency_bins_validate_order_types_and_duplicates(self):
        for bins in [[[1]], [["b", "a"]], [["a", "a"]], [["a"], ["a"]], "invalid"]:
            with self.assertRaises(ValueError):
                frequency_bands(bins)

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
    print("Romanian source reproduction " + ("checked" if args.check else "prepared"))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, OSError) as error:
        print("Romanian preparation failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
