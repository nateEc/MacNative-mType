#!/usr/bin/env python3
"""Reproduce literal modern Greek practice forms from independent pinned sources."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import unicodedata
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE_URL = "https://kaikki.org/dictionary/Greek/kaikki.org-dictionary-Greek.jsonl"
SOURCE_SHA = "acd0c0ead297157e4092934198bebd525f4cef6d4aea8361a56a6ecaadfb9696"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/small_el.msgpack.gz"
MEMBER_SHA = "9ec327293a1657eac51518d6506e387dda453b548e506f47ef6e720592c1d9c9"
REVISION = "kaikki-en-el-20261030-literal-wordfreq-v1"
BASE_ALPHABET = frozenset("αβγδεζηθικλμνξοπρςστυφχψωάέήίόύώ")
ALPHABET = BASE_ALPHABET | set("ΐϊϋ")
PARTS = set("noun name verb adj adv article pron det conj intj interj prep postp num particle phrase abbrev participle gerund contraction onomatopoeia onomatopeia prep_phrase".split())
REJECTED_LEXICAL_TAGS = frozenset({"misspelling", "proscribed", "nonstandard"})
SPECS = {"basic": (209, 12), "1k": (993, 16), "5k": (4963, 20), "10k": (9936, 21), "25k": (24836, 21)}
LEGACY = "πρωί παράθυρο χαρτί ακτή άνεμος άσκηση προσοχή ήρεμος καθαρός λίμνη δρόμος τραπέζι φως ταξίδι υπομονή στιγμή πόλη βροχή σιωπή κατεύθυνση αστέρι σημείωση κήπος ανάσα μικρός χρόνος άνοιξη νησί φίλος βιβλίο".split()
SWIFT = Path("Sources/Typebar/GreekCorpus.generated.swift")
NOTICE = Path("Resources/GreekCorpusNotices.txt")
ROWS = Path("Resources/GreekCorpusSources.txt")
MANIFEST = Path("Compatibility/greek-corpus.json")
PUBLISHED = {
    str(SWIFT): "09c349f3439d6fd802034fa3d5298ab89ba197e26e8318475699484a5b9b8034",
    str(ROWS): "d4293d9beacfb0f55073de7fbc97a9d3646aa88b78e7c2212fb9b6f823d455a2",
    str(NOTICE): "6114b322cfea791f73db6deda897225cbe6b33889b6f83be1e51006573787ab2",
}
MANIFEST_SHA = "3ae9f0cf45b7d6770d38e11f1b41e0d5adf967d3dcfb9b6b95ae60af2f0243f4"


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def literal(word):
    return (type(word) is str and 1 <= len(word) <= 21 and set(word) <= ALPHABET
        and word == unicodedata.normalize("NFC", word))


def alphabet_for(name):
    return BASE_ALPHABET if name == "basic" else ALPHABET - {"ΐ"} if name == "1k" else ALPHABET


def collect_entry(entry, forms):
    require(type(entry) is dict, "entry must be an object")
    if entry.get("lang_code") != "el" or entry.get("pos") not in PARTS:
        return
    title = entry.get("word")
    require(type(title) is str and title and not any(c in title for c in "\t\r\n"), "invalid dictionary title")
    senses = entry.get("senses", [])
    require(type(senses) is list and all(type(s) is dict for s in senses), "invalid senses array")
    sense_tags = [s.get("tags", []) for s in senses]
    require(all(type(tags) is list and all(type(t) is str for t in tags) for tags in sense_tags), "invalid sense tags")
    if sense_tags and all(REJECTED_LEXICAL_TAGS.intersection(tags) for tags in sense_tags):
        return
    rows = entry.get("forms", [])
    require(type(rows) is list, "invalid forms array")
    for row in [{"form": title, "tags": []}] + rows:
        require(type(row) is dict and type(row.get("form")) is str, "invalid form object")
        tags = row.get("tags", [])
        require(type(tags) is list and all(type(t) is str for t in tags), "invalid form tags")
        if REJECTED_LEXICAL_TAGS.intersection(tags) or any(t in {"table-tags", "inflection-template", "romanization", "class"} or t.startswith("error-") for t in tags):
            continue
        word = row["form"]
        if literal(word):
            forms.setdefault(word, title)


def read_dictionary(path):
    require(unicodedata.unidata_version == "15.0.0", "preparation requires Unicode 15.0.0")
    require(sha(path.read_bytes()) == SOURCE_SHA, "Greek dictionary immutable pin mismatch")
    forms, rows = {}, 0
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            collect_entry(json.loads(line), forms)
            rows += 1
    return forms, rows


def read_frequency(path):
    require(sha(path.read_bytes()) == WHEEL_SHA, "wordfreq wheel immutable pin mismatch")
    import msgpack
    require(msgpack.__version__ == "1.1.2", "preparation requires msgpack 1.1.2")
    with zipfile.ZipFile(path) as archive:
        packed = archive.read(MEMBER)
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode()
    require(sha(packed) == MEMBER_SHA, "Greek member immutable pin mismatch")
    bins = msgpack.unpackb(gzip.decompress(packed), raw=False)
    require(type(bins) is list and bins[0] == {"format": "cB", "version": 1}, "unsupported frequency format")
    bands = {}
    for index, words in enumerate(bins[1:]):
        require(type(words) is list and all(type(w) is str for w in words) and words == sorted(set(words)), "invalid frequency bin")
        for word in words:
            require(word not in bands, "duplicate frequency token")
            bands[word] = index
    require("## License" in metadata, "release license missing")
    return bands, metadata[metadata.index("## License"):].strip() + "\n"


def band(word, bands):
    # wordfreq 3.1.1 preprocesses Greek NFC text, then Unicode casefolds it.
    # Lookup normalization never changes the literal practice spelling.
    return bands.get(word.casefold())


def priority(word, bands):
    value = band(word, bands)
    return (0, value, word) if value is not None else (1, 0, word)


def select(forms, bands, name, previous):
    count, maximum = SPECS[name]
    alphabet = alphabet_for(name)
    candidates = [w for w in forms if len(w) <= maximum and set(w) <= alphabet
        and (name != "basic" or band(w, bands) is not None)]
    ordered = sorted(candidates, key=lambda w: priority(w, bands))
    chosen = set(LEGACY if name == "basic" else previous)
    require(chosen <= set(ordered) and len(chosen) <= count and len(ordered) >= count, "insufficient literal candidates")
    for length in {1, maximum}:
        if not any(len(w) == length for w in chosen):
            word = next((w for w in ordered if len(w) == length), None)
            require(word is not None, "literal length boundary missing")
            chosen.add(word)
    for character in sorted(alphabet):
        if not any(character in w for w in chosen):
            word = next((w for w in ordered if character in w), None)
            require(word is not None, "literal character boundary missing")
            chosen.add(word)
    require(len(chosen) <= count, "required forms exceed pool size")
    for word in ordered:
        if len(chosen) == count:
            break
        chosen.add(word)
    return sorted(chosen, key=lambda w: priority(w, bands)), len(ordered)


def native(pools):
    text = "// Literal independent Greek forms; no spelling, accent or sigma adaptation.\n"
    text += "// CC BY-SA 4.0. Full attribution and per-word source titles are retained.\n"
    text += "enum GreekCorpus {\n  static let revision = " + json.dumps(REVISION) + "\n"
    for name, words in pools.items():
        text += '  static let ' + ("basic" if name == "basic" else "words" + name) + ': [String] = """\n'
        text += "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    return (text + "}\n").encode()


def artifacts(dictionary, wheel):
    forms, source_rows = read_dictionary(dictionary)
    bands, frequency_notice = read_frequency(wheel)
    pools, details, previous = {}, {}, []
    for name, (count, maximum) in SPECS.items():
        words, capacity = select(forms, bands, name, previous)
        require(len(words) == len(set(words)) == count and min(map(len, words)) == 1 and max(map(len, words)) == maximum, "published boundaries differ")
        pools[name] = words
        details[name] = {"count": count, "minimumLength": 1, "maximumLength": maximum,
            "eligibleLiteralForms": capacity, "wholeObserved": sum(band(w, bands) is not None for w in words),
            "characters": "".join(sorted(set("".join(words)))), "wordsSHA256": sha(("\n".join(words) + "\n").encode())}
        previous = words
    rows = "# word\tsourceTitle\twholeTokenBand\n"
    for word in pools["25k"]:
        value = band(word, bands)
        rows += "\t".join([word, forms[word], "" if value is None else str(value)]) + "\n"
    notice = ("Typebar independent modern Greek corpus\nRevision: " + REVISION + "\n\n"
        "English Wiktionary contributors, extracted by Kaikki.org / Wiktextract.\n"
        "Source: " + SOURCE_URL + "\nSnapshot SHA-256: " + SOURCE_SHA + "\n"
        "Index reports extraction 2026-10-25 from enwiktionary dump 2026-10-01.\n"
        "This is postprocessed Kaikki data, not a complete raw Wiktextract dump.\n"
        "Only lang_code=el and supported lexical parts of speech are selected;\n"
        "romanization, template and extraction-error forms are excluded.\n"
        "Forms explicitly tagged misspelling, proscribed or nonstandard are excluded;\n"
        "entries whose senses all carry these tags cannot supply practice words.\n"
        "Entries with another unmarked sense remain eligible. These mechanical checks\n"
        "do not certify the semantics or normative quality of every remaining form.\n"
        "All selected forms are literal NFC lowercase modern Greek spellings.\n"
        "No accent removal, polytonic conversion, recasing, sigma replacement,\n"
        "transliteration, affix synthesis or padding is performed on practice values.\n"
        "The independent selection does not claim identical vocabulary or frequency distribution.\n"
        "Per-word titles identify English Wiktionary contributor pages:\n"
        "https://en.wiktionary.org/wiki/ followed by the percent-encoded sourceTitle.\n"
        "Dictionary selection: Creative Commons Attribution-ShareAlike 4.0 International.\n"
        "https://creativecommons.org/licenses/by-sa/4.0/\n\n"
        "wordfreq 3.1.1 wheel SHA-256: " + WHEEL_SHA + "\nMember: " + MEMBER
        + "\nMember SHA-256: " + MEMBER_SHA + "\n"
        "Whole-token bands use the release's Unicode casefold lookup, including final sigma\n"
        "and decomposed dialytika-tonos keys. Displayed words remain unchanged.\n"
        "Bands are observations, not usage counts. Empty fields mean no whole-token observation;\n"
        "they are not zero and no component estimates are substituted.\n\n" + frequency_notice).encode()
    outputs = {SWIFT: native(pools), ROWS: rows.encode(), NOTICE: notice}
    document = {"schemaVersion": 1, "revision": REVISION, "sourceURL": SOURCE_URL,
        "sourceSHA256": SOURCE_SHA, "dictionaryRows": source_rows, "wordfreqWheelSHA256": WHEEL_SHA,
        "frequencyMember": MEMBER, "frequencyMemberSHA256": MEMBER_SHA,
        "frequencyLookup": "literal NFC spelling then Unicode casefold; display unchanged",
        "pools": details, "artifacts": {str(p): sha(b) for p, b in outputs.items()}}
    outputs[MANIFEST] = (json.dumps(document, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    return outputs


def verify_bundled(root):
    require(bool(PUBLISHED) and sha((root / MANIFEST).read_bytes()) == MANIFEST_SHA, "immutable manifest pin mismatch")
    doc = json.loads((root / MANIFEST).read_text())
    require(doc["schemaVersion"] == 1 and doc["revision"] == REVISION and doc["artifacts"] == PUBLISHED, "unsupported corpus manifest")
    for path, digest in PUBLISHED.items():
        require(sha((root / path).read_bytes()) == digest, "artifact immutable pin mismatch: " + path)
    text = (root / SWIFT).read_text()
    matches = re.findall(r'static let (basic|words1k|words5k|words10k|words25k): \[String\] = """\n(.*?)\n"""', text, re.S)
    pools = {("basic" if k == "basic" else k[5:]): v.splitlines() for k, v in matches}
    require(len(matches) == len(pools) == 5 and list(pools) == list(SPECS) and native(pools) == text.encode(), "native template mismatch")
    previous = set(LEGACY)
    for name, words in pools.items():
        count, maximum = SPECS[name]
        require(len(words) == len(set(words)) == count and previous <= set(words), "duplicate or non-nested pool")
        require(min(map(len, words)) == 1 and max(map(len, words)) == maximum, "length boundaries differ")
        require(all(literal(w) for w in words) and set("".join(words)) == alphabet_for(name), "modern character boundaries differ")
        require(sha(("\n".join(words) + "\n").encode()) == doc["pools"][name]["wordsSHA256"], "pool pin mismatch")
        previous = set(words)
    rows = [line.split("\t") for line in (root / ROWS).read_text().splitlines() if not line.startswith("#")]
    require(len(rows) == 24836 and all(len(r) == 3 for r in rows), "incomplete source mapping")
    require([r[0] for r in rows] == pools["25k"], "source order mismatch")
    require(all(literal(w) and bool(title) and (not value or value.isdigit()) for w, title, value in rows), "invalid literal source trace")
    print("Greek bundled integrity passed")


class Contracts(unittest.TestCase):
    def test_literal_accents_and_final_sigma(self):
        for word in ["άνεμος", "φως", "ΐ", "προϋπόθεση", "α"]:
            self.assertTrue(literal(word))

    def test_no_silent_adaptation(self):
        for word in ["Πόλη", "πόλη", "ὁδός", "λόγος-λέξη", "λέξη λέξη", "ϙ", "abc", "ΰ"]:
            self.assertFalse(literal(word))

    def test_frequency_keys_do_not_rewrite_practice_spelling(self):
        self.assertEqual(band("άνεμος", {"άνεμοσ": 7}), 7)
        self.assertEqual(band("ΐ", {"ι\u0308\u0301": 8}), 8)
        self.assertIsNone(band("φως", {}))

    def test_language_and_romanization_rejection(self):
        forms = {}
        collect_entry({"lang_code": "grc", "pos": "noun", "word": "λόγος"}, forms)
        collect_entry({"lang_code": "el", "pos": "noun", "word": "Μάιος", "forms": [{"form": "μαΐου", "tags": ["romanization"]}]}, forms)
        self.assertEqual(forms, {})

    def test_literal_forms_keep_their_source_title(self):
        forms = {}
        collect_entry({"lang_code": "el", "pos": "noun", "word": "Μάιος", "forms": [{"form": "μαΐου", "tags": ["genitive"]}]}, forms)
        self.assertEqual(forms, {"μαΐου": "Μάιος"})

    def test_bad_source_structures_fail_explicitly(self):
        for value in [None, {"lang_code": "el", "pos": "noun", "word": "λέξη\t"}, {"lang_code": "el", "pos": "noun", "word": "λέξη", "forms": "bad"}]:
            with self.assertRaises(ValueError):
                collect_entry(value, {})

    def test_exclusively_rejected_senses_cannot_supply_practice_forms(self):
        for tag in ["misspelling", "proscribed", "nonstandard"]:
            forms = {}
            collect_entry({"lang_code": "el", "pos": "noun", "word": "λάθος",
                "senses": [{"tags": [tag]}]}, forms)
            self.assertEqual(forms, {})
        mixed = {}
        collect_entry({"lang_code": "el", "pos": "noun", "word": "λέξη",
            "senses": [{"tags": ["nonstandard"]}, {"tags": []}]}, mixed)
        self.assertEqual(mixed, {"λέξη": "λέξη"})

    def test_rejected_form_is_excluded_without_discarding_valid_lemma(self):
        forms = {}
        collect_entry({"lang_code": "el", "pos": "noun", "word": "βράδυ",
            "forms": [{"form": "βράδι", "tags": ["misspelling"]}]}, forms)
        self.assertEqual(forms, {"βράδυ": "βράδυ"})


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--check-bundled", action="store_true")
    p.add_argument("--check", action="store_true")
    p.add_argument("--dictionary", type=Path)
    p.add_argument("--wordfreq-wheel", type=Path)
    p.add_argument("--output-root", type=Path, default=ROOT)
    a = p.parse_args()
    if a.self_test:
        return 0 if unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Contracts)).wasSuccessful() else 1
    if a.check_bundled:
        verify_bundled(a.output_root)
        return 0
    require(a.dictionary and a.wordfreq_wheel, "pinned Greek dictionary and wheel required")
    outputs = artifacts(a.dictionary, a.wordfreq_wheel)
    require(bool(PUBLISHED) and {str(p): sha(b) for p, b in outputs.items() if p != MANIFEST} == PUBLISHED, "immutable artifact pins required")
    require(sha(outputs[MANIFEST]) == MANIFEST_SHA, "immutable manifest pin mismatch")
    if not a.check:
        require(not any((a.output_root / p).exists() for p in outputs), "refusing to overwrite artifacts")
    for path, data in outputs.items():
        target = a.output_root / path
        if a.check:
            require(target.read_bytes() == data, "source reproduction mismatch: " + str(path))
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    print("Greek source reproduction checked" if a.check else "Greek corpus prepared")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
