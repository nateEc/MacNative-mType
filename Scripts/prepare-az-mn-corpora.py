#!/usr/bin/env python3
"""Pinned independent Azerbaijani and Mongolian corpus selection and provenance."""
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
PARTS = set('noun verb adj adv name pron num det conj intj prep postp particle phrase abbrev'.split())
BAD = {'misspelling', 'proscribed', 'nonstandard'}
SPECS = {
    'az': {
        'name': 'Azerbaijani', 'sentenceCode': 'aze',
        'dictionarySHA': '8b17fec6310f7285fcbd8a08aa09f1c65fe3b98778bc1fa129b3de20bb50321e',
        'sentencesSHA': '315a666a6103209c6c435b5352e247db105f0e9a4a84149d88b0cb93a746bc33',
        'extraction': '2026-10-03; enwiktionary dump 2026-09-02; 1a05e46 / e3d6d4e',
        'legacy': 'kitab qələm pəncərə yol işıq körpü səhər kağız bağ bulud sakitlik lampa dağ toxum musiqi masa fikir qeyd iş cəhd dost şəhər dəniz kənd vaxt səs sual cavab ümid gələcək'.split(),
        'pools': {'basic': (199, 3, 6), '1k': (989, 2, 7)},
        'keys': {'basic': 'abcdefghijklmnopqrstuvxyzçöüğışə', '1k': 'abcdefghijklmnopqrstuvxyzçöüğışə\u0307'},
        'limits': {'basic': {'ascii': 73, 'accent': 126}, '1k': {'ascii': 321, 'accent': 666, 'dot': 2}},
    },
    'mn': {
        'name': 'Mongolian', 'sentenceCode': 'mon',
        'dictionarySHA': '6ccd2cafc023ea5d1bf0310bef9e8abf059174212dbd66cc91dbed6fca38dac7',
        'sentencesSHA': '5056ffc65661b7633d8a1a38bde442c9a59640366eccb384617c44e600a0bfb6',
        'extraction': '2026-10-25; enwiktionary dump 2026-10-01; f9fe161 / 6f96ddf',
        'legacy': 'ном цонх зам гэрэл гүүр өглөө цаас цэцэрлэг үүл тайван гэр уул үр хөгжим ширээ санаа тэмдэглэл ажил оролдлого найз хот гол салхи цаг дуу асуулт хариулт найдвар ирээдүй алхам'.split(),
        'pools': {'basic': (1085, 2, 15), '10k': (9219, 1, 18)},
        'keys': {'basic': 'абвгдежзийклмнопрстуфхцчшыьэюяёүө', '10k': 'ЁАБВГДЕЖЗИЛМНОПРСТУХЦЧШЭЮЯабвгдежзийклмнопрстуфхцчшъыьэюяёҮүӨө'},
        'limits': {'basic': {'lower': 1085}, '10k': {'lower': 8322, 'upper': 897}},
    },
}
PUBLISHED = {'Compatibility/azerbaijani-corpus.json': 'b719ec46e8f3e326d79a44778f36864fc931d896b155acff5db27f8ceedc8d0e', 'Compatibility/mongolian-corpus.json': '716f1ef66326c9d0b6b815389c419b67db1d4d383b93bdb0c61267a9b8406b50', 'Resources/AzerbaijaniCorpusNotices.txt': '1b6a5e479487fafbe95de3fcd6c765306b2fe668a314d954ffee1687d1ac6f8f', 'Resources/AzerbaijaniCorpusSources.txt': '9bd2ac4fcf0737c6ba8a546955c164b5540abd1cac3c97c709f3c2d832dea96e', 'Resources/MongolianCorpusNotices.txt': '9eb03d75e031ba0769b62be56dd95881756da3e255b79f2ac3a667dcd39694c5', 'Resources/MongolianCorpusSources.txt': '398804d24fe18f769b81f06f8c7d881e2ea6424460a34106f6c0da18994eb0ca', 'Sources/Typebar/AzerbaijaniCorpus.generated.swift': '039042c905bc1b796ebb18a3bef4777989d5f7a836e1661a64ecf6c8d9e38c36', 'Sources/Typebar/MongolianCorpus.generated.swift': '13f6995d5f32e060ee58e8c2f5fd66b91fc88ff8c2998290ef2f2da94a999ac9'}


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def paths(code):
    name = SPECS[code]['name']
    return ('Sources/Typebar/' + name + 'Corpus.generated.swift',
            'Resources/' + name + 'CorpusSources.txt',
            'Resources/' + name + 'CorpusNotices.txt',
            'Compatibility/' + name.lower() + '-corpus.json')


def literal(word, code):
    keys = set(SPECS[code]['keys'][next(reversed(SPECS[code]['pools']))])
    if not (type(word) is str and word and len(word) <= 18
            and word == unicodedata.normalize('NFC', word) and set(word) <= keys):
        return False
    if code == 'mn':
        return word.isalpha()
    if '\u0307' in word:
        return word.startswith('i\u0307') and word.count('\u0307') == 1 and word[2:].isalpha() and word == word.lower()
    return word.isalpha() and word == word.lower()


def category(word, code):
    if code == 'mn':
        return 'upper' if any(c.isupper() for c in word) else 'lower'
    return 'dot' if '\u0307' in word else 'ascii' if word.isascii() else 'accent'


def collect(entry, code, forms, witnesses):
    require(type(entry) is dict, 'invalid entry')
    if entry.get('lang_code') != code or entry.get('pos') not in PARTS:
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
        if word.isalpha() and word == unicodedata.normalize('NFC', word):
            witnesses.setdefault(word.lower(), title)
        if literal(word, code):
            forms.setdefault(word, ('dictionary', title, word, 'none', title))
        if code == 'mn' and word.startswith('ё') and word.isalpha():
            adapted = 'Ё' + word[1:]
            if literal(adapted, code):
                forms.setdefault(adapted, ('dictionary-initial-uppercase', title, word, 'Unicode-initial-uppercase-ё', title))
        if code == 'az' and word.startswith('İ') and word[1:].islower() and word.isalpha():
            adapted = word.lower()
            if literal(adapted, code):
                forms.setdefault(adapted, ('dictionary-lowercase', title, word, 'Unicode-default-lowercase-initial-İ', title))


def tokens(text):
    text = unicodedata.normalize('NFC', text)
    start = None
    for index, c in enumerate(text):
        inside = c.isalnum() or c in "_-'’" or unicodedata.category(c).startswith('M')
        if inside and start is None:
            start = index
        elif not inside and start is not None:
            yield text[start:index]; start = None
    if start is not None:
        yield text[start:]


def read_sources(code, dictionary, sentences):
    spec = SPECS[code]
    require(sha(dictionary.read_bytes()) == spec['dictionarySHA'], 'dictionary pin mismatch: ' + code)
    forms, witnesses = {}, {}
    for line in dictionary.open(encoding='utf-8'):
        collect(json.loads(line), code, forms, witnesses)
    for word in spec['legacy']:
        forms.setdefault(word, ('typebar-legacy', 'Typebar authored starter vocabulary', word, 'none', 'NA'))
    require(sha(sentences.read_bytes()) == spec['sentencesSHA'], 'sentence pin mismatch: ' + code)
    rows, authors, identifiers = [], set(), set()
    for line in bz2.open(sentences, 'rt', encoding='utf-8'):
        fields = line.rstrip('\n').split('\t')
        require(len(fields) == 6 and fields[0].isdigit() and fields[1] == spec['sentenceCode'], 'invalid sentence')
        identifier, _, text, author, _, _ = fields
        require(identifier not in identifiers, 'duplicate sentence')
        identifiers.add(identifier)
        author = author if author not in {'', '\\N'} else '(unowned)'
        authors.add(author); rows.append((identifier, text, author))
        if code == 'mn':
            for word in tokens(text):
                if literal(word, code) and any(c.isupper() for c in word) and word.lower() in witnesses:
                    forms.setdefault(word, ('tatoeba-literal', 'Tatoeba sentence ' + identifier, word, 'none', witnesses[word.lower()]))
    folded = {}
    for word, source in forms.items():
        if source[0] != 'tatoeba-literal':
            folded.setdefault(word.lower(), []).append(word)
    counts, first = Counter(), {}
    for identifier, text, author in rows:
        matched = set()
        for token in tokens(text):
            matched.update(folded.get(token.lower(), []))
            if token in forms and forms[token][0] == 'tatoeba-literal':
                matched.add(token)
        for word in matched:
            counts[word] += 1
            first.setdefault(word, (identifier, author))
    return forms, counts, first, sorted(authors), len(identifiers)


def select(code, forms, counts):
    spec = SPECS[code]
    def rank(word):
        kind, title, raw, _, _ = forms[word]
        return (word not in counts, -counts.get(word, 0), raw != title, word)
    pools = {}
    for name, (count, minimum, maximum) in spec['pools'].items():
        keys, limits = set(spec['keys'][name]), spec['limits'][name]
        eligible = {w for w in forms if literal(w, code) and set(w) <= keys
                    and (minimum <= len(w) <= maximum or code == 'az' and w in spec['legacy'])}
        chosen = set(spec['legacy']) | set(pools.get('basic', []))
        require(chosen <= eligible, 'missing legacy/base vocabulary')
        used = Counter(category(w, code) for w in chosen)
        def add_best(options, key=rank):
            word = min((w for w in options if w not in chosen and used[category(w, code)] < limits.get(category(w, code), 0) and (forms[w][0] != 'dictionary-initial-uppercase' or not any(forms[x][0] == 'dictionary-initial-uppercase' for x in chosen))), key=key, default=None)
            require(word is not None, 'insufficient typing coverage: ' + code + '/' + name)
            chosen.add(word); used[category(word, code)] += 1
        for length in [minimum, maximum]:
            if not any(len(w) == length for w in chosen):
                add_best(w for w in eligible if len(w) == length and category(w, code) != 'dot')
        missing = keys - set(''.join(chosen))
        while missing:
            add_best((w for w in eligible if set(w) & missing), lambda w: (-len(set(w) & missing), rank(w)))
            missing = keys - set(''.join(chosen))
        for key, limit in limits.items():
            require(used[key] <= limit, 'seed exceeds quota')
            options = sorted((w for w in eligible if w not in chosen and category(w, code) == key), key=rank)
            for word in options:
                if used[key] == limit:
                    break
                if key == 'dot' and any(forms[w][1] == forms[word][1] for w in chosen if category(w, code) == 'dot'):
                    continue
                if forms[word][0] == 'dictionary-initial-uppercase' and any(forms[w][0] == 'dictionary-initial-uppercase' for w in chosen):
                    continue
                chosen.add(word); used[key] += 1
            require(used[key] == limit, 'insufficient category: ' + code + '/' + key)
        require(len(chosen) == count and dict(Counter(category(w, code) for w in chosen)) == limits, 'quota mismatch')
        require(set(''.join(chosen)) == keys, 'typing key mismatch')
        pools[name] = sorted(chosen, key=rank)
    return pools


def artifacts(code, dictionary, sentences):
    spec = SPECS[code]
    forms, counts, first, authors, sentence_count = read_sources(code, dictionary, sentences)
    pools = select(code, forms, counts)
    swift, source_map, notice_path, manifest_path = paths(code)
    revision = 'kaikki-' + code + '-tatoeba-20261102-literal-v1'
    native = '// Independent corpus selection; see bundled source mappings and separate licenses.\nenum ' + spec['name'] + 'Corpus {\n  static let revision = ' + json.dumps(revision) + '\n'
    for name, words in pools.items():
        native += '  static let ' + ('basic' if name == 'basic' else 'words' + name) + ': [String] = """\n' + '\n'.join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    native += '}\n'
    union = sorted(set().union(*map(set, pools.values())))
    rows = '# word\tsourceKind\tsourceTitle\tsourceForm\tadaptation\tlexicalWitnessTitle\tobservationMode\twholeOptionSentenceCount\tfirstSentenceID\tfirstSentenceAuthor (NA means unobserved)\n'
    for word in union:
        identifier, author = first.get(word, ('NA', 'NA'))
        mode = 'exact-case' if forms[word][0] == 'tatoeba-literal' else 'lowercase-lookup'
        rows += '\t'.join([word, *forms[word], mode, str(counts[word]) if word in counts else 'NA', identifier, author]) + '\n'
    unattested = sorted(w for w in spec['legacy'] if forms[w][0] == 'typebar-legacy')
    exceptions = {n: sorted(w for w in words if not spec['pools'][n][1] <= len(w) <= spec['pools'][n][2]) for n, words in pools.items()}
    dictionary_url = 'https://kaikki.org/dictionary/' + spec['name'] + '/kaikki.org-dictionary-' + spec['name'] + '.jsonl'
    sentence_url = 'https://downloads.tatoeba.org/exports/per_language/' + spec['sentenceCode'] + '/' + spec['sentenceCode'] + '_sentences_detailed.tsv.bz2'
    adaptations = [w + ' <- ' + forms[w][2] + ' (entry ' + forms[w][1] + ')' for w in union if forms[w][0] in {'dictionary-lowercase', 'dictionary-initial-uppercase'}]
    notice = f'''Typebar independent {spec['name']} corpus
Revision: {revision}
English Wiktionary contributors via Kaikki.org / Wiktextract.
Dictionary: {dictionary_url}
Snapshot SHA-256: {spec['dictionarySHA']}
Index reports: {spec['extraction']}.
Dictionary selection/adaptations: CC BY-SA 4.0 International.
https://creativecommons.org/licenses/by-sa/4.0/
Dictionary contributor pages: https://en.wiktionary.org/wiki/ + encoded sourceTitle.
Selected lexical titles/forms use lang_code={code}; nonstandard/proscribed/
misspelling-only senses, romanization/template/error forms are excluded.
Ordinary spellings remain unchanged. Two Azerbaijani combining-dot options
use explicit Unicode default lowercase of independently sourced initial İ.
This is a compatibility adaptation, not a claim of normative Azerbaijani casing.
The raw source form, entry and exact rule accompany each adaptation below.
One Mongolian option capitalizes only an independently sourced initial ё to
cover uppercase Ё, absent from the literal candidate snapshots. This is marked
dictionary-initial-uppercase, not claimed as original source capitalization.
No arbitrary numbered padding, spelling synthesis or original Monkeytype words.
All 30 old Typebar starters remain in both pools; basic is retained in larger.
Selected lexical attestation missing for: {', '.join(unattested) or '(none)'}.
This does not claim absence of other categories in the raw dictionary.
Retained old-word length exceptions: {json.dumps(exceptions, ensure_ascii=False, sort_keys=True)}.
No other new word may exceed the declared source length bounds.
Code points/UTF-16 and Swift graphemes are distinct for combining-dot options.
Per-option source mapping: {source_map.split('/')[-1]}.
Adaptations for this language: {'; '.join(adaptations) or '(none)'}.

Tatoeba {spec['name']} contributors: CC BY 2.0 France.
Sentences: {sentence_url}
Snapshot SHA-256: {spec['sentencesSHA']}
Sentence rows: {sentence_count}; contributor identifiers: {len(authors)}.
https://creativecommons.org/licenses/by/2.0/fr/
https://tatoeba.org/en/downloads
Mongolian additional capitalized options are unchanged literal sentence tokens,
with a lowercase dictionary lexical witness. They are marked tatoeba-literal,
not dictionary headwords or artificial recasing; source sentence and lexical
entry are separate fields. Their observation mode is exact-case. Other word
observations use NFC lowercase lookup without altering delivered spelling.
Only selected short tokens and provenance are bundled, not the full archive,
translations or audio. Whole Unicode token boundaries keep hyphens, apostrophes,
underscores, digits and combining marks inside tokens; no partial-word matches.
One observation per option per sentence; missing observations stay NA, never
zero or component-frequency estimates. Unobserved options prefer headwords.
Observation counts are not representative frequencies or runtime Zipf values.
Vocabulary quality/distribution and device input are not certified equivalent
to Monkeytype. All processed contributor identifiers are credited below.

''' + '\n'.join(a if a == '(unowned)' else a + ' https://tatoeba.org/en/user/profile/' + quote(a, safe='') for a in authors) + '\n'
    output = {swift: native.encode(), source_map: rows.encode(), notice_path: notice.encode()}
    doc = {'schemaVersion': 1, 'revision': revision, 'dictionary': dictionary_url, 'dictionarySHA256': spec['dictionarySHA'], 'sentences': sentence_url, 'sentencesSHA256': spec['sentencesSHA'], 'sentenceRows': sentence_count, 'contributorIdentifiers': len(authors), 'legacyUnattested': unattested, 'artifacts': {n: sha(b) for n, b in output.items()}, 'pools': {}}
    for name, words in pools.items():
        doc['pools'][name] = {'count': len(words), 'minimumUTF16Length': min(map(len, words)), 'maximumUTF16Length': max(map(len, words)), 'characters': ''.join(sorted(set(''.join(words)))), 'categories': dict(Counter(category(w, code) for w in words)), 'legacyLengthExceptions': exceptions[name], 'observedOptions': sum(w in counts for w in words), 'sourceKinds': dict(Counter(forms[w][0] for w in words)), 'wordsSHA256': sha(('\n'.join(words) + '\n').encode())}
    output[manifest_path] = (json.dumps(doc, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()
    return output


def verify_bundled(root):
    require(len(PUBLISHED) == 8, 'eight immutable pins required')
    for name, digest in PUBLISHED.items():
        require(sha((root / name).read_bytes()) == digest, 'published pin mismatch: ' + name)
    for code, spec in SPECS.items():
        swift, rows_path, _, manifest = paths(code)
        pools = {('basic' if n == 'basic' else n[5:]): s.splitlines() for n, s in re.findall(r'static let (basic|words1k|words10k): \[String\] = """\n(.*?)\n"""', (root / swift).read_text(), re.S)}
        require(list(pools) == list(spec['pools']), 'missing native pools')
        rows = [s.split('\t') for s in (root / rows_path).read_text().splitlines() if not s.startswith('#')]
        provenance = {r[0]: r for r in rows}
        require(len(rows) == len(provenance) and set(provenance) == set().union(*map(set, pools.values())), 'missing provenance')
        for row in rows:
            require(len(row) == 10 and row[1] in {'dictionary', 'dictionary-lowercase', 'dictionary-initial-uppercase', 'tatoeba-literal', 'typebar-legacy'}, 'invalid source fields')
            require(row[2] and row[3] and (row[7:] == ['NA', 'NA', 'NA'] or row[7].isdigit() and int(row[7]) > 0 and row[8].isdigit() and row[9]), 'invalid observation')
            if row[1] == 'dictionary-lowercase':
                require(code == 'az' and row[0] == row[3].lower() and row[3].startswith('İ') and row[4] == 'Unicode-default-lowercase-initial-İ', 'invalid adaptation')
            elif row[1] == 'dictionary-initial-uppercase':
                require(code == 'mn' and row[3].startswith('ё') and row[0] == 'Ё' + row[3][1:] and row[4] == 'Unicode-initial-uppercase-ё', 'invalid initial case adaptation')
            else:
                require(row[0] == row[3] and row[4] == 'none', 'unexpected spelling change')
            require(row[6] == ('exact-case' if row[1] == 'tatoeba-literal' else 'lowercase-lookup'), 'wrong observation mode')
            if row[1] == 'tatoeba-literal':
                require(code == 'mn' and row[5] != 'NA' and row[7] != 'NA' and row[2] == 'Tatoeba sentence ' + row[8], 'missing literal witness')
        doc = json.loads((root / manifest).read_text())
        for name, words in pools.items():
            count, minimum, maximum = spec['pools'][name]
            require(len(words) == len(set(words)) == count and set(spec['legacy']) <= set(words) and set(pools['basic']) <= set(words), 'count/retention mismatch')
            require(set(''.join(words)) == set(spec['keys'][name]), 'alphabet mismatch')
            require(all(literal(w, code) and (minimum <= len(w) <= maximum or code == 'az' and w in spec['legacy']) for w in words), 'invalid literal/length')
            require(dict(Counter(category(w, code) for w in words)) == spec['limits'][name], 'category mismatch')
            require(doc['pools'][name]['wordsSHA256'] == sha(('\n'.join(words) + '\n').encode()), 'word pin mismatch')
            require(doc['pools'][name]['observedOptions'] == sum(provenance[w][7] != 'NA' for w in words), 'observation count mismatch')
        if code == 'mn':
            require(sum(r[1] == 'dictionary-initial-uppercase' for r in rows) == 1, 'one uppercase Ё adaptation required')
        if code == 'az':
            dotted = [w for w in provenance if '\u0307' in w]
            require(len(dotted) == 2 and len({provenance[w][2] for w in dotted}) == 2, 'distinct dot sources required')


class ContractTests(unittest.TestCase):
    def test_literal_and_combining_dot_are_not_generic_punctuation(self):
        self.assertTrue(literal('i\u0307lham', 'az'))
        self.assertEqual(category('i\u0307lham', 'az'), 'dot')
        self.assertFalse(literal('i\u0307\u0307lham', 'az'))
        self.assertFalse(literal('kitab.', 'az'))
        self.assertFalse(literal('ӿабв', 'mn'))
        self.assertTrue(literal('Ёс', 'mn'))

    def test_dictionary_adaptation_keeps_raw_source_and_witness(self):
        f, w = {}, {}
        collect({'lang_code': 'az', 'pos': 'name', 'word': 'İlham', 'senses': [{}]}, 'az', f, w)
        self.assertEqual(f['i\u0307lham'], ('dictionary-lowercase', 'İlham', 'İlham', 'Unicode-default-lowercase-initial-İ', 'İlham'))
        collect({'lang_code': 'az', 'pos': 'noun', 'word': 'kitab', 'senses': [{'tags': ['nonstandard']}]}, 'az', f, w)
        self.assertNotIn('kitab', f)
        collect({'lang_code': 'mn', 'pos': 'noun', 'word': 'ёс', 'senses': [{}]}, 'mn', f, w)
        self.assertEqual(f['Ёс'], ('dictionary-initial-uppercase', 'ёс', 'ёс', 'Unicode-initial-uppercase-ё', 'ёс'))

    def test_whole_token_boundaries_keep_marks_hyphens_and_apostrophes(self):
        self.assertEqual(list(tokens('Би, ном. i\u0307lham')), ['Би', 'ном', 'i\u0307lham'])
        for text in ['ном-ном', "ном'ном", 'ном_2', 'ном\u0301']:
            self.assertNotIn('ном', list(tokens(text)))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for code in SPECS:
        p.add_argument('--' + code + '-dictionary', type=Path)
        p.add_argument('--' + code + '-sentences', type=Path)
    p.add_argument('--output', type=Path); p.add_argument('--check', action='store_true')
    p.add_argument('--self-test', action='store_true'); p.add_argument('--check-bundled', action='store_true')
    args = p.parse_args()
    if args.self_test:
        raise SystemExit(not unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests)).wasSuccessful())
    if args.check_bundled:
        verify_bundled(ROOT); print('Azerbaijani/Mongolian pinned corpus/provenance check passed'); return
    require(args.output is not None, 'output required')
    output = {}
    for code in SPECS:
        dictionary, sentences = getattr(args, code + '_dictionary'), getattr(args, code + '_sentences')
        require(dictionary and sentences, 'all four source snapshots required')
        output.update(artifacts(code, dictionary, sentences))
    if PUBLISHED:
        require({n: sha(b) for n, b in output.items()} == PUBLISHED, 'reproduction pins mismatch')
    for name, data in output.items():
        path = args.output / name
        if args.check:
            require(path.read_bytes() == data, 'source reproduction mismatch: ' + name)
        else:
            require(not path.exists(), 'refusing to overwrite: ' + name)
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    print('Azerbaijani/Mongolian source reproduction checked' if args.check else 'Azerbaijani/Mongolian corpora prepared')


if __name__ == '__main__':
    main()
