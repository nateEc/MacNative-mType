#!/usr/bin/env python3
"""Build independent Kyrgyz literal pools from pinned dictionary and sentence data."""
import argparse
import bz2
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import unicodedata
import unittest
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
DICTIONARY_URL = 'https://kaikki.org/dictionary/Kyrgyz/kaikki.org-dictionary-Kyrgyz.jsonl'
DICTIONARY_SHA = '1d9ccd82e6ac3215a77806be47b933a209a8cc087353576f92ccc43cc022859c'
SENTENCES_URL = 'https://downloads.tatoeba.org/exports/per_language/kir/kir_sentences_detailed.tsv.bz2'
SENTENCES_SHA = 'd667a6b75f9a3e4c4fad3225f60c029cbb6d100da21484361e1482eac0c2f874'
REVISION = 'kaikki-en-ky-tatoeba-kir-20261102-literal-v1'
LETTERS = 'абвгдежзийклмнопрстуфхцчшыьэюяңүө'
CHARACTERS = {'basic': '-абгдежзийклмнопрстучшыэюяңүө', '1k': ' ,-МО' + LETTERS}
SPECS = {'basic': (234, 9, 1, 0), '1k': (849, 13, 8, 10)}
LIMITS = {'basic': {'plain': 233, 'hyphen': 1}, '1k': {'plain': 827, 'phrase': 10, 'hyphen': 8, 'comma': 2, 'upper': 1, 'upper-comma': 1}}
LEGACY = 'салам мен сен биз китеп калем үй жол жарык убакыт суу деңиз күн түн ай дос эртең бүгүн көз барак ой иш баштоо кадам сөз суроо жооп тоо'.split()
PARTS = set('noun verb adj adv name pron num det conj intj prep postp particle phrase abbrev'.split())
BAD = {'misspelling', 'proscribed', 'nonstandard'}
SWIFT = 'Sources/Typebar/KyrgyzCorpus.generated.swift'
ROWS = 'Resources/KyrgyzCorpusSources.txt'
NOTICE = 'Resources/KyrgyzCorpusNotices.txt'
MANIFEST = 'Compatibility/kyrgyz-corpus.json'
PUBLISHED = {'Compatibility/kyrgyz-corpus.json': 'cddc1f1009ab2a790f8d148ecda18669bb36e1ccf71965a648b1106eddebdda8', 'Resources/KyrgyzCorpusSources.txt': '3b1f5777c3b5224594a3c14dc29d1d67a3e335f5fefa97f94c53e06409fd33b1', 'Resources/KyrgyzCorpusNotices.txt': 'e7990c994a7ff1fce2210c8e81fa508185140c4e3e6ebb63e22233b486830089', 'Sources/Typebar/KyrgyzCorpus.generated.swift': '8d5587328d25101930e7410c0482947507b562506f56653b7d90b79d701b4b33'}


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def literal(word):
    if not (type(word) is str and 2 <= len(word) <= 13
            and word == unicodedata.normalize('NFC', word)
            and set(word) <= set(CHARACTERS['1k'])):
        return False
    body = word[:-1] if word.endswith(',') else word
    if re.fullmatch('[МО]?[' + LETTERS + ']+(?:[- ][' + LETTERS + ']+)?', body) is None:
        return False
    upper = any(c.isupper() for c in word)
    if word.endswith(','):
        return ' ' not in body and '-' not in body and (not upper or word.startswith('О'))
    return not upper or word.startswith('М') and ' ' not in word and '-' not in word


def collect(entry, forms):
    require(type(entry) is dict, 'invalid entry')
    if entry.get('lang_code') != 'ky' or entry.get('pos') not in PARTS:
        return
    senses = entry.get('senses', [])
    require(type(senses) is list and all(type(s) is dict for s in senses), 'invalid senses')
    if not senses or all(BAD.intersection(s.get('tags', [])) for s in senses):
        return
    title = entry.get('word')
    require(type(title) is str and not any(c in title for c in '\t\r\n'), 'invalid title')
    rows = entry.get('forms', [])
    require(type(rows) is list, 'invalid forms')
    for row in [{'form': title}] + rows:
        require(type(row) is dict and type(row.get('form')) is str, 'invalid form')
        tags = row.get('tags', [])
        require(type(tags) is list and all(type(t) is str for t in tags), 'invalid tags')
        if BAD.intersection(tags) or any(t in {'romanization', 'table-tags', 'inflection-template', 'class'} or t.startswith('error-') for t in tags):
            continue
        word = row['form']
        if (' ' in word or '-' in word) and word != title:
            continue
        if ',' not in word and literal(word):
            forms.setdefault(word, ('dictionary', title))


def spans(text):
    result, start = [], None
    for i, c in enumerate(text):
        inside = c.isalnum() or c in "_-'’" or unicodedata.category(c).startswith('M')
        if inside and start is None:
            start = i
        elif not inside and start is not None:
            result.append((start, i)); start = None
    if start is not None:
        result.append((start, len(text)))
    return result


def matches(text, candidates):
    text = unicodedata.normalize('NFC', text)
    # Comma options keep literal source case; dictionary word/phrase queries
    # use lowercase keys without changing the delivered option spelling.
    folded = {}
    for word in candidates:
        if not word.endswith(','):
            folded.setdefault(word.lower(), []).append(word)
    result = set()
    tokens = spans(text)
    for i, (begin, end) in enumerate(tokens):
        word = text[begin:end]
        result.update(folded.get(word.lower(), []))
        if text[end:end + 1] == ',':
            exact = word + ','
            if exact in candidates:
                result.add(exact)
        if i + 1 < len(tokens) and text[end:tokens[i + 1][0]] == ' ':
            result.update(folded.get(text[begin:tokens[i + 1][1]].lower(), []))
    return result


def read_sources(dictionary, sentences):
    require(sha(dictionary.read_bytes()) == DICTIONARY_SHA, 'dictionary pin mismatch')
    forms = {}
    for line in dictionary.open(encoding='utf-8'):
        collect(json.loads(line), forms)
    for word in LEGACY:
        forms.setdefault(word, ('typebar-legacy', 'Typebar authored starter vocabulary'))
    require(sha(sentences.read_bytes()) == SENTENCES_SHA, 'sentence pin mismatch')
    rows, authors, identifiers = [], set(), set()
    for line in bz2.open(sentences, 'rt', encoding='utf-8'):
        f = line.rstrip('\n').split('\t')
        require(len(f) == 6 and f[0].isdigit() and f[1] == 'kir', 'invalid sentence')
        identifier, _, text, author, _, _ = f
        require(identifier not in identifiers, 'duplicate sentence')
        identifiers.add(identifier)
        author = author if author not in {'', '\\N'} else '(unowned)'
        authors.add(author); rows.append((identifier, text, author))
        text = unicodedata.normalize('NFC', text)
        for begin, end in spans(text):
            if text[end:end + 1] == ',':
                word = text[begin:end + 1]
                if literal(word):
                    forms.setdefault(word, ('tatoeba-literal', 'Tatoeba sentence ' + identifier))
    counts, first = Counter(), {}
    for identifier, text, author in rows:
        for word in matches(text, forms):
            counts[word] += 1
            first.setdefault(word, (identifier, author))
    return forms, counts, first, sorted(authors), len(identifiers)


def category(word):
    if any(c.isupper() for c in word):
        return 'upper-comma' if word.endswith(',') else 'upper'
    return 'comma' if word.endswith(',') else 'phrase' if ' ' in word else 'hyphen' if '-' in word else 'plain'


def select(forms, counts):
    def rank(word):
        kind, title = forms[word]
        return (word not in counts, -counts.get(word, 0), word != title, word)
    pools = {}
    for name, (count, maximum, hyphens, phrases) in SPECS.items():
        eligible = {w for w in forms if set(w) <= set(CHARACTERS[name]) and
                    len(w) <= maximum}
        chosen = set(LEGACY) | set(pools.get('basic', []))
        require(chosen <= eligible, 'missing old/basic seed')
        limits = LIMITS[name]
        used = Counter(map(category, chosen))
        def add_best(candidates, key=rank):
            word = min((w for w in candidates if w not in chosen and used[category(w)] < limits[category(w)]), key=key, default=None)
            require(word is not None, 'insufficient eligible words')
            chosen.add(word); used[category(word)] += 1
        for length in [2, maximum]:
            if not any(len(w) == length for w in chosen):
                add_best(w for w in eligible if len(w) == length and category(w) == 'plain')
        missing = set(CHARACTERS[name]) - set(''.join(chosen))
        while missing:
            add_best((w for w in eligible if set(w) & missing), lambda w: (-len(set(w) & missing), rank(w)))
            missing = set(CHARACTERS[name]) - set(''.join(chosen))
        for key, limit in limits.items():
            require(used[key] <= limit, 'seed quota exceeded')
            options = sorted((w for w in eligible if w not in chosen and category(w) == key), key=rank)
            needed = limit - used[key]
            require(len(options) >= needed, 'insufficient category')
            chosen.update(options[:needed])
        require(len(chosen) == count and dict(Counter(map(category, chosen))) == {k: v for k, v in limits.items() if v}, 'quota mismatch')
        pools[name] = sorted(chosen, key=rank)
    return pools


def artifacts(dictionary, sentences):
    forms, counts, first, authors, sentence_count = read_sources(dictionary, sentences)
    pools = select(forms, counts)
    native = '// Independent Kyrgyz literal forms and excerpts; see bundled licenses.\n// See bundled provenance; original Monkeytype words are never read here.\nenum KyrgyzCorpus {\n  static let revision = ' + json.dumps(REVISION) + '\n'
    for name, words in pools.items():
        native += '  static let ' + ('basic' if name == 'basic' else 'words1k') + ': [String] = """\n' + '\n'.join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    native += '}\n'
    union = sorted(set().union(*map(set, pools.values())))
    rows = '# word\tsourceKind\tsourceTitle\ttatoebaWholeOptionSentenceCount\tfirstSentenceID\tfirstSentenceAuthor (NA means unobserved)\n'
    for word in union:
        identifier, author = first.get(word, ('NA', 'NA'))
        rows += '\t'.join([word, *forms[word], str(counts[word]) if word in counts else 'NA', identifier, author]) + '\n'
    unattested = sorted(w for w in LEGACY if forms[w][0] == 'typebar-legacy')
    notice = f"""Typebar independent Kyrgyz corpus
Revision: {REVISION}
English Wiktionary contributors via Kaikki.org / Wiktextract.
Dictionary: {DICTIONARY_URL}
Snapshot SHA-256: {DICTIONARY_SHA}
Index reports extraction 2026-10-25, enwiktionary dump 2026-10-01,
extractor revisions f9fe161 and 6f96ddf.
Dictionary selection: CC BY-SA 4.0 International.
https://creativecommons.org/licenses/by-sa/4.0/
Dictionary contributor page: https://en.wiktionary.org/wiki/ + encoded sourceTitle.
Only unchanged NFC lexical titles/forms with lang_code=ky are selected;
misspelling/proscribed/nonstandard-only senses and tagged romanization,
template or error forms are excluded. Hyphens and phrases must be literal
headword titles; no multiword inflection-table variants are used for quotas.
All 28 Typebar old starters remain in both pools. Selected lexical attestation
missing for: {', '.join(unattested) or '(none)'}.
This reports selected lexical forms, not absence of other raw entries.
The basic pool has 234 entries, length 2-9 and one hyphenated option.
The 849-entry pool retains the basic pool, length 2-13, eight hyphenated
options, ten two-word headwords, two lowercase comma options, one uppercase-M
single word and one uppercase-O comma option. Spellings are never recased.
Phrases consume separate runtime word slots; literal punctuation is retained.
No numbered padding, spelling synthesis or original Monkeytype words.
Per-word source and first observed sentence/author: KyrgyzCorpusSources.txt.

Tatoeba Kyrgyz contributors: CC BY 2.0 France.
Sentences: {SENTENCES_URL}
Snapshot SHA-256: {SENTENCES_SHA}
Sentence rows: {sentence_count}; contributor identifiers: {len(authors)}.
https://creativecommons.org/licenses/by/2.0/fr/
https://tatoeba.org/en/downloads
The three comma options are unchanged literal token excerpts from this
snapshot, not dictionary headwords or dictionary spelling adaptations.
Their sourceKind is tatoeba-literal and sourceTitle names a source sentence.
Only selected short options and provenance are bundled, not the whole archive,
translations or audio. Comma observation queries preserve exact source case.
Other word/phrase observations use lowercase lookup; one match per sentence.
Unicode letters/digits, combining marks, hyphens, underscores and apostrophes
remain inside token boundaries. Phrases require one ASCII space and cannot
cross punctuation, adjacent spaces or tabs. No component-frequency estimates.
Unobserved dictionary options prefer headword titles over inflected forms.
Missing observations stay NA, never zero; these are not runtime Zipf values.
Vocabulary quality and frequency distribution are not certified equivalent
to Monkeytype. All processed contributor identifiers follow; unknown rows
are explicit. Observation evidence is not linguistic or device acceptance.

""" + '\n'.join(a if a == '(unowned)' else a + ' https://tatoeba.org/en/user/profile/' + quote(a, safe='') for a in authors) + '\n'
    output = {SWIFT: native.encode(), ROWS: rows.encode(), NOTICE: notice.encode()}
    manifest = {'schemaVersion': 1, 'revision': REVISION, 'dictionary': DICTIONARY_URL, 'dictionarySHA256': DICTIONARY_SHA, 'sentences': SENTENCES_URL, 'sentencesSHA256': SENTENCES_SHA, 'sentenceRows': sentence_count, 'contributorIdentifiers': len(authors), 'legacyUnattested': unattested, 'artifacts': {p: sha(b) for p, b in output.items()}, 'pools': {}}
    for name, words in pools.items():
        manifest['pools'][name] = {'count': len(words), 'minimumLength': min(map(len, words)), 'maximumLength': max(map(len, words)), 'characters': ''.join(sorted(set(''.join(words)))), 'categories': dict(Counter(map(category, words))), 'observedOptions': sum(w in counts for w in words), 'observedPhrases': sum(' ' in w and w in counts for w in words), 'observedHyphens': sum('-' in w and w in counts for w in words), 'observedCommaOptions': sum(w.endswith(',') and w in counts for w in words), 'legacyLengthExceptions': sorted(w for w in words if len(w) > SPECS[name][1]), 'wordsSHA256': sha(('\n'.join(words) + '\n').encode())}
    output[MANIFEST] = (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + '\n').encode()
    return output


def verify_bundled(root):
    require(bool(PUBLISHED), 'immutable pins required')
    for name, digest in PUBLISHED.items():
        require(sha((root / name).read_bytes()) == digest, 'published pin mismatch: ' + name)
    native = (root / SWIFT).read_text()
    pools = {('basic' if n == 'basic' else '1k'): s.splitlines() for n, s in re.findall(r'static let (basic|words1k): \[String\] = """\n(.*?)\n"""', native, re.S)}
    require(list(pools) == list(SPECS), 'missing pools')
    rows = [line.split('\t') for line in (root / ROWS).read_text().splitlines() if not line.startswith('#')]
    require(all(len(r) == 6 and r[1] in {'dictionary', 'typebar-legacy', 'tatoeba-literal'} and r[2] and
                (r[3:] == ['NA', 'NA', 'NA'] or r[3].isdigit() and int(r[3]) > 0 and r[4].isdigit() and r[5]) and
                (category(r[0]) not in {'phrase', 'hyphen'} or r[0] == r[2]) and (not r[0].endswith(',') or r[1] == 'tatoeba-literal' and r[3] != 'NA') for r in rows), 'invalid provenance')
    provenance = {r[0]: r for r in rows}
    require(len(rows) == len(provenance) and set(provenance) == set().union(*map(set, pools.values())), 'incomplete provenance')
    doc = json.loads((root / MANIFEST).read_text())
    for name, words in pools.items():
        count, maximum, hyphens, phrases = SPECS[name]
        require(len(words) == len(set(words)) == count and set(LEGACY) <= set(words) and set(pools['basic']) <= set(words), 'count/retention mismatch')
        require(all(literal(w) and len(w) <= maximum for w in words) and min(map(len, words)) == 2, 'literal/length mismatch')
        require(set(''.join(words)) == set(CHARACTERS[name]), 'typing alphabet mismatch')
        require(dict(Counter(map(category, words))) == LIMITS[name], 'category mismatch')
        require(doc['pools'][name]['wordsSHA256'] == sha(('\n'.join(words) + '\n').encode()), 'word pin mismatch')
        require(doc['pools'][name]['observedOptions'] == sum(provenance[w][3] != 'NA' for w in words), 'observation mismatch')


class ContractTests(unittest.TestCase):
    def test_literal_keeps_case_and_only_admitted_shapes(self):
        for w in ['ата-эне', 'үй-бүлө', 'көз айнек', 'Москва', 'Ошентип,', 'эмес,']:
            self.assertTrue(literal(w), w)
        for w in ['Өз', 'Ооба', 'Мекен,', 'эки  сөз', 'кирили.', 'ԝаб', 'а', '-сөз', 'сөз-']:
            self.assertFalse(literal(w), w)

    def test_dictionary_filter_does_not_synthesize_phrase_or_comma(self):
        f = {}
        collect({'lang_code': 'ky', 'pos': 'noun', 'word': 'көз айнек', 'senses': [{}], 'forms': [{'form': 'көз айнеги'}, {'form': 'сөз,'}, {'form': 'кирип', 'tags': ['romanization']}]}, f)
        self.assertEqual(f, {'көз айнек': ('dictionary', 'көз айнек')})

    def test_observations_keep_literal_commas_and_whole_unicode_boundaries(self):
        c = {'Ошентип,', 'эмес,', 'ата-эне', 'көз айнек', 'Москва'}
        self.assertEqual(matches('Ошентип, эмес, ата-эне көз айнек Москва', c), c)
        for t in ['ошентип,', 'Эмес,', 'ата-энелер', 'көз  айнек', 'көз, айнек', 'көз\tайнек', 'көз айнек2', 'Москва\u0301']:
            self.assertFalse(matches(t, c), t)



def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--dictionary', type=Path); p.add_argument('--sentences', type=Path)
    p.add_argument('--output', type=Path); p.add_argument('--check', action='store_true')
    p.add_argument('--check-bundled', action='store_true'); p.add_argument('--self-test', action='store_true')
    a = p.parse_args()
    if a.self_test:
        raise SystemExit(not unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests)).wasSuccessful())
    if a.check_bundled:
        verify_bundled(ROOT); print('Kyrgyz pinned corpus/provenance check passed'); return
    require(a.dictionary and a.sentences and a.output, 'dictionary, sentences and output required')
    output = artifacts(a.dictionary, a.sentences)
    if PUBLISHED:
        require({n: sha(b) for n, b in output.items()} == PUBLISHED, 'reproduction pins mismatch')
    for n, data in output.items():
        path = a.output / n
        if a.check:
            require(path.read_bytes() == data, 'reproduction mismatch: ' + n)
        else:
            require(not path.exists(), 'refusing to overwrite: ' + n)
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    print('Kyrgyz source reproduction checked' if a.check else 'Kyrgyz corpus prepared')


if __name__ == '__main__':
    main()
