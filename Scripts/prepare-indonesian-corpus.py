#!/usr/bin/env python3
"""Reproduce independent literal Indonesian pools; never reads Monkeytype words."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "https://kaikki.org/dictionary/Indonesian/kaikki.org-dictionary-Indonesian.jsonl"
SOURCE_SHA = "3ebda79fc5ed7abd1995e2a46294362f3f9282bcf74b892b4d9588d76bdc97f5"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/small_id.msgpack.gz"
MEMBER_SHA = "6fd891027cd6395b5c038c0e6402fa7e107ffd8973f862053246b897beb1bcd3"
REVISION = "kaikki-en-id-20261102-literal-wordfreq-v1"
SPECS = {"basic": (310, 11, 0, 0), "1k": (1020, 14, 2, 2), "10k": (13769, 13, 0, 494)}
CHARACTERS = {"basic": "abcdefghijklmnoprstuwy", "1k": "-ITabcdefghijklmnoprstuvwyz", "10k": "-abcdefghijklmnopqrstuvwxyz"}
LEGACY = "pagi jendela kertas pantai angin latihan perhatian tenang jelas danau jalan meja cahaya perjalanan kesabaran sejenak kota hujan hening arah bintang catatan taman napas kecil waktu musim perahu teman harapan".split()
PARTS = set("noun verb adj adv name pron num det conj intj prep postp particle phrase abbrev".split())
BAD = {"misspelling", "proscribed", "nonstandard"}
SWIFT = "Sources/Typebar/IndonesianCorpus.generated.swift"
ROWS = "Resources/IndonesianCorpusSources.txt"
NOTICE = "Resources/IndonesianCorpusNotices.txt"
MANIFEST = "Compatibility/indonesian-corpus.json"
PUBLISHED = {
    SWIFT: "a0953937edc6546cf4416079f1b3d93ddfe5f727cbe112feac810a3c8b5d4200",
    ROWS: "7cd3fa91e630540e10247be3156a64bd9dcabc619fc36894aff343e694dd7175",
    NOTICE: "98e8a634b0c4ce73e61c9a6039ecc1c5c7be9d440e6e4df1a5a959a7c3510b6c",
    MANIFEST: "7b619c18a42050dae1ccb140c72d19d0baa3ea6ab269db1cc78f8b8e26e2e77d",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def literal(word):
    return type(word) is str and 2 <= len(word) <= 14 and re.fullmatch(r"[A-Za-z]+(?:-[A-Za-z]+)*", word) is not None


def collect(entry, forms):
    require(type(entry) is dict, "invalid dictionary entry")
    if entry.get("lang_code") != "id" or entry.get("pos") not in PARTS:
        return
    senses = entry.get("senses", [{}])
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
        if BAD.intersection(tags) or any(t in {"romanization", "table-tags", "inflection-template", "class"} or t.startswith("error-") for t in tags):
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
        require(type(words) is list and words == sorted(set(words)), "invalid bin")
        for word in words:
            require(type(word) is str and word not in bands, "invalid frequency token")
            bands[word] = index
    for word in LEGACY:
        require(word in bands, "legacy word lacks declared frequency observation")
        forms.setdefault(word, ("typebar-legacy", "Typebar authored starter vocabulary"))
    return forms, bands, metadata[metadata.index("## License"):].strip() + "\n"


def priority(word, bands):
    value = bands.get(word.lower())  # ASCII lookup only; display is never changed.
    return (value is None, value if value is not None else 0, word)


def select(forms, bands):
    pools = {}
    for name, (count, maximum, upper, punct) in SPECS.items():
        eligible = {w for w in forms if len(w) <= maximum and set(w) <= set(CHARACTERS[name])}
        required = set(LEGACY) | set(pools.get("basic", []))
        require(required <= eligible, "required literal seed missing")
        result = set()
        for category, amount in [("upper", upper), ("hyphen", punct), ("plain", count - upper - punct)]:
            def matches(word):
                return (any(c.isupper() for c in word) and "-" not in word) if category == "upper" else (word.islower() and ("-" in word) == (category == "hyphen"))
            candidates = sorted((w for w in eligible if matches(w)), key=lambda w: priority(w, bands))
            chosen = required.intersection(candidates)
            if category == "upper":
                for character in CHARACTERS[name]:
                    if character.isupper() and not any(character in w for w in chosen):
                        chosen.add(next(w for w in candidates if character in w))
            if category == "plain" and not any(len(w) == maximum for w in chosen):
                chosen.add(next(w for w in candidates if len(w) == maximum))
            require(len(chosen) <= amount, "seed exceeds category quota")
            for word in candidates:
                if len(chosen) == amount:
                    break
                chosen.add(word)
            require(len(chosen) == amount, "insufficient literal forms")
            result.update(chosen)
        require(len(result) == count and required <= result, "selection mismatch")
        require(set("".join(result)) == set(CHARACTERS[name]), "typing character coverage mismatch")
        pools[name] = sorted(result, key=lambda w: priority(w, bands))
    return pools


def artifacts(dictionary, wheel):
    forms, bands, licenses = read_sources(dictionary, wheel)
    pools = select(forms, bands)
    native = "// Independent literal Indonesian selection, CC BY-SA 4.0.\n// See bundled notices and per-word source titles; no spelling synthesis.\nenum IndonesianCorpus {\n  static let revision = " + json.dumps(REVISION) + "\n"
    for name, words in pools.items():
        native += '  static let ' + ("basic" if name == "basic" else "words" + name) + ': [String] = """\n' + "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    native += "}\n"
    union = sorted(set().union(*map(set, pools.values())))
    rows = "# word\tsourceKind\tsourceTitle\twordfreqWholeTokenBand (NA means unobserved)\n"
    for word in union:
        kind, title = forms[word]
        value = bands.get(word.lower())
        rows += "\t".join([word, kind, title, "NA" if value is None else str(value)]) + "\n"
    notice = f"""Typebar independent Indonesian corpus
Revision: {REVISION}
English Wiktionary contributors, extracted by Kaikki.org / Wiktextract.
Source: {SOURCE}
Snapshot SHA-256: {SOURCE_SHA}
Index reports extraction 2026-10-30 from enwiktionary dump 2026-10-01.
Selected literal titles/forms only; no recasing, affix synthesis or numbered padding.
Only lang_code=id and declared lexical parts of speech are selected.
Misspelling/proscribed/nonstandard-only senses and tagged extraction/template/
romanization forms are excluded. These filters do not certify linguistic quality.
Per-word contributor page: https://en.wiktionary.org/wiki/ + encoded sourceTitle.
Selection is adapted by filtering/ranking; displayed spellings are unchanged.
The 30 old Typebar authored starter words are retained in all three pools.
sejenak and hening are marked typebar-legacy, not dictionary attestations.
Dictionary selection and frequency data: CC BY-SA 4.0 International.
https://creativecommons.org/licenses/by-sa/4.0/
Source mapping: IndonesianCorpusSources.txt; reproducible selection in the repository.
Vocabulary, ordering and frequency distribution differ from Monkeytype.
Pools are not all nested: 1k permits capitals and 14 letters, 10k does not.

wordfreq 3.1.1 wheel SHA-256: {WHEEL_SHA}
Member: {MEMBER}
Member SHA-256: {MEMBER_SHA}
Ranking uses ASCII lowercase whole-token observations, not component estimates.
No observation is not zero. Dictionary-only entries follow observed entries.
Bands are frequency observations, not usage counts or runtime Zipf support.

""" + licenses
    output = {SWIFT: native.encode(), ROWS: rows.encode(), NOTICE: notice.encode()}
    doc = {"schemaVersion": 1, "revision": REVISION, "source": SOURCE, "sourceSHA256": SOURCE_SHA,
           "wheelSHA256": WHEEL_SHA, "member": MEMBER, "memberSHA256": MEMBER_SHA,
           "artifacts": {p: sha(b) for p, b in output.items()}, "pools": {}}
    for name, words in pools.items():
        doc["pools"][name] = {"characters": "".join(sorted(set("".join(words)))), "count": len(words), "minimumLength": min(map(len, words)), "maximumLength": max(map(len, words)),
            "uppercaseCount": sum(any(c.isupper() for c in w) for w in words), "punctuationCount": sum("-" in w for w in words),
            "wholeObserved": sum(w.lower() in bands for w in words), "wordsSHA256": sha(("\n".join(words) + "\n").encode())}
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
    pools = {("basic" if name == "basic" else name[5:]): text.splitlines() for name, text in re.findall(r'static let (basic|words1k|words10k): \[String\] = """\n(.*?)\n"""', (root / SWIFT).read_text(), re.S)}
    require(list(pools) == list(SPECS), "missing native pools")
    rows = [line.split("\t") for line in (root / ROWS).read_text().splitlines() if not line.startswith("#")]
    require(all(len(row) == 4 and row[1] in {"dictionary", "typebar-legacy"} and row[2]
        and (row[3] == "NA" or row[3].isdigit()) for row in rows), "invalid provenance")
    require({row[0] for row in rows} == set().union(*map(set, pools.values())), "incomplete provenance")
    for name, words in pools.items():
        count, maximum, upper, punct = SPECS[name]
        require(len(words) == len(set(words)) == count and set(LEGACY) <= set(words), "count/legacy mismatch")
        require(all(literal(w) for w in words) and min(map(len, words)) == 2 and max(map(len, words)) == maximum, "literal/length mismatch")
        require(set("".join(words)) == set(CHARACTERS[name]), "character set mismatch")
        require(sum(any(c.isupper() for c in w) for w in words) == upper and sum("-" in w for w in words) == punct, "category mismatch")
        require(sha(("\n".join(words) + "\n").encode()) == doc["pools"][name]["wordsSHA256"], "word pin mismatch")


class Contracts(unittest.TestCase):
    def test_literal_spelling_and_rejection(self):
        self.assertTrue(literal("anak-anak")); self.assertTrue(literal("Indonesia"))
        for word in ["-anak", "anak-", "anak--anak", "a b", "abc1", "é", "a"]:
            self.assertFalse(literal(word))

    def test_language_affix_and_bad_senses_do_not_supply_words(self):
        for change in [{"lang_code": "ms"}, {"pos": "prefix"}, {"senses": [{"tags": ["misspelling"]}]}]:
            forms = {}; collect(dict({"lang_code": "id", "pos": "noun", "word": "anak"}, **change), forms)
            self.assertEqual(forms, {})

    def test_literal_forms_keep_title_without_romanization(self):
        forms = {}; collect({"lang_code": "id", "pos": "noun", "word": "anak", "forms": [{"form": "anak-anak"}, {"form": "anakku", "tags": ["romanization"]}]}, forms)
        self.assertEqual(forms, {"anak": ("dictionary", "anak"), "anak-anak": ("dictionary", "anak")})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dictionary", type=Path); parser.add_argument("--wordfreq-wheel", type=Path)
    parser.add_argument("--output-root", type=Path); parser.add_argument("--check", action="store_true")
    parser.add_argument("--check-bundled", action="store_true"); parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return 0 if unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Contracts)).wasSuccessful() else 1
    if args.check_bundled:
        verify_bundled(args.output_root or ROOT); print("Indonesian bundled corpus verified"); return 0
    require(args.dictionary and args.wordfreq_wheel and args.output_root, "explicit pinned sources and output root required")
    output = artifacts(args.dictionary, args.wordfreq_wheel)
    if PUBLISHED:
        require({p: sha(b) for p, b in output.items()} == PUBLISHED, "reproduction pins mismatch")
    for name, data in output.items():
        target = args.output_root / name
        if args.check:
            require(target.read_bytes() == data, "source reproduction mismatch: " + name)
        else:
            require(not target.exists(), "refusing to overwrite artifact")
            target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
    print("Indonesian source reproduction checked" if args.check else "Indonesian corpus prepared")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
