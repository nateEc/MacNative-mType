#!/usr/bin/env python3
"""Prepare literal Russian Wiktionary forms with independent wordfreq ordering.
QA only: no downloads, reference word values, or native runtime dependencies.
"""
import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys
import unicodedata
import unittest
import zipfile

SOURCE_URL = "https://kaikki.org/dictionary/downloads/ru/ru-extract.jsonl.gz"
SOURCE_SHA = "7e30fc4e4b21ff16cde09a501494f25287ae66f9a0f94e770ae826e5003c7698"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/large_ru.msgpack.gz"
MEMBER_SHA = "0440613cc765c14a20fb9483225f2fec4d85e66672809076bcec9b29119f9b43"
REVISION = "kaikki-ru-20261029-wordfreq-3.1.1-v1"
# Aggregate count, minimum/maximum length, maximum fields/field length only.
REFERENCE = {
    "1k": {"C": (2, 6, 6, 1, 6), "L": (993, 1, 15, 1, 15), "P": (1, 6, 6, 1, 6)},
    "5k": {"C": (40, 2, 10, 1, 10), "CS": (2, 14, 20, 2, 10),
           "L": (4927, 1, 17, 1, 17), "P": (2, 3, 9, 1, 9)},
    "10k": {"L": (9934, 1, 21, 1, 21), "P": (62, 5, 24, 1, 24)},
    "25k": {"C": (1209, 2, 17, 1, 17), "CP": (9, 8, 16, 1, 16),
            "L": (24306, 1, 24, 1, 24), "P": (513, 3, 34, 1, 34)},
    "50k": {"C": (2377, 2, 17, 1, 17), "CP": (19, 8, 18, 1, 18),
            "L": (48253, 1, 24, 1, 24), "P": (1033, 3, 34, 1, 34)},
    "375k": {"L": (376058, 1, 49, 1, 49), "P": (34, 5, 16, 1, 16)},
}
# Explicit remaining gaps; never silently shorten a reference boundary.
SPECS = {k: dict(v) for k, v in REFERENCE.items()}
SPECS["375k"]["L"] = (376058, 1, 46, 1, 46)
HYPHENS = dict(zip(SPECS, [1, 1, 1, 3, 3, 2]))
MARKS = {"1k": "-", "5k": "-.", "10k": "-", "25k": "-'", "50k": "-'", "375k": "-′"}
REFERENCE_PUNCTUATION = {"1k": {"-": 1}, "5k": {"-": 1, ".": 1}, "10k": {"-": 62},
    "25k": {"-": 543, "'": 1}, "50k": {"-": 1086, "'": 2}, "375k": {"-": 33, "′": 2}}
PARTS = set("noun name verb adj adv article pron det conj intj interj prep postp num particle phrase abbrev participle gerund contraction onomatopoeia onomatopeia prep_phrase".split())
RESERVED = ["человек", "время", "язык", "ещё", "практика"]
NAMES = ["Россия", "Москва"]
SWIFT = Path("Sources/Typebar/RussianCorpus.generated.swift")
NOTICES = Path("Resources/RussianCorpusNotices.txt")
SOURCES = Path("Resources/RussianCorpusSources.txt")
MANIFEST = Path("Compatibility/russian-corpus.json")
PUBLISHED = {
    str(SWIFT): "b8d9d14b0d087522bb5a5ca8f75937e469a0922bd985566dfa0296142f3a048a",
    str(NOTICES): "c37063392a3eed9ad77d8ba25d3c1f727a413c05dd420341bf1c6ff83d5cc4f7",
    str(SOURCES): "e39ccaf5e7e7d31989b91265b721e9d131b93ed07787cd8ccbd778b68c8204ab",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for part in iter(lambda: f.read(1024 * 1024), b""):
            h.update(part)
    return h.hexdigest()


def eligible(word):
    return (type(word) is str and 1 <= len(word) <= 70
            and word == unicodedata.normalize("NFC", word) and all(word.split(" "))
            and not word.startswith("-") and not word.endswith("-")
            and any(c.isalpha() for c in word)
            and all(c in " -.'′" or (c.isalpha() and unicodedata.name(c, "").startswith("CYRILLIC ")) for c in word))


def input_class(word):
    return "".join(k for k, yes in [("C", any(c.isupper() for c in word)),
        ("P", any(unicodedata.category(c).startswith("P") for c in word)),
        ("S", " " in word)] if yes) or "L"


def collect_entry(item, forms):
    require(type(item) is dict, "dictionary entry must be an object")
    if item.get("lang_code") != "ru" or item.get("pos") not in PARTS:
        return
    lemma = item.get("word")
    require(type(lemma) is str and lemma and not any(c in lemma for c in "\t\r\n"), "invalid source title")
    candidates = item.get("forms", [])
    require(type(candidates) is list, "dictionary forms must be an array")
    for form in [{"form": lemma, "tags": []}] + candidates:
        require(type(form) is dict and type(form.get("form")) is str, "invalid dictionary form")
        tags = form.get("tags", [])
        require(type(tags) is list and all(type(t) is str for t in tags), "invalid form tags")
        if any(t in {"table-tags", "inflection-template", "romanization", "class"} or t.startswith("error-") for t in tags):
            continue
        word = form["form"]
        if eligible(word):
            old = forms.get(word)
            if old is None or (lemma != word, len(lemma), lemma) < (old != word, len(old), old):
                forms[word] = lemma


def read_dictionary(path):
    require(unicodedata.unidata_version == "15.0.0", "source preparation requires Unicode 15.0.0")
    require(file_digest(path) == SOURCE_SHA, "Russian dictionary snapshot SHA-256 mismatch")
    forms, rows = {}, 0
    with gzip.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            collect_entry(json.loads(line), forms); rows += 1
    return forms, rows


def frequency_bands(bins):
    require(type(bins) is list, "frequency bins must be an array")
    result = {}
    for band, words in enumerate(bins):
        require(type(words) is list and all(type(w) is str for w in words), "frequency bins must contain strings")
        require(words == sorted(set(words)), "frequency bins must be sorted and unique")
        for word in words:
            require(word not in result, "duplicate frequency token")
            result[word] = band
    return result


def read_frequency(path):
    require(file_digest(path) == WHEEL_SHA, "wordfreq wheel SHA-256 mismatch")
    import msgpack
    require(msgpack.__version__ == "1.1.2", "source preparation requires msgpack==1.1.2")
    with zipfile.ZipFile(path) as archive:
        packed = archive.read(MEMBER)
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode()
    require(digest(packed) == MEMBER_SHA, "Russian frequency member SHA-256 mismatch")
    bins = msgpack.unpackb(gzip.decompress(packed), raw=False)
    require(type(bins) is list and bins and bins[0] == {"format": "cB", "version": 1}, "unsupported frequency format")
    require("## License" in metadata, "wordfreq release notices missing")
    return frequency_bands(bins[1:]), metadata[metadata.index("## License"):].strip() + "\n"


def rank_evidence(word, bands):
    whole = bands.get(word.casefold())
    parts = [p for p in re.split("[-.'′ ]", word.casefold()) if p]
    estimate = max((bands.get(p, 10**9) for p in parts), default=10**9) if len(parts) > 1 else 10**9
    return whole, estimate if estimate != 10**9 else None


def priority(word, bands):
    whole, estimate = rank_evidence(word, bands)
    return ((0, whole, word.casefold(), word) if whole is not None else
            (1, estimate, word.casefold(), word) if estimate is not None else
            (2, 0, word.casefold(), word))


def fits(word, spec, hyphens):
    _, low, high, fields, field_length = spec
    parts = word.split(" ")
    return low <= len(word) <= high and len(parts) <= fields and max(map(len, parts)) <= field_length and word.count("-") <= hyphens


def select_group(candidates, spec, bands, hyphens, reserved=(), required_marks=()):
    count = spec[0]
    available = sorted((w for w in candidates if fits(w, spec, hyphens)), key=lambda w: priority(w, bands))
    require(len(available) >= count, "insufficient literal dictionary capacity; never pad")
    required = list(reserved)
    require(all(w in available for w in required), "reserved literal form is absent")
    scores = [lambda w: -len(w), len, lambda w: w.count("-"),
              lambda w: len(w.split(" ")), lambda w: max(map(len, w.split(" ")))]
    for mark in required_marks:
        require(any(mark in w for w in available), "required literal punctuation unavailable")
        scores.append(lambda w, mark=mark: mark in w)
    boundaries = [(score, max(map(score, available))) for score in scores]
    while True:
        missing = [(score, target) for score, target in boundaries if not any(score(w) == target for w in required)]
        if not missing: break
        required.append(max(available, key=lambda w: sum(score(w) == target for score, target in missing)))
    required = list(dict.fromkeys(required))
    require(len(required) <= count, "quota cannot preserve literal field boundaries")
    chosen, protected = available[:count], set(required)
    for word in required:
        if word not in chosen:
            at = next((i for i in range(len(chosen)-1, -1, -1) if chosen[i] not in protected), None)
            require(at is not None, "no room for required literal field")
            chosen[at] = word
    return sorted(chosen, key=lambda w: priority(w, bands)), len(available)


def shape(words):
    groups = defaultdict(list)
    for word in words: groups[input_class(word)].append(word)
    return {"count": len(words), "uniqueCount": len(set(words)),
            "groups": {k: [len(v), min(map(len, v)), max(map(len, v)), max(len(w.split(" ")) for w in v),
                           max(len(p) for w in v for p in w.split(" "))] for k, v in sorted(groups.items())},
            "maximumHyphens": max(w.count("-") for w in words),
            "punctuationScalars": dict(sorted(Counter(c for w in words for c in w if unicodedata.category(c).startswith("P")).items()))}


def validate(words, spec):
    require(all(eligible(w) for w in words), "invalid literal Russian form")
    require(len(words) == len(set(words)) == sum(v[0] for v in spec.values())
            and shape(words)["groups"] == {k: list(v) for k, v in spec.items()}, "input-class or field boundary mismatch")


def native_source(scales):
    text = ("// Generated by Scripts/prepare-russian-corpus.py; do not edit.\n"
            "// Russian Wiktionary literal forms; independent wordfreq ordering.\n"
            "// CC BY-SA 4.0 adapted selection; notices and source mapping accompany the app.\n"
            "enum RussianCorpus {\n" + f'  static let revision = "{REVISION}"\n')
    for key, words in scales.items():
        text += f'  static let words{key}: [String] = """\n' + "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    return (text + "}\n").encode()


def artifacts(forms, rows, bands, release_notices):
    groups = defaultdict(list)
    for word in forms: groups[input_class(word)].append(word)
    scales, available = {}, {}
    for key, spec in SPECS.items():
        chosen, available[key] = [], {}
        for kind, contract in spec.items():
            candidates = [w for w in groups[kind] if all(c not in ".'′" or c in MARKS[key] for c in w)]
            words, capacity = select_group(candidates, contract, bands, HYPHENS[key],
                RESERVED if kind == "L" else NAMES if kind == "C" else (),
                [".", "-"] if key == "5k" and kind == "P" else ())
            chosen += words; available[key][kind] = capacity
        validate(chosen, spec)
        scales[key] = sorted(chosen, key=lambda w: priority(w, bands))
    union = set(w for words in scales.values() for w in words)
    source = ("# Literal form\tRussian Wiktionary source page title\twholeCasefoldBand\tcomponentBandEstimate\n"
              "# Pages: https://ru.wiktionary.org/wiki/<URL-encoded title>\n"
              "# Contributors: https://ru.wiktionary.org/w/index.php?title=<URL-encoded title>&action=history\n"
              "# Bands are wordfreq cB bucket indexes, not measured token counts; - means unavailable.\n")
    for word in sorted(union):
        evidence = rank_evidence(word, bands)
        source += word + "\t" + forms[word] + "\t" + "\t".join("-" if b is None else str(b) for b in evidence) + "\n"
    notice = ("Typebar independent Russian corpus — revision 1\n"
              "Russian Wiktionary (Викисловарь) contributors; Kaikki.org / Wiktextract.\n"
              "Selection and ordering adapted by Typebar contributors (2026), CC BY-SA 4.0.\n"
              "https://creativecommons.org/licenses/by-sa/4.0/\n"
              "https://ru.wiktionary.org/\nhttps://kaikki.org/ruwiktionary/\n"
              "https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use#7._Licensing_of_Content\n"
              "https://kaikki.org/dictionary/rawdata.html\n\n"
              "Pinned raw Russian-edition snapshot retrieved 2026-10-29:\n" + SOURCE_URL + "\nSHA-256: " + SOURCE_SHA + "\n\n"
              "Changes: select lang_code=ru lexical parts, literal NFC Cyrillic headwords\n"
              "and inflected forms. No stress stripping, NFC rewriting, recasing, number\n"
              "suffixes, repeated-letter padding or new compounds. Exclude templates,\n"
              "romanizations, error tags and isolated affixes. Keep literal punctuation,\n"
              "case and single spaces. Wordfreq casefold whole-form bands rank first,\n"
              "then estimates from the least frequent component, then unobserved forms.\n"
              "Reserve five ordinary practice words, two existing proper names and actual\n"
              "input boundaries. Band indexes are not observed counts. Literal dictionary\n"
              "forms need not have actual usage observations. Source mapping includes every\n"
              "selected spelling, source page title and separate whole/estimated bands.\n"
              "Largest plain-word boundary is 46 versus reference 49: an open gap, not\n"
              "filled with fabricated characters. Input-class quotas are not lexical,\n"
              "frequency, punctuation distribution, difficulty or language quality parity.\n"
              "Basic Russian, abbreviation/short-form pools and historical records remain\n"
              "unchanged. Definitions, quotations, audio, images and raw source not bundled.\n\n"
              "Tatu Ylonen, Wiktextract: Wiktionary as Machine-Readable Structured Data,\n"
              "LREC 2022, pp. 1317–1325. https://aclanthology.org/2022.lrec-1.140/\n\n"
              "=== wordfreq 3.1.1 release metadata ===\n" + release_notices)
    generated = {SWIFT: native_source(scales), NOTICES: notice.encode(), SOURCES: source.encode()}
    manifest = {"schemaVersion": 1, "revision": REVISION,
                "dictionary": {"url": SOURCE_URL, "sha256": SOURCE_SHA, "edition": "ru", "languageCode": "ru", "retrievedDate": "2026-10-29", "postprocessed": False, "rows": rows, "eligibleForms": len(forms)},
                "frequency": {"wheelSHA256": WHEEL_SHA, "member": MEMBER, "memberSHA256": MEMBER_SHA, "tokens": len(bands), "format": "cB v1"},
                "preparation": {"unicodeVersion": "15.0.0", "msgpackVersion": "1.1.2", "runtimeDependencies": []},
                "referenceGroups": REFERENCE, "remainingBoundaryGaps": {"375k.L.maximumLength": [46, 49], "375k.L.maximumFieldLength": [46, 49]},
                "referencePunctuationScalars": REFERENCE_PUNCTUATION,
                "punctuationScalarDifferences": {k: {c: [shape(w)["punctuationScalars"].get(c, 0), target]
                    for c, target in REFERENCE_PUNCTUATION[k].items() if shape(w)["punctuationScalars"].get(c, 0) != target}
                    for k, w in scales.items()},
                "available": available, "sourceMapCount": len(union),
                "scales": {k: {"shape": shape(w), "wordsSHA256": digest(("\n".join(w) + "\n").encode())} for k, w in scales.items()},
                "filesSHA256": {str(k): digest(v) for k, v in generated.items()}}
    generated[MANIFEST] = (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    return generated


def verify_pins(hashes):
    require(bool(PUBLISHED) and hashes == PUBLISHED, "published pins required; mutable manifest hashes are insufficient")


def verify_bundled(root):
    m = json.loads((root / MANIFEST).read_text())
    require(type(m["schemaVersion"]) is int and m["schemaVersion"] == 1 and m["revision"] == REVISION, "unsupported manifest")
    require(m["dictionary"]["sha256"] == SOURCE_SHA and m["frequency"]["wheelSHA256"] == WHEEL_SHA
            and m["frequency"]["memberSHA256"] == MEMBER_SHA, "source pin mismatch")
    verify_pins(m["filesSHA256"])
    for path, sha in m["filesSHA256"].items(): require(file_digest(root / path) == sha, "bundled file mismatch: " + path)
    text = (root / SWIFT).read_text()
    matches = re.findall(r'  static let words(1k|5k|10k|25k|50k|375k): \[String\] = """\n(.*?)"""', text, re.S)
    scales = {k: body.splitlines() for k, body in matches}
    require(len(matches) == len(scales) == len(SPECS) and list(scales) == list(SPECS)
            and native_source(scales) == text.encode() and set(m["scales"]) == set(SPECS), "native template mismatch")
    rows = [line.split("\t") for line in (root / SOURCES).read_text().splitlines() if not line.startswith("#")]
    require(all(len(row) == 4 and row[0] and row[1] and all(x == "-" or x.isdigit() for x in row[2:]) for row in rows), "invalid source mapping")
    require(len(rows) == len({r[0] for r in rows}) == m["sourceMapCount"], "duplicate source mapping")
    union = set()
    for key, words in scales.items():
        validate(words, SPECS[key]); union.update(words)
        require(m["scales"][key] == {"shape": shape(words), "wordsSHA256": digest(("\n".join(words) + "\n").encode())}, "native content mismatch")
    require({r[0] for r in rows} == union, "source mapping coverage mismatch")
    require(m["referenceGroups"] == json.loads(json.dumps(REFERENCE)), "reference aggregate drift")
    require(m["referencePunctuationScalars"] == REFERENCE_PUNCTUATION, "punctuation aggregate drift")
    require(m["remainingBoundaryGaps"] == {"375k.L.maximumLength": [46, 49],
            "375k.L.maximumFieldLength": [46, 49]}, "undeclared length boundary drift")
    require(m["punctuationScalarDifferences"] == {k: {c: [shape(w)["punctuationScalars"].get(c, 0), target]
            for c, target in REFERENCE_PUNCTUATION[k].items() if shape(w)["punctuationScalars"].get(c, 0) != target}
            for k, w in scales.items()}, "punctuation difference drift")


class Contracts(unittest.TestCase):
    def test_literals_not_stress_stripping_or_padding(self):
        for word in ["время", "ещё", "Москва", "из-за", "ул.", "Новая Земля"]: self.assertTrue(eligible(word))
        for word in ["вре́мя", "-за", "из-", "а  б", "a", "я1", 'я"', "я\\", "я\n"]: self.assertFalse(eligible(word))

    def test_filters_and_stable_source_title(self):
        forms = {}; item = dict(word="время", lang_code="ru", pos="noun", forms=[{"form": "времени", "tags": []}, {"form": "шаблон", "tags": ["inflection-template"]}])
        collect_entry(item, forms); collect_entry(dict(item, lang_code="uk", word="інше"), forms)
        self.assertEqual(forms, {"время": "время", "времени": "время"})
        collect_entry(dict(word="времени", lang_code="ru", pos="noun"), forms)
        self.assertEqual(forms["времени"], "времени")

    def test_frequency_bands_are_not_counts(self):
        b = frequency_bands([["а", "я"], ["время"]])
        self.assertEqual(b["а"], 0); self.assertEqual(rank_evidence("Время", b), (1, None))
        self.assertEqual(rank_evidence("а-я", b), (None, 0))
        self.assertEqual(rank_evidence("а-б", b), (None, None))

    def test_invalid_frequency_layout_rejected(self):
        for bins in [["а"], [["я", "а"]], [["а"], ["а"]]]:
            with self.assertRaises(ValueError): frequency_bands(bins)

    def test_combined_input_classes(self):
        self.assertEqual(input_class("Новая Земля"), "CS")
        self.assertEqual(input_class("Ростов-на-Дону"), "CP")

    def test_boundaries_cover_quota_without_redundant_ties(self):
        chosen, _ = select_group(["Мир", "Дом"], (1, 3, 3, 1, 3), {"мир": 0}, 0)
        self.assertEqual(chosen, ["Мир"])

    def test_source_fields_and_punctuation_are_real(self):
        chosen, _ = select_group(["т.е.", "кое-как", "из-за"], (2, 4, 7, 1, 7), {}, 1)
        self.assertEqual(set(chosen), {"т.е.", "кое-как"})
        self.assertFalse(fits("а-б-в-г", (1, 1, 8, 1, 8), 2))

    def test_small_quota_preserves_both_punctuation_kinds_and_lengths(self):
        words, _ = select_group(["а-б", "др.", "кое-какой"], (2, 3, 9, 1, 9), {"а-б": 0}, 1,
                                required_marks=[".", "-"])
        self.assertEqual(set(words), {"др.", "кое-какой"})

    def test_shortage_fails_instead_of_filling(self):
        with self.assertRaises(ValueError): select_group(["я"], (2, 1, 3, 1, 3), {}, 0)

    def test_published_pin_cannot_be_absent(self):
        with self.assertRaises(ValueError): verify_pins({})


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--dictionary", type=Path); p.add_argument("--frequency-wheel", type=Path)
    p.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parents[1])
    for name in ["self-test", "check-bundled", "check"]: p.add_argument("--" + name, action="store_true")
    args = p.parse_args()
    if args.self_test: return 0 if unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Contracts)).wasSuccessful() else 1
    if args.check_bundled:
        verify_bundled(args.output_root); print("Russian bundled integrity passed (source reproduction is stronger)"); return 0
    require(args.dictionary is not None and args.frequency_wheel is not None, "two fixed source snapshots required")
    forms, rows = read_dictionary(args.dictionary)
    bands, notices = read_frequency(args.frequency_wheel)
    outputs = artifacts(forms, rows, bands, notices)
    verify_pins({str(k): digest(v) for k, v in outputs.items() if k != MANIFEST})
    if args.check:
        for path, data in outputs.items(): require((args.output_root / path).read_bytes() == data, "artifact mismatch: " + str(path))
    else:
        require(not any((args.output_root / path).exists() for path in outputs), "refusing to overwrite artifacts")
        for path, data in outputs.items():
            target = args.output_root / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
    print("Russian source reproduction checked" if args.check else "Russian corpus prepared"); return 0


if __name__ == "__main__":
    sys.exit(main())
