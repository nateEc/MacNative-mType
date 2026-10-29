#!/usr/bin/env python3
"""Prepare independent, observed Esperanto dictionary forms in three spellings.
Standard-library QA only. No downloads, reference data or native dependencies.
"""
import argparse
import bz2
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import sys
import unicodedata
import unittest
from urllib.parse import quote

DICTIONARY_URL = "https://kaikki.org/dictionary/Esperanto/kaikki.org-dictionary-Esperanto.jsonl"
DICTIONARY_SHA = "564df5523507921c3d6b2f94c49418a3ace682671e7425ae7aa4652ad5fcfc1b"
FREQUENCY_URL = "https://downloads.tatoeba.org/exports/per_language/epo/epo_sentences_detailed.tsv.bz2"
FREQUENCY_SHA = "c7c3d234e5156596028a0a79ed669b137538966a8058373494e0c7836178ea7d"
REVISION = "kaikki-en-esperanto-tatoeba-20261029-v1"
COUNTS = {
    "native1k": 1000, "native10k": 10000, "native25k": 24998, "native36k": 36342,
    "x1k": 999, "x10k": 9993, "x25k": 24970, "x36k": 36296,
    "h1k": 999, "h10k": 9969, "h25k": 24922, "h36k": 36131,
}
LIMITS = dict(zip(COUNTS, [15, 17, 17, 40, 15, 17, 18, 40, 15, 17, 18, 40]))
PARTS = {"noun", "verb", "adj", "adv", "pron", "det", "num", "conj", "prep", "intj", "article", "particle"}
RESERVED = ["amiko", "ĉielo", "aĉeti", "ĝardeno", "ĥoro", "ĵurnalo", "ŝipo", "aŭtuno"]
SWIFT = Path("Sources/Typebar/EsperantoCorpus.generated.swift")
NOTICES = Path("Resources/EsperantoCorpusNotices.txt")
SOURCES = Path("Resources/EsperantoCorpusSources.txt")
MANIFEST = Path("Compatibility/esperanto-corpus.json")
# Published file pins are independent of the editable manifest.
PUBLISHED = {
    str(SWIFT): "9ddab7089c18c3a47975057712629ce0d95b4b592ee325410ca82fe61bf15fb5",
    str(NOTICES): "6f3173797b596e4cb3c69f1cfda4af059f40bb79e20807ca71eeb72ac3b9ce7f",
    str(SOURCES): "a69fa7d10e8d4a88c9f58a49bee8ac0b747c172165c77afa2c320bf761058e70",
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
    return (type(word) is str and 1 <= len(word) <= 40
            and word == word.lower() == unicodedata.normalize("NFC", word)
            and all(c.isalpha() and unicodedata.name(c, "").startswith("LATIN ") for c in word))


def spelling(word, system):
    require(system in {"native", "x", "h"}, "unknown spelling system")
    values = ["cx", "gx", "hx", "jx", "sx", "ux"] if system == "x" else ["ch", "gh", "hh", "jh", "sh", "u"]
    return word if system == "native" else word.translate(dict(zip(map(ord, "ĉĝĥĵŝŭ"), values)))


def collect_entry(item, forms):
    require(type(item) is dict, "dictionary entry must be an object")
    if item.get("lang_code") != "eo" or item.get("pos") not in PARTS:
        return
    lemma = item.get("word")
    require(type(lemma) is str and lemma and not any(c in lemma for c in "\t\r\n"), "invalid source title")
    candidates = item.get("forms", [])
    require(type(candidates) is list, "forms must be an array")
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
    require(file_digest(path) == DICTIONARY_SHA, "dictionary snapshot SHA-256 mismatch")
    forms = {}
    with path.open(encoding="utf-8") as f:
        for line in f:
            collect_entry(json.loads(line), forms)
    return forms


def tokens(text):
    # Whole Latin-letter runs after NFC/lowercase; punctuation separates runs.
    return [w for w in re.findall(r"[^\W\d_]+", unicodedata.normalize("NFC", text).lower())
            if all(unicodedata.name(c, "").startswith("LATIN ") for c in w)]


def read_frequency(path):
    require(file_digest(path) == FREQUENCY_SHA, "frequency snapshot SHA-256 mismatch")
    counts, ids, owners, seen = Counter(), {}, set(), set()
    with bz2.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            row = line.rstrip("\n").split("\t")
            require(len(row) == 6 and row[0].isdigit() and row[1] == "epo" and row[0] not in seen,
                    "invalid or duplicate detailed Esperanto sentence")
            seen.add(row[0]); owners.add(row[3])
            for word in tokens(row[2]):
                counts[word] += 1
                ids.setdefault(word, row[0])
    return counts, ids, owners, len(seen)


def priority(word, forms, counts):
    return -counts[word], forms[word] != word, word


def select(forms, counts, system, count, maximum):
    require(type(count) is int and count > 0 and type(maximum) is int and maximum > 0, "invalid bounds")
    owners = {}
    for word in sorted((w for w in forms if counts[w] > 0), key=lambda w: priority(w, forms, counts)):
        owners.setdefault(spelling(word, system), word)
    available = [w for w in owners if len(w) <= maximum]
    require(len(available) >= count, "insufficient observed literal forms; never pad")
    chosen = available[:count]
    reserved = [spelling(w, system) for w in RESERVED]
    require(all(w in available for w in reserved), "required letter-practice forms are absent")
    # Keep real one-letter and longest-field practice without manufacturing text.
    reserved += [min(available, key=len), max(available, key=len)]
    protected = set(reserved)
    for word in reserved:
        if word not in chosen:
            remove = next((i for i in range(len(chosen)-1, -1, -1) if chosen[i] not in protected), None)
            require(remove is not None, "not enough room for reserved forms")
            chosen[remove] = word
    chosen.sort(key=lambda w: priority(owners[w], forms, counts))
    require(len(chosen) == len(set(chosen)) == count, "selection is not exact and unique")
    return chosen, {w: owners[w] for w in chosen}, len(available)


def shape(words):
    return {"count": len(words), "uniqueCount": len(set(words)), "minimumLength": min(map(len, words)),
            "maximumLength": max(map(len, words)), "nonASCIIEntries": sum(not w.isascii() for w in words)}


def native_source(scales):
    header = ("// Generated by Scripts/prepare-esperanto-corpus.py; do not edit.\n"
              "// Independent English Wiktionary forms; Tatoeba-derived usage ranking.\n"
              "// Notices and per-spelling sources: Resources/EsperantoCorpus*.txt.\n"
              "// No reference-project code or word data. Each choice initializes on demand.\n"
              "enum EsperantoCorpus {\n" + f'  static let revision = "{REVISION}"\n')
    return (header + "".join(f'  static let {k}: [String] = """\n' + "\n".join(w)
            + '\n""".split(separator: "\\n").map(String.init)\n' for k, w in scales.items()) + "}\n").encode()


def artifacts(forms, counts, ids, owners, sentences):
    scales, evidence, available = {}, {}, {}
    for key, count in COUNTS.items():
        system = re.sub(r"\d+k$", "", key)
        words, sources, total = select(forms, counts, system, count, LIMITS[key])
        scales[key] = words; available[key] = total
        for output, original in sources.items():
            row = [original, forms[original], str(counts[original]), ids[original]]
            previous = evidence.setdefault((system, output), row)
            require(previous == row, "inconsistent spelling ownership")
    source_text = ("# Typebar independent Esperanto spelling sources; revision " + REVISION + "\n"
                   "# system\tspelling\tliteralDictionaryForm\tEnglishWiktionaryTitle\tTatoebaTokenCount\tfirstSentenceID\n"
                   "# Dictionary: https://en.wiktionary.org/wiki/<percent-encoded-title>#Esperanto\n"
                   "# Contributors/history: https://en.wiktionary.org/w/index.php?title=<percent-encoded-title>&action=history\n"
                   "# Usage evidence: https://tatoeba.org/en/sentences/show/<firstSentenceID>\n")
    source_text += "".join("\t".join([system, output] + row) + "\n"
                           for (system, output), row in sorted(evidence.items()))
    notices = ("Typebar independent Esperanto scale corpus\nRevision: " + REVISION + "\n\n"
               "Adapted selection and X/H spellings: CC BY-SA 4.0.\n"
               "English Wiktionary contributors; extracted through Kaikki.org / Wiktextract.\n"
               "https://creativecommons.org/licenses/by-sa/4.0/\nhttps://en.wiktionary.org/wiki/Wiktionary:Copyrights\n"
               "Dictionary snapshot retrieved 2026-10-29 (postprocessed English edition):\n"
               + DICTIONARY_URL + "\nSHA-256: " + DICTIONARY_SHA + "\n\n"
               "Frequency counts derived from Tatoeba Esperanto detailed sentences, CC BY 2.0 FR.\n"
               "https://creativecommons.org/licenses/by/2.0/fr/\nhttps://tatoeba.org/en/downloads\n"
               + FREQUENCY_URL + "\nSHA-256: " + FREQUENCY_SHA + "\n\n"
               "Changes: select only literal lowercase NFC Latin-letter dictionary forms also\n"
               "observed as Latin-letter tokens in the fixed Esperanto sentence snapshot.\n"
               "NFC/lowercase before counting; punctuation (including apostrophes/hyphens)\n"
               "separates tokens. No sentences, translations, glosses, audio or images bundled.\n"
               "Sort by measured token count descending, then literal-headword preference and\n"
               "spelling. Reserve eight letter-practice forms, shortest and longest real fields.\n"
               "X maps ĉĝĥĵŝŭ to cx/gx/hx/jx/sx/ux; H to ch/gh/hh/jh/sh/u.\n"
               "Preserve other literal Latin accents. Deduplicate encoded collisions by\n"
               "the highest-priority original; keep its count, do not invent combined counts.\n"
               "Per-spelling original, entry title, measured count and first observing sentence\n"
               "are in EsperantoCorpusSources.txt with source/contributor-history URL templates.\n"
               "This is curriculum selection ranked on one sentence corpus, not original-list,\n"
               "general frequency, dialect, difficulty, quality or distribution equivalence.\n"
               "Longest fields fall short of reference 40 characters; no synthetic padding.\n"
               "Extraction errors, unusual, archaic or offensive forms may remain.\n"
               "Basic authored pools and captured old results remain unchanged.\n\n"
               "Tatu Ylonen, Wiktextract: Wiktionary as Machine-Readable Structured Data,\n"
               "LREC 2022, pp. 1317–1325. https://aclanthology.org/2022.lrec-1.140/\n\n"
               "Tatoeba contributors in the fixed snapshot (public owner handles; unowned\n"
               "sentences retain \\N; source sentence pages supply contribution history):\n")
    notices += "".join(owner + "\t" + ("unowned; consult source sentence history" if owner == "\\N"
                      else "https://tatoeba.org/en/user/profile/" + quote(owner, safe="")) + "\n" for owner in sorted(owners))
    generated = {SWIFT: native_source(scales), NOTICES: notices.encode(), SOURCES: source_text.encode()}
    manifest = {"schemaVersion": 1, "revision": REVISION,
                "dictionary": {"url": DICTIONARY_URL, "sha256": DICTIONARY_SHA, "languageCode": "eo", "edition": "en", "postprocessed": True},
                "frequency": {"url": FREQUENCY_URL, "sha256": FREQUENCY_SHA, "languageCode": "epo", "sentences": sentences,
                              "contributors": len(owners), "tokens": sum(counts.values()), "distinctTokens": len(counts)},
                "preparation": {"unicodeVersion": "15.0.0", "runtimeDependencies": []},
                "availableObservedForms": available, "dictionaryForms": len(forms), "sourceMapCount": len(evidence),
                "scales": {k: {"shape": shape(w), "wordsSHA256": digest(("\n".join(w) + "\n").encode())} for k, w in scales.items()},
                "filesSHA256": {str(k): digest(v) for k, v in generated.items()},
                "limits": "Original long-field, accent distribution and language-quality parity remain open; never pad."}
    generated[MANIFEST] = (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    return generated


def verify_pins(hashes):
    require(bool(PUBLISHED) and hashes == PUBLISHED, "published file pin mismatch; mutable manifest hashes are insufficient")


def verify_bundled(root):
    m = json.loads((root / MANIFEST).read_text())
    require(type(m["schemaVersion"]) is int and m["schemaVersion"] == 1 and m["revision"] == REVISION, "unsupported manifest")
    require(m["dictionary"] == {"url": DICTIONARY_URL, "sha256": DICTIONARY_SHA, "languageCode": "eo", "edition": "en", "postprocessed": True}
            and m["frequency"]["url"] == FREQUENCY_URL and m["frequency"]["sha256"] == FREQUENCY_SHA
            and m["frequency"]["languageCode"] == "epo", "source pin mismatch")
    verify_pins(m["filesSHA256"])
    for name, sha in m["filesSHA256"].items():
        require(file_digest(root / name) == sha, "bundled file hash mismatch: " + name)
    text = (root / SWIFT).read_text()
    matches = re.findall(r'  static let (native|x|h)(1k|10k|25k|36k): \[String\] = """\n(.*?)"""', text, re.S)
    scales = {a+b: body.splitlines() for a, b, body in matches}
    require(len(matches) == len(scales) == len(COUNTS) and list(scales) == list(COUNTS)
            and native_source(scales) == text.encode() and set(m["scales"]) == set(COUNTS), "native template mismatch")
    rows = [r.split("\t") for r in (root / SOURCES).read_text().splitlines() if not r.startswith("#")]
    require(all(len(r) == 6 and all(r) for r in rows), "invalid evidence rows")
    evidence = {(r[0], r[1]): r[2:] for r in rows}
    require(len(rows) == len(evidence) == m["sourceMapCount"], "duplicate evidence rows")
    expected = set()
    for key, words in scales.items():
        system = re.sub(r"\d+k$", "", key)
        require(len(words) == len(set(words)) == COUNTS[key] and all(eligible(w) and len(w) <= LIMITS[key] for w in words), "invalid native shape")
        require(m["scales"][key] == {"shape": shape(words), "wordsSHA256": digest(("\n".join(words) + "\n").encode())}, "native content mismatch")
        for word in words:
            expected.add((system, word))
            require((system, word) in evidence, "missing source spelling")
            original, lemma, count, sid = evidence[system, word]
            require(eligible(original) and spelling(original, system) == word and bool(lemma)
                    and count.isdigit() and int(count) > 0 and sid.isdigit(), "invalid spelling provenance")
    require(set(evidence) == expected, "evidence coverage mismatch")


def publish(outputs, root, check):
    verify_pins({str(k): digest(v) for k, v in outputs.items() if k != MANIFEST})
    if check:
        for name, data in outputs.items():
            require((root / name).read_bytes() == data, "artifact mismatch: " + str(name))
    else:
        require(not any((root / name).exists() for name in outputs), "refusing to overwrite artifacts")
        for name, data in outputs.items():
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)


class Contracts(unittest.TestCase):
    def test_six_letter_spellings_and_h_u(self):
        self.assertEqual(spelling("ĉĝĥĵŝŭ", "x"), "cxgxhxjxsxux")
        self.assertEqual(spelling("ĉĝĥĵŝŭ", "h"), "chghhhjhshu")
        self.assertEqual(spelling("café", "x"), "café")

    def test_literal_filter(self):
        for word in ["ĉielo", "aŭtuno", "café"]: self.assertTrue(eligible(word))
        for word in ["", "Ĝardeno", "e\u0301", "a a", "a-", "q7", "a\x92", "字"]: self.assertFalse(eligible(word))

    def test_entry_metadata_is_not_a_form(self):
        forms = {}
        collect_entry({"lang_code": "eo", "pos": "noun", "word": "ŝipo", "forms": [
            {"form": "ŝipoj", "tags": ["plural"]}, {"form": "fake", "tags": ["error-table"]}]}, forms)
        self.assertEqual(forms, {"ŝipo": "ŝipo", "ŝipoj": "ŝipo"})

    def test_other_language_and_parts_are_not_words(self):
        forms = {}
        collect_entry({"lang_code": "en", "pos": "noun", "word": "apple"}, forms)
        collect_entry({"lang_code": "eo", "pos": "prefix", "word": "mal"}, forms)
        self.assertFalse(forms)

    def test_tokens_lowercase_and_punctuation_boundaries(self):
        self.assertEqual(tokens("Ĉielo, ĝardeno! ŝip-o 123 字"), ["ĉielo", "ĝardeno", "ŝip", "o"])

    def test_unknown_system_and_bad_bounds_fail(self):
        with self.assertRaises(ValueError): spelling("a", "bad")
        with self.assertRaises(ValueError): select({}, Counter(), "native", 0, 15)

    def test_insufficient_observations_never_pad(self):
        with self.assertRaises(ValueError): select({"amiko": "amiko"}, Counter(), "native", 1000, 15)

    def test_h_collision_uses_literal_owner_with_highest_count(self):
        forms = {w: w for w in RESERVED + ["au", "aŭ", "a", "longavorto"]}
        counts = Counter({w: 1 for w in forms}); counts["aŭ"] = 50; counts["au"] = 2
        words, owners, _ = select(forms, counts, "h", len(forms)-1, 40)
        self.assertEqual(words.count("au"), 1); self.assertEqual(owners["au"], "aŭ")

    def test_published_pins_cannot_be_replaced_by_manifest(self):
        with self.assertRaises(ValueError): verify_pins({})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dictionary", type=Path)
    parser.add_argument("--frequency", type=Path)
    parser.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--check-bundled", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return 0 if unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Contracts)).wasSuccessful() else 1
    if args.check_bundled:
        verify_bundled(args.output_root); print("Esperanto bundled integrity passed (twelve pools; source reproduction is stronger)"); return 0
    require(args.dictionary is not None and args.frequency is not None, "fixed dictionary and frequency snapshots required")
    forms = read_dictionary(args.dictionary)
    counts, ids, owners, sentences = read_frequency(args.frequency)
    publish(artifacts(forms, counts, ids, owners, sentences), args.output_root, args.check)
    print("Esperanto source reproduction checked" if args.check else "Esperanto corpus prepared")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("Esperanto preparation failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
