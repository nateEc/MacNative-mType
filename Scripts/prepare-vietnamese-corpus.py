#!/usr/bin/env python3
"""Reproduce independent Vietnamese literal pools; never reads Monkeytype words."""
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
SOURCE = "https://kaikki.org/dictionary/Vietnamese/kaikki.org-dictionary-Vietnamese.jsonl"
SOURCE_SHA = "186cd0a62d876dada70c9761bc05e598c8cf7b9a48e0aa518bab6c649e28d945"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/small_vi.msgpack.gz"
MEMBER_SHA = "bde76e2846f38fc8f4ad5112493d524c0c7f5e5545072b4de773d0a83159f15f"
REVISION = "kaikki-en-vi-20261102-literal-wordfreq-v1"
SPECS = {"basic": (319, 6, 270), "1k": (1000, 7, 870), "5k": (5000, 7, 4450)}
REFERENCE_KEYS = {
    "basic": "abcdeghiklmnopqrstuvxyàáâãéêìíòóôùúýăđĩũơưạảấầẩậắằẳặẹẻẽếểễệỉịọỏốồổỗộớờởợủứừửữự",
    "1k": "abcdeghiklmnopqrstuvxyàáâãèéêìíòóôõùúýăđĩũơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỷỹ",
    "5k": "abcdefghiklmnopqrstuvxyàáâãèéêìíòóôõùúýăđĩũơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ",
}
LEGACY = "sách cửa đường ánh sáng cầu buổi trang nơi mây yên lặng núi hạt giọng bàn ý câu nhìn trải nghiệm khoảng cách bước kiên nhẫn cân bằng làng mưa".split()
PARTS = set("noun verb adj adv name pron num det conj intj prep postp particle phrase abbrev classifier syllable".split())
BAD = {"misspelling", "proscribed", "nonstandard"}
SWIFT = "Sources/Typebar/VietnameseCorpus.generated.swift"
ROWS = "Resources/VietnameseCorpusSources.txt"
NOTICE = "Resources/VietnameseCorpusNotices.txt"
MANIFEST = "Compatibility/vietnamese-corpus.json"
PUBLISHED = {
    SWIFT: "4fab9a4fe33d2af9f467e64957cf5a10cae2aed09d222bd02d32f69bfba6a2cb",
    ROWS: "a38b9321d243ba4222647b0def6e208e98067b75d6fdb45c817cb56359662400",
    NOTICE: "f04e2a8a62a46673e6e2de6ea3720c8bdb646fd65f10a8e1e41bd8aa78aacf12",
    MANIFEST: "a47ee789dd7094abd6ba9a9dcf596100b5a99c271aa4eeea38b3fee7d08ce051",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def literal(word):
    return (type(word) is str and 1 <= len(word) <= 7 and word.isalpha()
            and word == word.lower() and word == unicodedata.normalize("NFC", word))


def collect(entry, forms):
    require(type(entry) is dict, "invalid dictionary entry")
    if entry.get("lang_code") != "vi" or entry.get("pos") not in PARTS:
        return
    senses = entry.get("senses", [])
    require(type(senses) is list, "invalid senses")
    if not senses or all(BAD.intersection(s.get("tags", [])) for s in senses):
        return
    title = entry.get("word")
    require(type(title) is str and not any(c in title for c in "\t\r\n"), "invalid source title")
    rows = entry.get("forms", [])
    require(type(rows) is list, "invalid forms")
    for row in [{"form": title}] + rows:
        require(type(row) is dict and type(row.get("form")) is str, "invalid form")
        tags = row.get("tags", [])
        require(type(tags) is list and all(type(t) is str for t in tags), "invalid tags")
        if BAD.intersection(tags) or any(t in {"romanization", "table-tags", "inflection-template", "class"}
                                        or t.startswith("error-") for t in tags):
            continue
        if literal(row["form"]):
            forms.setdefault(row["form"], ("dictionary", title))


def read_sources(dictionary, wheel):
    require(sha(dictionary.read_bytes()) == SOURCE_SHA, "dictionary pin mismatch")
    forms = {}
    for line in dictionary.open(encoding="utf-8"):
        collect(json.loads(line), forms)
    require(sha(wheel.read_bytes()) == WHEEL_SHA, "wheel pin mismatch")
    import msgpack
    require(msgpack.__version__ == "1.1.2", "requires msgpack 1.1.2")
    with zipfile.ZipFile(wheel) as archive:
        data = archive.read(MEMBER)
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode()
    require(sha(data) == MEMBER_SHA, "frequency member pin mismatch")
    bins = msgpack.unpackb(gzip.decompress(data), raw=False)
    require(bins[0] == {"format": "cB", "version": 1}, "invalid frequency format")
    bands = {}
    for index, words in enumerate(bins[1:]):
        require(type(words) is list and words == sorted(set(words)), "invalid frequency bin")
        for word in words:
            require(type(word) is str and word not in bands, "invalid frequency token")
            bands[word] = index
    for word in LEGACY:
        forms.setdefault(word, ("typebar-legacy", "Typebar authored starter vocabulary"))
    return forms, bands, metadata[metadata.index("## License"):].strip() + "\n"


def priority(word, bands):
    value = bands.get(word)
    return (value is None, value if value is not None else 0, word)


def choose(eligible, required, count, maximum, non_ascii, characters, bands):
    require(required <= eligible, "required literal seed missing")
    limits = {True: non_ascii, False: count - non_ascii}
    chosen = set(required)

    def fits(word):
        category = not word.isascii()
        return sum((not w.isascii()) == category for w in chosen) < limits[category]

    def add_best(candidates, key):
        candidates = [w for w in candidates if w not in chosen and fits(w)]
        require(bool(candidates), "insufficient literal forms for required coverage")
        chosen.add(min(candidates, key=key))

    for length in [1, maximum]:
        if not any(len(w) == length for w in chosen):
            add_best((w for w in eligible if len(w) == length), lambda w: priority(w, bands))
    missing = characters - set("".join(chosen))
    while missing:
        add_best((w for w in eligible if set(w) & missing),
                 lambda w: (-len(set(w) & missing), priority(w, bands)))
        missing = characters - set("".join(chosen))
    for category, limit in limits.items():
        current = {w for w in chosen if (not w.isascii()) == category}
        require(len(current) <= limit, "seed exceeds category quota")
        for word in sorted((w for w in eligible if (not w.isascii()) == category),
                           key=lambda w: priority(w, bands)):
            if len(current) == limit:
                break
            current.add(word)
        require(len(current) == limit, "insufficient literal category")
        chosen.update(current)
    require(len(chosen) == count and set("".join(chosen)) == characters, "selection mismatch")
    return sorted(chosen, key=lambda w: priority(w, bands))


def select(forms, bands):
    pools = {}
    inherited = set(LEGACY)
    for name, (count, maximum, non_ascii) in SPECS.items():
        characters = set(REFERENCE_KEYS[name]) | set("".join(LEGACY))
        eligible = {w for w in forms if len(w) <= maximum and set(w) <= characters}
        pools[name] = choose(eligible, inherited, count, maximum, non_ascii, characters, bands)
        inherited = set(pools[name])
    return pools


def artifacts(dictionary, wheel):
    forms, bands, licenses = read_sources(dictionary, wheel)
    pools = select(forms, bands)
    native = "// Independent literal Vietnamese forms, CC BY-SA 4.0.\n// See bundled per-word provenance; no spelling or numbered-word synthesis.\nenum VietnameseCorpus {\n  static let revision = " + json.dumps(REVISION) + "\n"
    for name, words in pools.items():
        native += '  static let ' + ("basic" if name == "basic" else "words" + name) + ': [String] = """\n' + "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    native += "}\n"
    union = sorted(set().union(*map(set, pools.values())))
    rows = "# word\tsourceKind\tsourceTitle\twordfreqWholeTokenBand (NA means unobserved)\n"
    for word in union:
        kind, title = forms[word]
        value = bands.get(word)
        rows += "\t".join([word, kind, title, "NA" if value is None else str(value)]) + "\n"
    unattested = sorted(w for w in LEGACY if forms[w][0] == "typebar-legacy")
    notice = f"""Typebar independent Vietnamese corpus
Revision: {REVISION}
English Wiktionary contributors, extracted by Kaikki.org / Wiktextract.
Source: {SOURCE}
Snapshot SHA-256: {SOURCE_SHA}
Index reports extraction 2026-10-30 from enwiktionary dump 2026-10-01,
using extractor revisions 19f9a30 and 6f96ddf.
Only literal NFC lowercase alphabetic titles/forms of lang_code=vi and declared
lexical parts of speech are selected. No recasing, phrase splitting, affix
synthesis, numbered padding, definitions, examples or original Monkeytype words.
Misspelling/proscribed/nonstandard-only senses and tagged extraction/template/
romanization forms are excluded. These filters do not certify linguistic quality.
Per-word contributor page: https://en.wiktionary.org/wiki/ + encoded sourceTitle.
Selection is adapted by filtering/ranking; displayed spellings are unchanged.
All 30 old Typebar authored starter words remain in all three nested pools.
Legacy words without selected lexical attestation: {', '.join(unattested) or '(none)'}.
This reports the allowed lexical selection, not absence of raw entries.
The raw kiên entry is romanization and is excluded by that lexical policy.
These retained words are explicitly marked typebar-legacy, not selected
lexical dictionary attestations.
The basic pool retains legacy nhan-with-tilde (nhẫn), adding ẫ to the source
basic typing alphabet; 1k and 5k need no extra legacy typing characters.
The three pools contain 319/1000/5000 options and 270/870/4450 non-ASCII options.
Dictionary selection and frequency data: CC BY-SA 4.0 International.
https://creativecommons.org/licenses/by-sa/4.0/
Source mapping: VietnameseCorpusSources.txt; reproducible selection in the repository.
Vocabulary, ordering, distribution and linguistic quality are not certified
equivalent to Monkeytype. The original source provides only aggregate constraints.

wordfreq 3.1.1 wheel SHA-256: {WHEEL_SHA}
Member: {MEMBER}
Member SHA-256: {MEMBER_SHA}
Ranking uses unchanged whole-token Vietnamese observations. Missing is NA,
not zero and not an estimate from component words. Unobserved forms follow
observed ones. Bands are observations, not usage counts or runtime Zipf support.

""" + licenses
    output = {SWIFT: native.encode(), ROWS: rows.encode(), NOTICE: notice.encode()}
    doc = {"schemaVersion": 1, "revision": REVISION, "source": SOURCE, "sourceSHA256": SOURCE_SHA,
           "wheelSHA256": WHEEL_SHA, "member": MEMBER, "memberSHA256": MEMBER_SHA,
           "legacyUnattested": unattested,
           "legacyAttestationScope": "Selected lexical parts of speech; raw romanization entries are excluded.",
           "artifacts": {p: sha(b) for p, b in output.items()}, "pools": {}}
    for name, words in pools.items():
        characters = set("".join(words))
        doc["pools"][name] = {"count": len(words), "minimumLength": min(map(len, words)),
            "maximumLength": max(map(len, words)), "characters": "".join(sorted(characters)),
            "referenceCharacters": REFERENCE_KEYS[name],
            "legacyExtraCharacters": "".join(sorted(characters - set(REFERENCE_KEYS[name]))),
            "nonASCIIOptions": sum(not w.isascii() for w in words),
            "wholeObserved": sum(w in bands for w in words),
            "wordsSHA256": sha(("\n".join(words) + "\n").encode())}
    output[MANIFEST] = (json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
    return output


def verify_bundled(root):
    require(bool(PUBLISHED), "immutable artifact pins required")
    for name, digest in PUBLISHED.items():
        require(sha((root / name).read_bytes()) == digest, "artifact pin mismatch: " + name)
    doc = json.loads((root / MANIFEST).read_text())
    require(doc["revision"] == REVISION, "revision mismatch")
    for name, digest in doc["artifacts"].items():
        require(sha((root / name).read_bytes()) == digest, "manifest mismatch")
    pools = {("basic" if name == "basic" else name[5:]): text.splitlines()
             for name, text in re.findall(r'static let (basic|words1k|words5k): \[String\] = """\n(.*?)\n"""',
                                         (root / SWIFT).read_text(), re.S)}
    require(list(pools) == list(SPECS), "missing native pools")
    rows = [line.split("\t") for line in (root / ROWS).read_text().splitlines() if not line.startswith("#")]
    require(all(len(row) == 4 and row[1] in {"dictionary", "typebar-legacy"} and row[2]
                and (row[3] == "NA" or row[3].isdigit()) for row in rows), "invalid provenance")
    provenance = {row[0]: row for row in rows}
    require(len(rows) == len(provenance) and set(provenance) == set().union(*map(set, pools.values())), "incomplete provenance")
    inherited = set(LEGACY)
    for name, words in pools.items():
        count, maximum, non_ascii = SPECS[name]
        require(len(words) == len(set(words)) == count and inherited <= set(words), "count/nesting/legacy mismatch")
        require(all(literal(w) for w in words) and min(map(len, words)) == 1
                and max(map(len, words)) == maximum, "literal/length mismatch")
        require(set("".join(words)) == set(REFERENCE_KEYS[name]) | set("".join(LEGACY)), "typing key mismatch")
        require(sum(not w.isascii() for w in words) == non_ascii, "category mismatch")
        require(doc["pools"][name]["wordsSHA256"] == sha(("\n".join(words) + "\n").encode()), "pool pin mismatch")
        require(doc["pools"][name]["wholeObserved"] == sum(provenance[w][3] != "NA" for w in words), "observation mismatch")
        inherited = set(words)


class ContractTests(unittest.TestCase):
    def test_literal_requires_nfc_lowercase_single_orthographic_units(self):
        for word in ["đ", "nhẫn", "nghiêng"]:
            self.assertTrue(literal(word))
        for word in ["e\u0301", "Nhẫn", "hai từ", "qvi01", "mưa-đêm", ""]:
            self.assertFalse(literal(word))

    def test_source_filter_rejects_wrong_language_and_bad_only_senses(self):
        forms = {}
        entry = {"lang_code": "vi", "pos": "noun", "word": "mưa", "senses": [{"tags": ["nonstandard"]}]}
        collect(entry, forms)
        self.assertFalse(forms)
        entry["senses"].append({})
        entry["forms"] = [{"form": "abc", "tags": ["romanization"]}]
        collect(entry, forms)
        self.assertEqual(forms, {"mưa": ("dictionary", "mưa")})
        entry["word"] = "abc"; entry["lang_code"] = "id"
        collect(entry, forms)
        self.assertNotIn("abc", forms)
        collect({"lang_code": "vi", "pos": "romanization", "word": "kiên", "senses": [{}]}, forms)
        self.assertNotIn("kiên", forms)

    def test_selection_preserves_quota_coverage_and_unobserved_seeds(self):
        words = choose({"a", "ab", "b", "á", "bá"}, {"a"}, 4, 2, 2, set("abá"), {"á": 0, "b": 1})
        self.assertEqual(len(words), 4)
        self.assertIn("a", words)
        self.assertEqual(sum(not w.isascii() for w in words), 2)
        self.assertEqual(set("".join(words)), set("abá"))
        self.assertLess(priority("á", {"á": 0}), priority("a", {"á": 0}))
        with self.assertRaises(ValueError):
            choose({"a", "á"}, set(), 4, 2, 2, set("abá"), {})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dictionary", type=Path)
    parser.add_argument("--wordfreq-wheel", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--check-bundled", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests))
        raise SystemExit(not result.wasSuccessful())
    if args.check_bundled:
        verify_bundled(ROOT)
        print("Vietnamese pinned corpus/provenance check passed")
        return
    require(args.dictionary and args.wordfreq_wheel and args.output, "dictionary, wheel and output directory are required")
    output = artifacts(args.dictionary, args.wordfreq_wheel)
    if PUBLISHED:
        require({name: sha(data) for name, data in output.items()} == PUBLISHED, "reproduction pins mismatch")
    for name, data in output.items():
        path = args.output / name
        if args.check:
            require(path.read_bytes() == data, "source reproduction mismatch: " + name)
        else:
            require(not path.exists(), "refusing to overwrite artifact: " + name)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    print("Vietnamese source reproduction checked" if args.check else "Vietnamese corpus prepared")


if __name__ == "__main__":
    main()
