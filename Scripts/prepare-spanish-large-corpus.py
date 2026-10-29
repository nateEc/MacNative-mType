#!/usr/bin/env python3
"""Prepare independent Spanish 650k data; no reference words or downloads.

Source preparation needs Unicode 15.0.0 and msgpack==1.1.2. Bundled checks
and self-tests use the standard library. No native runtime dependency.
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

SNAPSHOTS = {
    "es": {"url": "https://kaikki.org/dictionary/downloads/es/es-extract.jsonl.gz", "sha256": "9bca1b9e3d4573825f196aff7aaa1a640503430df248f5a82f6602177abf6853"},
    "fr": {"url": "https://kaikki.org/dictionary/downloads/fr/fr-extract.jsonl.gz", "sha256": "823fa6f488e23850075747762d946c730c798d971e93b37fe645863b8f25e377"},
}
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/large_es.msgpack.gz"
MEMBER_SHA = "14f326b4f68d517f9b8b99c1e26ef56a508d2dc8d0ee7a9e6e8732ddab1aa65e"
COUNT, MAXIMUM, PHRASES, PUNCTUATED = 646579, 26, 162, 77
REVISION = "kaikki-es-fr-20261029-wordfreq-3.1.1-large-v1"
SWIFT = Path("Sources/Typebar/SpanishLargeCorpus.generated.swift")
MANIFEST = Path("Compatibility/spanish-large-corpus.json")
NOTICES = Path("Resources/SpanishLargeCorpusNotices.txt")
SOURCES = Path("Resources/SpanishLargeCorpusSources.txt")
ATTRIBUTION_PINS = {
    str(NOTICES): "9ec3b4cbb7c5f0487f6e9e40e272233df9954f0032baf24d9e19bb0d12d107f2",
    str(SOURCES): "11aa61f95f2d6696a2755213a54ad507fb6f5e2cabe939bb80df253048737feb",
}
NAMES = ["España", "México", "Madrid"]
ASCII_BOUNDARIES = ["-ción", "-dad", "anti-", "ex-"]
FIGURE_BASES = ["-able", "-al", "-ano", "-ario", "-dor", "-ero", "-ismo", "-ista", "-ito", "-mente", "-oso"]
SLASHES = ["y/o", "s/n"]
LABEL_BASE = "neurorretroalimentaciones"
PARENTHETICAL_BASE = "amigo"
PARTS = frozenset("noun name verb adj adv article pron det conj intj prep postp num particle phrase abbrev prefix suffix affix infix participle contraction onomatopoeia".split())


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


def literal(word):
    return type(word) is str and 1 <= len(word) <= MAXIMUM and word == unicodedata.normalize("NFC", word)


def title(value):
    require(type(value) is str and value and not any(c in value for c in "\t\r\n"), "invalid source title")
    return value


def owner_priority(owner):
    return owner[0] != "es", len(owner[1]), owner[1]


def remember(pool, word, owner):
    previous = pool.get(word)
    if previous is None or owner_priority(owner) < owner_priority(previous):
        pool[word] = owner


def collect_entry(item, edition, pools):
    require(type(item) is dict and edition in SNAPSHOTS, "invalid dictionary entry or edition")
    if item.get("lang_code") != "es" or item.get("pos") not in PARTS:
        return
    lemma = title(item.get("word"))
    if literal(lemma):
        if letters(lemma):
            remember(pools["lower" if lemma == lemma.lower() else "cased"], lemma, (edition, lemma))
        elif lemma == lemma.lower():
            if " " in lemma and all(letters(w) for w in lemma.split(" ")):
                remember(pools["phrases"], lemma, (edition, lemma))
            elif lemma in SLASHES or lemma.count("-") == 1 and all(letters(w) for w in lemma.split("-") if w):
                if any(c.isalpha() for c in lemma):
                    remember(pools["punctuated"], lemma, (edition, lemma))
    forms = item.get("forms", [])
    require(type(forms) is list, "dictionary forms must be an array")
    for form in forms:
        require(type(form) is dict and type(form.get("form")) is str, "invalid inflected form")
        word = form["form"]
        if literal(word) and letters(word) and word == word.lower():
            remember(pools["lower"], word, (edition, title(form.get("source") or lemma)))


def read_dictionaries(paths):
    require(unicodedata.unidata_version == "15.0.0", "source preparation requires Unicode 15.0.0")
    require(set(paths) == set(SNAPSHOTS), "provide both dictionary editions")
    pools = {k: {} for k in ["lower", "cased", "phrases", "punctuated"]}
    for edition, path in paths.items():
        require(file_digest(path) == SNAPSHOTS[edition]["sha256"], "dictionary snapshot SHA-256 mismatch: " + edition)
        with gzip.open(path, "rt", encoding="utf-8") as source:
            for line in source:
                collect_entry(json.loads(line), edition, pools)
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
    require(digest(packed) == MEMBER_SHA, "Spanish frequency member SHA-256 mismatch")
    data = msgpack.unpackb(gzip.decompress(packed), raw=False)
    require(type(data) is list and data and data[0] == {"format": "cB", "version": 1}, "unsupported frequency format")
    require("## License" in metadata, "wordfreq release notices missing")
    return frequency_bands(data[1:]), metadata[metadata.index("## License"):].strip() + "\n"


def priority(word, bands):
    band = bands.get(word.casefold())
    if band is None:
        band = max((bands.get(w.casefold(), 10**9) for w in re.split("[ -]", word) if w), default=10**9)
    return band, word


def take(pool, count, bands):
    require(type(count) is int and count >= 0, "invalid selection count")
    ranked = sorted(pool, key=lambda w: priority(w, bands))
    require(len(ranked) >= count, "insufficient literal dictionary forms; never pad")
    return ranked[:count]


def select(pools, bands):
    # Editorial examples are explicit typography / writing practice based on
    # existing terms, never presented as literal dictionary spellings or ranks.
    require(all(w in pools["cased"] for w in NAMES), "proper-name spelling not attested")
    required = ASCII_BOUNDARIES + FIGURE_BASES + SLASHES
    require(all(w in pools["punctuated"] for w in required), "punctuation base not attested")
    require(LABEL_BASE in pools["lower"] and PARENTHETICAL_BASE in pools["lower"], "editorial writing base not attested")
    internal = {w: owner for w, owner in pools["punctuated"].items()
                if w.count("-") == 1 and not w.startswith("-") and not w.endswith("-")}
    hyphens = ASCII_BOUNDARIES + take(internal, 58, bands)
    phrases = take(pools["phrases"], PHRASES, bands)
    editorial = []
    for base in FIGURE_BASES:
        editorial.append({"word": "‒" + base[1:], "base": base, "kind": "figureDashTypography", "owner": pools["punctuated"][base]})
    editorial += [{"word": LABEL_BASE + ":", "base": LABEL_BASE, "kind": "topicLabel", "owner": pools["lower"][LABEL_BASE]},
                  {"word": "(" + PARENTHETICAL_BASE + ")", "base": PARENTHETICAL_BASE, "kind": "parentheticalTerm", "owner": pools["lower"][PARENTHETICAL_BASE]}]
    punctuated = hyphens + SLASHES + [row["word"] for row in editorial]
    require(len(punctuated) == len(set(punctuated)) == PUNCTUATED, "punctuation inventory mismatch")
    words = take(pools["lower"], COUNT - PHRASES - PUNCTUATED - len(NAMES), bands) + NAMES + phrases + punctuated
    require(len(words) == len(set(words)) == COUNT, "selection must be exact and unique")
    require(max(map(len, words)) == MAXIMUM, "maximum field boundary missing")
    owners = {}
    for word in words:
        if word in pools["lower"]: owner = pools["lower"][word]
        elif word in NAMES: owner = pools["cased"][word]
        elif word in phrases: owner = pools["phrases"][word]
        elif word in pools["punctuated"]: owner = pools["punctuated"][word]
        else: owner = next(row["owner"] for row in editorial if row["word"] == word)
        owners[word] = owner
    return sorted(words, key=lambda w: priority(w, bands)), editorial, owners


def native_source(words):
    return ("// Generated by Scripts/prepare-spanish-large-corpus.py; do not edit.\n"
            "// Independent Spanish Wiktionary forms; 13 explicitly edited writing examples.\n"
            "// CC BY-SA 4.0 adapted selection; full notices and source mapping accompany the app.\n"
            "enum SpanishLargeCorpus {\n" + f'  static let revision = "{REVISION}"\n'
            + '  static let words: [String] = """\n' + "\n".join(words)
            + '\n""".split(separator: "\\n").map(String.init)\n}\n').encode()


def shape(words):
    return {"count": len(words), "uniqueCount": len(set(words)), "minimumLength": min(map(len, words)),
            "maximumLength": max(map(len, words)), "maximumLetterLength": max(len(w) for w in words if letters(w)),
            "uppercaseCount": sum(any(c.isupper() for c in w) for w in words), "nonASCIICount": sum(not w.isascii() for w in words),
            "nonLetterCount": sum(not w.isalpha() for w in words), "spaceEntries": sum(" " in w for w in words),
            "punctuationEntries": sum(any(unicodedata.category(c).startswith("P") for c in w) for w in words),
            "punctuationScalars": {c: sum(w.count(c) for w in words) for c in sorted({c for w in words for c in w if unicodedata.category(c).startswith("P")})}}


def check_attribution_pins(hashes):
    require(set(ATTRIBUTION_PINS) == {str(NOTICES), str(SOURCES)}
            and all(hashes.get(name) == sha for name, sha in ATTRIBUTION_PINS.items()),
            "published attribution pin mismatch; mutable manifest hashes are insufficient")


def artifacts(pools, bands, release_notices):
    words, editorial, owners = select(pools, bands)
    edits = {row["word"]: row for row in editorial}
    source_map = ("# Practice spelling\tWiktionary edition\tSource page title\tEvidence kind\n"
                  "# Page: https://<edition>.wiktionary.org/wiki/<URL-encoded title>\n"
                  "# Contributors: https://<edition>.wiktionary.org/w/index.php?title=<URL-encoded title>&action=history\n"
                  "# Editorial writing examples are adaptations of the indicated base, not literal source spellings.\n"
                  + "".join(w + "\t" + owners[w][0] + "\t" + owners[w][1] + "\t" + (edits[w]["kind"] if w in edits else "dictionaryLiteral") + "\n" for w in sorted(words))).encode()
    notices = ("Typebar independent Spanish 650k corpus — revision 1\n"
               "Spanish-language entries from Wikcionario and Wiktionnaire contributors,\n"
               "extracted by Kaikki.org / Wiktextract. Selection and 13 editorial typography /\n"
               "writing examples adapted by Typebar contributors (2026), CC BY-SA 4.0.\n"
               "https://creativecommons.org/licenses/by-sa/4.0/\n"
               "https://es.wiktionary.org/\n"
               "https://fr.wiktionary.org/wiki/Wiktionnaire:Licence\n\n"
               "Dictionary snapshots retrieved 2026-10-29:\n"
               + "".join(e + ": " + row["url"] + "\nSHA-256: " + row["sha256"] + "\n" for e, row in SNAPSHOTS.items())
               + "https://kaikki.org/dictionary/rawdata.html\n\n"
               "Only lang_code=es entries are used, from both editions; Spanish-edition\n"
               "attribution is preferred when both provide the same form. Inflection source\n"
               "pages are retained when supplied. No definitions, examples, images or audio.\n"
               "SpanishLargeCorpusSources.txt maps every practice spelling to its edition,\n"
               "page title and evidence kind, with page / contributor-history URL templates.\n\n"
               "Changes: lowercase NFC Latin-letter forms, three existing proper names,\n"
               "162 existing multiword headwords, 62 literal ASCII-hyphen headwords and two\n"
               "literal slash abbreviations. Eleven suffixes receive an explicitly editorial\n"
               "U+2012 figure dash variant; one existing term becomes a topic label with a\n"
               "colon, another a parenthetical writing example. These 13 edited forms are\n"
               "not claimed as dictionary spellings or separately observed frequencies.\n"
               "They preserve character-practice capabilities without invented filler words.\n"
               "Ranking uses case-folded wordfreq observations; missing whole-form ranks\n"
               "use the rarest constituent as an estimate, unknown ranks last. Not a pure\n"
               "frequency cutoff. Data can include extraction errors, archaic forms, names,\n"
               "loans, colloquial or offensive words; no quality / difficulty / distribution\n"
               "parity claim. Original basic / 1k / 10k corpora are unchanged.\n\n"
               "Tatu Ylonen, Wiktextract: Wiktionary as Machine-Readable Structured Data,\n"
               "LREC 2022, pp. 1317–1325. https://aclanthology.org/2022.lrec-1.140/\n\n"
               "=== wordfreq 3.1.1 release metadata ===\n" + release_notices).encode()
    swift = native_source(words)
    generated = {SWIFT: swift, NOTICES: notices, SOURCES: source_map}
    manifest = {"schemaVersion": 1, "revision": REVISION,
                "dictionaries": {e: dict(row, retrievedDate="2026-10-29", languageCode="es") for e, row in SNAPSHOTS.items()},
                "wordfreq": {"version": "3.1.1", "wheelSHA256": WHEEL_SHA, "member": MEMBER, "memberSHA256": MEMBER_SHA},
                "preparation": {"unicodeVersion": "15.0.0", "msgpackVersion": "1.1.2", "runtimeDependencies": []},
                "available": {k: len(v) for k, v in pools.items()}, "shape": shape(words),
                "wordsSHA256": digest(("\n".join(words) + "\n").encode()), "editorialForms": editorial,
                "literalProperNames": NAMES, "sourceMapCount": len(owners),
                "filesSHA256": {str(k): digest(v) for k, v in generated.items()},
                "dataLicense": "CC-BY-SA-4.0 adapted selection; retain notices and entry map",
                "limits": "Literal forms and declared writing adaptations do not prove quality, difficulty or distribution parity."}
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
    require(type(manifest["schemaVersion"]) is int and manifest["schemaVersion"] == 1 and manifest["revision"] == REVISION, "unsupported manifest")
    require(set(manifest["dictionaries"]) == set(SNAPSHOTS) and all(manifest["dictionaries"][e]["sha256"] == r["sha256"] and manifest["dictionaries"][e]["url"] == r["url"] for e, r in SNAPSHOTS.items()), "dictionary pin mismatch")
    require(manifest["wordfreq"]["wheelSHA256"] == WHEEL_SHA and manifest["wordfreq"]["memberSHA256"] == MEMBER_SHA, "frequency pin mismatch")
    hashes = manifest["filesSHA256"]
    require(set(hashes) == {str(SWIFT), str(NOTICES), str(SOURCES)}, "file inventory mismatch")
    check_attribution_pins(hashes)
    for name, sha in hashes.items():
        require(file_digest(root / name) == sha, "bundled file hash mismatch: " + name)
    swift = (root / SWIFT).read_bytes();match = re.search(rb'  static let words: \[String\] = """\n(.*?)"""', swift, re.S)
    require(match is not None, "missing native data section")
    body = match.group(1);words = body.decode().splitlines()
    require(native_source(words) == swift and digest(body) == manifest["wordsSHA256"], "native data mismatch")
    require(len(words) == len(set(words)) == COUNT and shape(words) == manifest["shape"], "word shape mismatch")
    require(manifest["shape"]["maximumLength"] == MAXIMUM and manifest["shape"]["minimumLength"] == 1
            and manifest["shape"]["spaceEntries"] == PHRASES and manifest["shape"]["punctuationEntries"] == PUNCTUATED
            and manifest["shape"]["nonLetterCount"] == PHRASES + PUNCTUATED and manifest["shape"]["uppercaseCount"] == 3, "practice limits changed")
    allowed = set("-‒():/ ")
    require(all(literal(w) and all(c.isalpha() or c in allowed for c in w) for w in words), "invalid native spelling")
    expected_edit_words = {"‒" + w[1:] for w in FIGURE_BASES} | {LABEL_BASE + ":", "(" + PARENTHETICAL_BASE + ")"}
    require({r["word"] for r in manifest["editorialForms"]} == expected_edit_words <= set(words)
            and len(manifest["editorialForms"]) == 13 and manifest["literalProperNames"] == NAMES, "editorial evidence changed")
    rows = [line.split("\t") for line in (root / SOURCES).read_text().splitlines() if not line.startswith("#")]
    require(all(len(r) == 4 and r[1] in SNAPSHOTS and all(r) for r in rows), "invalid source map")
    require(len(rows) == len({r[0] for r in rows}) == manifest["sourceMapCount"] == COUNT
            and {r[0] for r in rows} == set(words), "source map coverage mismatch")
    print("Spanish large bundled integrity passed (646579 forms; source reproduction is stronger)")


class Contracts(unittest.TestCase):
    def test_language_gate_and_literal_inflection_source(self):
        p = {k: {} for k in ["lower", "cased", "phrases", "punctuated"]}
        collect_entry({"lang_code": "es", "pos": "noun", "word": "niño", "forms": [{"form": "niños", "source": "niño"}]}, "es", p)
        collect_entry({"lang_code": "fr", "pos": "noun", "word": "enfant"}, "fr", p)
        self.assertEqual(p["lower"], {"niño": ("es", "niño"), "niños": ("es", "niño")})

    def test_edition_preference_is_order_independent(self):
        for editions in [["es", "fr"], ["fr", "es"]]:
            p = {}
            for edition in editions: remember(p, "niño", (edition, "niño"))
            self.assertEqual(p, {"niño": ("es", "niño")})

    def test_existing_phrases_and_boundary_affixes_are_not_concatenated(self):
        p = {k: {} for k in ["lower", "cased", "phrases", "punctuated"]}
        for w in ["por favor", "por  favor", "-ismo", "anti-", "y/o", "---"]:
            collect_entry({"lang_code": "es", "pos": "noun", "word": w}, "es", p)
        self.assertEqual(set(p["phrases"]), {"por favor"})
        self.assertEqual(set(p["punctuated"]), {"-ismo", "anti-", "y/o"})

    def test_insufficient_forms_never_pad_and_counts_reject_bool(self):
        for n in [True, -1]:
            with self.assertRaises(ValueError): take({}, n, {})
        with self.assertRaisesRegex(ValueError, "never pad"): take({"niño": ("es", "niño")}, 2, {})

    def test_frequency_bins_reject_wrong_order_duplicates_and_types(self):
        for bins in [[["b", "a"]], [["a", "a"]], [["a"], ["a"]], [[1]], "invalid"]:
            with self.assertRaises(ValueError): frequency_bands(bins)

    def test_typography_keeps_nfc_and_estimated_rank_is_explicit(self):
        self.assertFalse(literal("nin\u0303o"))
        self.assertEqual(priority("por favor", {"por": 1, "favor": 10})[0], 10)
        self.assertEqual(priority("niño", {"niño": 3})[0], 3)

    def test_edited_forms_require_all_original_bases(self):
        p = {k: {} for k in ["lower", "cased", "phrases", "punctuated"]}
        with self.assertRaisesRegex(ValueError, "not attested"): select(p, {})

    def test_attribution_pins_cannot_be_redefined_by_manifest(self):
        check_attribution_pins(dict(ATTRIBUTION_PINS))
        for name in ATTRIBUTION_PINS:
            changed = dict(ATTRIBUTION_PINS, **{name: "0" * 64})
            with self.assertRaises(ValueError): check_attribution_pins(changed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spanish-dictionary", type=Path)
    parser.add_argument("--french-dictionary", type=Path)
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
        verify_bundled(args.output_root);return 0
    require(args.spanish_dictionary is not None and args.french_dictionary is not None and args.wordfreq_wheel is not None, "provide both dictionary editions and --wordfreq-wheel")
    bands, notices = read_frequency(args.wordfreq_wheel)
    pools = read_dictionaries({"es": args.spanish_dictionary, "fr": args.french_dictionary})
    publish(artifacts(pools, bands, notices), args.output_root, args.check)
    print("Spanish large source reproduction " + ("checked" if args.check else "prepared"))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, OSError) as error:
        print("Spanish large preparation failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
