#!/usr/bin/env python3
"""Pinned independent Malay dictionary forms and Malay-only sentence observations."""
import argparse
import bz2
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import unicodedata
import unittest

ROOT = Path(__file__).resolve().parents[1]
DICTIONARY_URL = "https://kaikki.org/dictionary/Malay/kaikki.org-dictionary-Malay.jsonl"
DICTIONARY_SHA = "d4b211c01a2206ae4136a6b35ca0cd1412e053cf95bcb639837a4f4559d3c592"
SENTENCES_URL = "https://downloads.tatoeba.org/exports/per_language/zsm/zsm_sentences_detailed.tsv.bz2"
SENTENCES_SHA = "3e4701bc8b673a278a30a084be3c87deaa449da9ed011082a06bda1e27821d20"
REVISION = "kaikki-en-ms-tatoeba-zsm-20261102-literal-v1"
LEGACY = "pagi tingkap kertas pantai angin latihan perhatian tenang jelas tasik jalan meja cahaya perjalanan kesabaran seketika bandar hujan sunyi arah bintang catatan taman nafas kecil masa musim perahu sahabat harapan".split()
SPECS = {"basic": (228, 12, 0, 0, 0), "1k": (1000, 16, 1, 12, 1)}
CHARACTERS = {"basic": "abcdefghijklmnoprstuwy", "1k": " -Sabcdefghijklmnoprstuvwyz"}
PARTS = set("noun verb adj adv name pron num det conj intj prep postp particle phrase abbrev article".split())
BAD = {"misspelling", "proscribed", "nonstandard"}
SWIFT = "Sources/Typebar/MalayCorpus.generated.swift"
ROWS = "Resources/MalayCorpusSources.txt"
NOTICE = "Resources/MalayCorpusNotices.txt"
MANIFEST = "Compatibility/malay-corpus.json"
PUBLISHED = {
    SWIFT: "9f904015b7e754d37c62d164806781a4d9a02912d1327ad0c88dec45893d0ebf",
    ROWS: "9a78f6b05bf07ba85efc6ed84891f2e97b0e2a3636ff2864b5b10df475f1c22d",
    NOTICE: "992628474b6322278824a0570cb72bad2001136b1d7e9f36ed6f07156cf8de10",
    MANIFEST: "09f4a4eaff4be2f4a179182e6a715e72f086076b592c178b6819ca5bdbb46a44",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def literal(word):
    return type(word) is str and 2 <= len(word) <= 16 and re.fullmatch(r"[A-Za-z]+(?:-[A-Za-z]+)*|[A-Za-z]+ [A-Za-z]+", word) is not None


def collect(entry, forms):
    require(type(entry) is dict, "invalid dictionary entry")
    if entry.get("lang_code") != "ms" or entry.get("pos") not in PARTS:
        return
    senses = entry.get("senses", [{}])
    require(type(senses) is list and all(type(s) is dict for s in senses), "invalid senses")
    if not senses or all(BAD.intersection(s.get("tags", [])) for s in senses):
        return
    title = entry.get("word")
    require(type(title) is str and not any(c in title for c in "\t\r\n"), "invalid source title")
    rows = entry.get("forms", [])
    require(type(rows) is list, "invalid forms")
    for row in [{"form": title}] + rows:
        require(type(row) is dict and type(row.get("form")) is str, "invalid form")
        tags = row.get("tags", [])
        require(type(tags) is list and all(type(t) is str for t in tags), "invalid form tags")
        if BAD.intersection(tags) or any(t in {"romanization", "table-tags", "inflection-template", "class"} or t.startswith("error-") for t in tags):
            continue
        if literal(row["form"]):
            forms.setdefault(row["form"], ("dictionary", title))


def observations(text):
    text = unicodedata.normalize("NFC", text)
    matches = list(re.finditer(r"\w+(?:-\w+)*", text))
    valid = {}
    for match in matches:
        word = match.group().lower()
        edges = text[max(0, match.start() - 1):match.start()] + text[match.end():match.end() + 1]
        if re.fullmatch(r"[a-z]+(?:-[a-z]+)*", word) and not any(unicodedata.category(c).startswith("M") for c in edges):
            valid[match.start()] = word
            yield word
    for left, right in zip(matches, matches[1:]):
        a, b = valid.get(left.start()), valid.get(right.start())
        if a and b and "-" not in a + b and text[left.end():right.start()] == " ":
            yield a + " " + b


def read_sources(dictionary, sentences):
    require(sha(dictionary.read_bytes()) == DICTIONARY_SHA, "dictionary pin mismatch")
    forms = {}
    for line in dictionary.open(encoding="utf-8"):
        collect(json.loads(line), forms)
    require(sha(sentences.read_bytes()) == SENTENCES_SHA, "Malay sentence pin mismatch")
    counts, first, owners, seen = Counter(), {}, set(), set()
    with bz2.open(sentences, "rt", encoding="utf-8") as stream:
        for line in stream:
            row = line.rstrip("\n").split("\t")
            require(len(row) == 6 and row[0].isdigit() and row[1] == "zsm" and row[0] not in seen, "invalid/duplicate standard Malay sentence")
            seen.add(row[0]); owners.add(row[3])
            for word in observations(row[2]):
                counts[word] += 1
                first.setdefault(word, row[0])
    for word in LEGACY:
        forms.setdefault(word, ("typebar-legacy", "Typebar authored starter vocabulary"))
    return forms, counts, first, owners, len(seen)


def priority(word, counts):
    return -counts[word.lower()], word


def select(forms, counts):
    pools = {}
    for name, (count, maximum, upper, hyphen, phrase) in SPECS.items():
        eligible = {w for w in forms if len(w) <= maximum and set(w) <= set(CHARACTERS[name])}
        required = set(LEGACY) | set(pools.get("basic", []))
        require(required <= eligible, "missing legacy/base seed")
        result = set()
        for category, amount in [("upper", upper), ("hyphen", hyphen), ("phrase", phrase), ("plain", count - upper - hyphen - phrase)]:
            def matches(word):
                if category == "upper": return any(c.isupper() for c in word) and word.isalpha()
                if not word.islower(): return False
                if category == "phrase": return " " in word and "-" not in word
                if category == "hyphen": return "-" in word and " " not in word
                return word.isalpha()
            candidates = sorted((w for w in eligible if matches(w)), key=lambda w: priority(w, counts))
            chosen = required.intersection(candidates)
            if category == "plain" and not any(len(w) == maximum for w in chosen):
                chosen.add(next(w for w in candidates if len(w) == maximum))
            require(len(chosen) <= amount, "seed exceeds quota")
            for word in candidates:
                if len(chosen) == amount: break
                chosen.add(word)
            require(len(chosen) == amount, "insufficient literal category forms")
            result.update(chosen)
        require(len(result) == count and required <= result and set("".join(result)) == set(CHARACTERS[name]), "count/character coverage mismatch")
        pools[name] = sorted(result, key=lambda w: priority(w, counts))
    return pools


def artifacts(dictionary, sentences):
    forms, counts, first, owners, sentence_count = read_sources(dictionary, sentences)
    pools = select(forms, counts)
    native = '// Independent Malay forms; see bundled CC BY-SA / CC BY attribution.\nenum MalayCorpus {\n  static let revision = ' + json.dumps(REVISION) + '\n'
    for name, words in pools.items():
        native += '  static let ' + ("basic" if name == "basic" else "words1k") + ': [String] = """\n' + "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    native += '}\n'
    rows = '# word\tsourceKind\tsourceTitle\tMalayTokenOccurrences\tfirstSentenceID (NA means unobserved)\n'
    for word in sorted(set().union(*map(set, pools.values()))):
        kind, title = forms[word]; key = word.lower()
        rows += '\t'.join([word, kind, title, str(counts[key]) if counts[key] else 'NA', first.get(key, 'NA')]) + '\n'
    notice = f"""Typebar independent Malay corpus
Revision: {REVISION}
English Wiktionary contributors, extracted by Kaikki.org / Wiktextract.
Source: {DICTIONARY_URL}
Snapshot SHA-256: {DICTIONARY_SHA}
Index: extraction 2026-10-30, enwiktionary dump 2026-10-01.
Dictionary selection: Creative Commons Attribution-ShareAlike 4.0 International.
https://creativecommons.org/licenses/by-sa/4.0/
Dictionary rows link to https://en.wiktionary.org/wiki/ + encoded sourceTitle.
Only lang_code=ms lexical entries, original ASCII forms and declared character sets.
No inflection, recasing, numbered padding or Indonesian frequency substitution.
Romanization/template/error forms and exclusively rejected lexical senses excluded.
Filters do not certify normative/semantic quality of every word.
All 30 Typebar authored starter words retained. latihan and harapan have legacy
provenance, not dictionary attestations. Missing observations are NA, not zero frequency.

Frequency observations: Tatoeba standard Malay (zsm) contributors.
Source: {SENTENCES_URL}
Snapshot SHA-256: {SENTENCES_SHA}
Sentences: {sentence_count}. CC BY 2.0 France (CC0 records may also be included).
https://creativecommons.org/licenses/by/2.0/fr/
https://tatoeba.org/en/downloads
Whole Unicode word runs after NFC; complete ASCII tokens only, internal hyphens kept.
Phrase observations require exactly one literal space between adjacent full tokens.
Lookup is lowercased; practice forms are unchanged. Counts describe this snapshot,
not general usage, Monkeytype's distribution or native runtime Zipf support.
MalayCorpusSources.txt records per-form title, count and first observing sentence ID.
Sentence attribution page: https://tatoeba.org/en/sentences/show/ + sentence ID.
No sentences, translations, definitions, images, audio or original Monkeytype lists bundled.
Selection changes filtering/order, not literal spellings. Source generator in repository.

Public Tatoeba contributor handles in the fixed snapshot (\\N means unknown/unowned):
""" + ''.join('- ' + owner + '\n' for owner in sorted(owners))
    output = {SWIFT: native.encode(), ROWS: rows.encode(), NOTICE: notice.encode()}
    doc = {"schemaVersion": 1, "revision": REVISION, "dictionary": DICTIONARY_URL, "dictionarySHA256": DICTIONARY_SHA,
        "sentences": SENTENCES_URL, "sentencesSHA256": SENTENCES_SHA, "sentenceCount": sentence_count,
        "artifacts": {p: sha(b) for p, b in output.items()}, "pools": {}}
    for name, words in pools.items():
        doc['pools'][name] = {"count": len(words), "minimumLength": min(map(len, words)), "maximumLength": max(map(len, words)),
            "characters": ''.join(sorted(set(''.join(words)))), "uppercaseCount": sum(any(c.isupper() for c in w) for w in words),
            "hyphenCount": sum('-' in w for w in words), "spaceCount": sum(' ' in w for w in words),
            "wholeObserved": sum(counts[w.lower()] > 0 for w in words), "wordsSHA256": sha(('\n'.join(words) + '\n').encode())}
    output[MANIFEST] = (json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=True) + '\n').encode()
    return output


def verify_bundled(root):
    require(bool(PUBLISHED), "immutable pins required")
    for name, digest in PUBLISHED.items(): require(sha((root / name).read_bytes()) == digest, "artifact pin mismatch: " + name)
    doc = json.loads((root / MANIFEST).read_text()); require(doc['revision'] == REVISION, "revision mismatch")
    pools = {('basic' if k == 'basic' else '1k'): v.splitlines() for k, v in re.findall(r'static let (basic|words1k): \[String\] = """\n(.*?)\n"""', (root / SWIFT).read_text(), re.S)}
    require(list(pools) == list(SPECS), "missing native pools")
    rows = [line.split('\t') for line in (root / ROWS).read_text().splitlines() if not line.startswith('#')]
    require(len(rows) == len({r[0] for r in rows}) and all(len(r) == 5 and r[1] in {'dictionary', 'typebar-legacy'} and r[2]
        and ((r[3] == r[4] == 'NA') or (r[3].isdigit() and int(r[3]) > 0 and r[4].isdigit())) for r in rows), "invalid provenance")
    require({r[0] for r in rows} == set().union(*map(set, pools.values())), "incomplete provenance")
    for name, words in pools.items():
        count, maximum, upper, hyphen, phrase = SPECS[name]
        require(len(words) == len(set(words)) == count and set(LEGACY) <= set(words), "count/legacy mismatch")
        require(all(literal(w) for w in words) and min(map(len, words)) == 2 and max(map(len, words)) == maximum, "literal/length mismatch")
        require(set(''.join(words)) == set(CHARACTERS[name]), "character set mismatch")
        require(sum(any(c.isupper() for c in w) for w in words) == upper and sum('-' in w for w in words) == hyphen and sum(' ' in w for w in words) == phrase, "category mismatch")
        require(sha(('\n'.join(words) + '\n').encode()) == doc['pools'][name]['wordsSHA256'], "word pin mismatch")


class Contracts(unittest.TestCase):
    def test_literal_fields_reject_padding_shapes(self):
        self.assertTrue(literal('kanak-kanak')); self.assertTrue(literal('hari ini'))
        for w in ['-anak', 'anak-', 'a  b', 'abc1', 'é', ' a', 'a ']: self.assertFalse(literal(w))

    def test_exact_whole_token_and_phrase_boundaries(self):
        values = list(observations('café buku-buku hari ini, bukan  hari.'))
        self.assertNotIn('caf', values); self.assertIn('buku-buku', values)
        self.assertIn('hari ini', values); self.assertNotIn('bukan hari', values)

    def test_other_language_and_invalid_senses_are_excluded(self):
        for change in [{'lang_code': 'id'}, {'pos': 'prefix'}, {'senses': [{'tags': ['misspelling']}]}]:
            forms = {}; collect(dict({'lang_code': 'ms', 'pos': 'noun', 'word': 'anak'}, **change), forms); self.assertEqual(forms, {})


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--dictionary', type=Path); parser.add_argument('--sentences', type=Path)
    parser.add_argument('--output-root', type=Path); parser.add_argument('--check', action='store_true')
    parser.add_argument('--self-test', action='store_true'); parser.add_argument('--check-bundled', action='store_true'); args = parser.parse_args()
    if args.self_test: return 0 if unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Contracts)).wasSuccessful() else 1
    if args.check_bundled: verify_bundled(args.output_root or ROOT); print('Malay bundled corpus verified'); return 0
    require(args.dictionary and args.sentences and args.output_root, 'explicit pinned sources and output root required')
    output = artifacts(args.dictionary, args.sentences)
    if PUBLISHED: require({p: sha(b) for p, b in output.items()} == PUBLISHED, 'reproduction pin mismatch')
    for name, data in output.items():
        target = args.output_root / name
        if args.check: require(target.read_bytes() == data, 'source reproduction mismatch: ' + name)
        else:
            require(not target.exists(), 'refusing to overwrite artifact'); target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
    print('Malay source reproduction checked' if args.check else 'Malay corpus prepared'); return 0


if __name__ == '__main__': raise SystemExit(main())
