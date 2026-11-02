#!/usr/bin/env python3
"""Build independent Kazakh literal pools from pinned dictionary and sentence data."""
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
DICTIONARY_URL = 'https://kaikki.org/dictionary/Kazakh/kaikki.org-dictionary-Kazakh.jsonl'
DICTIONARY_SHA = 'a1655f3a9fefbe802a63e44536d925097a076ce77809103da426ffc2f4ea9dc0'
SENTENCES_URL = 'https://downloads.tatoeba.org/exports/per_language/kaz/kaz_sentences_detailed.tsv.bz2'
SENTENCES_SHA = '60de70798d3f0857a361d1d3daa4cf373da1e6cc394b0feca1070d7c67c7020c'
REVISION = 'kaikki-en-kk-tatoeba-kaz-20261102-literal-v1'
LETTERS = 'абвгдежзийклмнопрстуфхцчшыьэюяіғқңүұәө'
CHARACTERS = {'basic': 'абгдежзийклмнопрстухшыюяіғқңүұәө', '1k': ' -' + LETTERS}
SPECS = {'basic': (202, 7, 0, 0), '1k': (990, 16, 4, 3)}
LEGACY = 'кітап есік жол жарық көпір таң бет орын бұлт тыныштық тау тұқым дауыс үстел ой сөйлем көзқарас тәжірибе қашықтық қадам сабыр тепе теңдік ауыл жаңбыр жұлдыз дос үміт еңбек өзен'.split()
PARTS = set('noun verb adj adv name pron num det conj intj prep postp particle phrase abbrev'.split())
BAD = {'misspelling', 'proscribed', 'nonstandard'}
SWIFT = 'Sources/Typebar/KazakhCorpus.generated.swift'
ROWS = 'Resources/KazakhCorpusSources.txt'
NOTICE = 'Resources/KazakhCorpusNotices.txt'
MANIFEST = 'Compatibility/kazakh-corpus.json'
PUBLISHED = {'Compatibility/kazakh-corpus.json': '712fde159d9364a81abf0cf836933ade63fe055504adca38736e2524d6d0731a', 'Resources/KazakhCorpusSources.txt': 'bdd384af2d9e6c135cf581ee860d2487042000d6e57600bce5f0e821437f9837', 'Resources/KazakhCorpusNotices.txt': '215e30485974317456d0ca91a234570f4ee30e83d93cdca3cb5ab28e3c5ff0f9', 'Sources/Typebar/KazakhCorpus.generated.swift': 'abefb43becae340936f13197f9861248a1e033b7b26768d84b44e821e5376153'}


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def literal(word):
    return (type(word) is str and 2 <= len(word) <= 16
            and word == unicodedata.normalize('NFC', word)
            and re.fullmatch('[' + LETTERS + ']+(?:[- ][' + LETTERS + ']+)?', word) is not None)


def collect(entry, forms):
    require(type(entry) is dict, 'invalid entry')
    if entry.get('lang_code') != 'kk' or entry.get('pos') not in PARTS:
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
        if literal(word):
            forms.setdefault(word, ('dictionary', title))


def matches(text, candidates):
    text = unicodedata.normalize('NFC', text).lower()
    spans, start = [], None
    for index, c in enumerate(text):
        inside = c.isalnum() or c in "_-'’" or unicodedata.category(c).startswith('M')
        if inside and start is None:
            start = index
        elif not inside and start is not None:
            spans.append((start, index)); start = None
    if start is not None:
        spans.append((start, len(text)))
    result = set()
    for i, (begin, end) in enumerate(spans):
        word = text[begin:end]
        if word in candidates:
            result.add(word)
        if i + 1 < len(spans) and text[end:spans[i + 1][0]] == ' ':
            phrase = text[begin:spans[i + 1][1]]
            if phrase in candidates:
                result.add(phrase)
    return result


def read_sources(dictionary, sentences):
    require(sha(dictionary.read_bytes()) == DICTIONARY_SHA, 'dictionary pin mismatch')
    forms = {}
    for line in dictionary.open(encoding='utf-8'):
        collect(json.loads(line), forms)
    for word in LEGACY:
        forms.setdefault(word, ('typebar-legacy', 'Typebar authored starter vocabulary'))
    require(sha(sentences.read_bytes()) == SENTENCES_SHA, 'sentence pin mismatch')
    counts, first, authors, identifiers = Counter(), {}, set(), set()
    for line in bz2.open(sentences, 'rt', encoding='utf-8'):
        fields = line.rstrip('\n').split('\t')
        require(len(fields) == 6 and fields[0].isdigit() and fields[1] == 'kaz', 'invalid sentence')
        identifier, _, text, author, _, _ = fields
        require(identifier not in identifiers, 'duplicate sentence')
        identifiers.add(identifier)
        author = author if author not in {'', '\\N'} else '(unowned)'
        authors.add(author)
        for word in matches(text, forms):
            counts[word] += 1
            first.setdefault(word, (identifier, author))
    return forms, counts, first, sorted(authors), len(identifiers)


def category(word):
    return 'phrase' if ' ' in word else 'hyphen' if '-' in word else 'plain'


def select(forms, counts):
    def rank(word):
        kind, title = forms[word]
        return (word not in counts, -counts.get(word, 0), word != title, word)
    pools = {}
    for name, (count, maximum, hyphens, phrases) in SPECS.items():
        eligible = {w for w in forms if set(w) <= set(CHARACTERS[name]) and
                    (len(w) <= maximum or name == 'basic' and w in LEGACY)}
        chosen = set(LEGACY) | set(pools.get('basic', []))
        require(chosen <= eligible, 'missing old/basic seed')
        limits = {'plain': count - hyphens - phrases, 'hyphen': hyphens, 'phrase': phrases}
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
    native = '// Independent Kazakh literal forms, CC BY-SA 4.0.\n// See bundled provenance; original Monkeytype words are never read here.\nenum KazakhCorpus {\n  static let revision = ' + json.dumps(REVISION) + '\n'
    for name, words in pools.items():
        native += '  static let ' + ('basic' if name == 'basic' else 'words1k') + ': [String] = """\n' + '\n'.join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    native += '}\n'
    union = sorted(set().union(*map(set, pools.values())))
    rows = '# word\tsourceKind\tsourceTitle\ttatoebaWholeOptionSentenceCount\tfirstSentenceID\tfirstSentenceAuthor (NA means unobserved)\n'
    for word in union:
        identifier, author = first.get(word, ('NA', 'NA'))
        rows += '\t'.join([word, *forms[word], str(counts[word]) if word in counts else 'NA', identifier, author]) + '\n'
    unattested = sorted(w for w in LEGACY if forms[w][0] == 'typebar-legacy')
    notice = f'''Typebar independent Kazakh corpus
Revision: {REVISION}
English Wiktionary contributors via Kaikki.org / Wiktextract.
Dictionary: {DICTIONARY_URL}
Snapshot SHA-256: {DICTIONARY_SHA}
Index reports extraction 2026-10-30, enwiktionary dump 2026-10-01,
extractor revisions 19f9a30 and 6f96ddf.
Dictionary selection: CC BY-SA 4.0 International.
https://creativecommons.org/licenses/by-sa/4.0/
Per-word contributor page: https://en.wiktionary.org/wiki/ + encoded sourceTitle.
Selection filters/ranks unchanged literal NFC lowercase Cyrillic forms of kk
lexical entries. Misspelling/proscribed/nonstandard-only senses and tagged
romanization/template/error forms are excluded. Hyphens and phrases must be
literal headword titles; inflection tables cannot synthesize them for quotas.
All 30 old Typebar starters remain in both pools; selected lexical attestation
missing for: {', '.join(unattested) or '(none)'}.
This reports selected lexical forms, not absence of other raw entries.
The basic pool has 202 options and the original typing alphabet. Four retained
old words exceed the reference basic maximum of 7 letters: тыныштық, көзқарас,
тәжірибе, қашықтық (8 letters). All newly selected basic words have at most 7.
The 990-option pool retains the basic pool, four literal hyphenated options,
three two-word headwords, length 2-16 and its separate complete typing alphabet.
Phrase components consume separate runtime word slots; hyphens remain literal.
No spelling synthesis, numbered padding, definitions, sentence text, examples,
translations, audio or original Monkeytype words are bundled.
Per-word provenance: KazakhCorpusSources.txt; reproduction script in repository.

Tatoeba Kazakh contributors, observation evidence only.
Sentences: {SENTENCES_URL}
Snapshot SHA-256: {SENTENCES_SHA}
Sentence rows: {sentence_count}; contributor identifiers: {len(authors)}.
Sentence data: CC BY 2.0 France.
https://creativecommons.org/licenses/by/2.0/fr/
https://tatoeba.org/en/downloads
Ranking counts whole-option matching sentences (once per sentence), using NFC
lowercase Unicode token boundaries. Hyphens, apostrophes, digits, underscores
and combining marks stay inside boundaries; phrases require one ASCII space.
Missing observations remain NA, never zero or component-frequency estimates.
Unobserved dictionary options prefer headword titles over inflected forms.
These sentence observations are not runtime Zipf support, a representative
frequency model or a certification of linguistic quality. Vocabulary and
frequency distribution are not claimed equivalent to Monkeytype.
All processed snapshot contributor identifiers follow; unknown rows are explicit.

''' + '\n'.join(a if a == '(unowned)' else a + ' https://tatoeba.org/en/user/profile/' + quote(a, safe='') for a in authors) + '\n'
    output = {SWIFT: native.encode(), ROWS: rows.encode(), NOTICE: notice.encode()}
    manifest = {'schemaVersion': 1, 'revision': REVISION, 'dictionary': DICTIONARY_URL, 'dictionarySHA256': DICTIONARY_SHA, 'sentences': SENTENCES_URL, 'sentencesSHA256': SENTENCES_SHA, 'sentenceRows': sentence_count, 'contributorIdentifiers': len(authors), 'legacyUnattested': unattested, 'artifacts': {p: sha(b) for p, b in output.items()}, 'pools': {}}
    for name, words in pools.items():
        manifest['pools'][name] = {'count': len(words), 'minimumLength': min(map(len, words)), 'maximumLength': max(map(len, words)), 'characters': ''.join(sorted(set(''.join(words)))), 'categories': dict(Counter(map(category, words))), 'observedOptions': sum(w in counts for w in words), 'observedPhrases': sum(' ' in w and w in counts for w in words), 'observedHyphens': sum('-' in w and w in counts for w in words), 'legacyLengthExceptions': sorted(w for w in words if len(w) > SPECS[name][1]), 'wordsSHA256': sha(('\n'.join(words) + '\n').encode())}
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
    require(all(len(r) == 6 and r[1] in {'dictionary', 'typebar-legacy'} and r[2] and
                (r[3:] == ['NA', 'NA', 'NA'] or r[3].isdigit() and int(r[3]) > 0 and r[4].isdigit() and r[5]) and
                (category(r[0]) == 'plain' or r[0] == r[2]) for r in rows), 'invalid provenance')
    provenance = {r[0]: r for r in rows}
    require(len(rows) == len(provenance) and set(provenance) == set().union(*map(set, pools.values())), 'incomplete provenance')
    doc = json.loads((root / MANIFEST).read_text())
    for name, words in pools.items():
        count, maximum, hyphens, phrases = SPECS[name]
        require(len(words) == len(set(words)) == count and set(LEGACY) <= set(words) and set(pools['basic']) <= set(words), 'count/retention mismatch')
        require(all(literal(w) and (len(w) <= maximum or name == 'basic' and w in LEGACY) for w in words) and min(map(len, words)) == 2, 'literal/length mismatch')
        require(set(''.join(words)) == set(CHARACTERS[name]), 'typing alphabet mismatch')
        require(sum('-' in w for w in words) == hyphens and sum(' ' in w for w in words) == phrases, 'category mismatch')
        require(doc['pools'][name]['wordsSHA256'] == sha(('\n'.join(words) + '\n').encode()), 'word pin mismatch')
        require(doc['pools'][name]['observedOptions'] == sum(provenance[w][3] != 'NA' for w in words), 'observation mismatch')


class ContractTests(unittest.TestCase):
    def test_literal_requires_unchanged_cyrillic_and_separators(self):
        for w in ['қап-қара', 'аяқ киім', 'кітап', 'шөп']:
            self.assertTrue(literal(w))
        for w in ['кітап.', 'Қазақ', 'аяқ  киім', 'кітап ', 'а', 'ԛаб', 'кітап-']:
            self.assertFalse(literal(w))

    def test_source_filter_keeps_headwords_without_generated_multiword_variants(self):
        forms = {}
        collect({'lang_code': 'kk', 'pos': 'noun', 'word': 'аяқ киім', 'senses': [{}], 'forms': [{'form': 'аяқ киімі'}, {'form': 'кітап', 'tags': ['romanization']}]}, forms)
        self.assertEqual(forms, {'аяқ киім': ('dictionary', 'аяқ киім')})
        collect({'lang_code': 'kk', 'pos': 'noun', 'word': 'есік', 'senses': [{'tags': ['misspelling']}]}, forms)
        self.assertNotIn('есік', forms)

    def test_whole_option_observation_rejects_fragments_and_space_substitution(self):
        c = {'аяқ киім', 'қап-қара', 'кітап'}
        self.assertEqual(matches('АЯҚ киім. Қап-қара! кітап кітап', c), c)
        for text in ['аяқ  киім', 'аяқ, киім', 'аяқ\tкиім', 'кітап2', 'кітап_а', 'кітап\u0301', "кітап'а", 'кітап-үй', 'аяқ киімдер']:
            self.assertFalse(matches(text, c), text)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--dictionary', type=Path); p.add_argument('--sentences', type=Path)
    p.add_argument('--output', type=Path); p.add_argument('--check', action='store_true')
    p.add_argument('--check-bundled', action='store_true'); p.add_argument('--self-test', action='store_true')
    a = p.parse_args()
    if a.self_test:
        raise SystemExit(not unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests)).wasSuccessful())
    if a.check_bundled:
        verify_bundled(ROOT); print('Kazakh pinned corpus/provenance check passed'); return
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
    print('Kazakh source reproduction checked' if a.check else 'Kazakh corpus prepared')


if __name__ == '__main__':
    main()
