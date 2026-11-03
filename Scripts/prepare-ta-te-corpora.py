#!/usr/bin/env python3
"""Reproduce independent Tamil/Telugu literal entries and source-preserved phrases.

Original Monkeytype data is not an input. Configuration contains aggregate
character/shape facts and preexisting Typebar vocabulary only.
Full reconstruction requires msgpack 1.1.2 and Node v24.19.0 / Unicode 17.0.
"""
from pathlib import Path
import argparse, json, re, hashlib, bz2, unicodedata, subprocess, collections, zipfile, gzip, unittest
from urllib.parse import quote
ROOT = Path(__file__).resolve().parents[1]

def require(value, message):
    if not value:
        raise ValueError(message)

def sha(data):
    return hashlib.sha256(data).hexdigest()
spec = {'ta': {'name': 'Tamil', 'prefix': 'tamil', 'legacy': ['\u0baa\u0bc1\u0ba4\u0bcd\u0ba4\u0b95\u0bae\u0bcd', '\u0baa\u0bc7\u0ba9\u0bbe', '\u0b9a\u0bbe\u0bb3\u0bb0\u0bae\u0bcd', '\u0baa\u0bbe\u0ba4\u0bc8', '\u0b92\u0bb3\u0bbf', '\u0baa\u0bbe\u0bb2\u0bae\u0bcd', '\u0b95\u0bbe\u0bb2\u0bc8', '\u0b95\u0bbe\u0b95\u0bbf\u0ba4\u0bae\u0bcd', '\u0ba4\u0bcb\u0b9f\u0bcd\u0b9f\u0bae\u0bcd', '\u0bae\u0bc7\u0b95\u0bae\u0bcd', '\u0b85\u0bae\u0bc8\u0ba4\u0bbf', '\u0bb5\u0bbf\u0bb3\u0b95\u0bcd\u0b95\u0bc1', '\u0bae\u0bb2\u0bc8', '\u0bb5\u0bbf\u0ba4\u0bc8', '\u0b87\u0b9a\u0bc8', '\u0bae\u0bc7\u0b9a\u0bc8', '\u0b9a\u0bbf\u0ba8\u0bcd\u0ba4\u0ba9\u0bc8', '\u0b95\u0bc1\u0bb1\u0bbf\u0baa\u0bcd\u0baa\u0bc1', '\u0baf\u0bcb\u0b9a\u0ba9\u0bc8', '\u0bae\u0bc1\u0baf\u0bb1\u0bcd\u0b9a\u0bbf', '\u0ba4\u0bc2\u0bb0\u0bae\u0bcd', '\u0b85\u0b9f\u0bbf', '\u0baa\u0bca\u0bb1\u0bc1\u0bae\u0bc8', '\u0b9a\u0bae\u0ba8\u0bbf\u0bb2\u0bc8'], 'oldSeeds': ['\u0b85\u0b95\u0bbe', '\u0ba8\u0bc0\u0bb3\u0bae\u0bbe\u0ba9\u0baa\u0baf\u0bbf\u0bb1\u0bcd\u0b9a\u0bbf', '\u0b87\u0b9a\u0bc8 \u0ba8\u0b9f\u0bc8'], 'pools': {'basic': {'count': 366, 'minimum': 2, 'maximum': 17, 'minG': 1, 'maxG': 10, 'keys': '\u0b85\u0b86\u0b87\u0b89\u0b8a\u0b8e\u0b8f\u0b92\u0b93\u0b95\u0b99\u0b9a\u0b9c\u0b9f\u0ba3\u0ba4\u0ba8\u0ba9\u0baa\u0bae\u0baf\u0bb0\u0bb1\u0bb2\u0bb3\u0bb4\u0bb5\u0bb7\u0bb8\u0bbe\u0bbf\u0bc0\u0bc1\u0bc2\u0bc6\u0bc7\u0bc8\u0bca\u0bcb\u0bcd', 'quotas': {'mark spaces=0': 363, 'plain spaces=0': 3}}, '1k': {'count': 951, 'minimum': 1, 'maximum': 19, 'minG': 1, 'maxG': 11, 'keys': '\u0b83\u0b85\u0b86\u0b87\u0b88\u0b89\u0b8a\u0b8e\u0b8f\u0b90\u0b92\u0b93\u0b95\u0b99\u0b9a\u0b9c\u0b9e\u0b9f\u0ba3\u0ba4\u0ba8\u0ba9\u0baa\u0bae\u0baf\u0bb0\u0bb1\u0bb2\u0bb3\u0bb4\u0bb5\u0bb7\u0bb8\u0bbe\u0bbf\u0bc0\u0bc1\u0bc2\u0bc6\u0bc7\u0bc8\u0bca\u0bcb\u0bcc\u0bcd', 'quotas': {'mark spaces=0': 942, 'plain spaces=0': 9}}, 'old': {'count': 460, 'minimum': 3, 'maximum': 13, 'minG': 2, 'maxG': 8, 'keys': ' \u0b85\u0b86\u0b87\u0b89\u0b8a\u0b8e\u0b8f\u0b90\u0b92\u0b93\u0b94\u0b95\u0b99\u0b9a\u0b9c\u0b9e\u0b9f\u0ba3\u0ba4\u0ba8\u0ba9\u0baa\u0bae\u0baf\u0bb0\u0bb1\u0bb2\u0bb3\u0bb4\u0bb5\u0bb7\u0bb8\u0bbe\u0bbf\u0bc0\u0bc1\u0bc2\u0bc6\u0bc7\u0bc8\u0bca\u0bcb\u0bcd', 'quotas': {'mark spaces=0': 458, 'plain spaces=0': 1, 'mark spaces=1': 1}}}}, 'te': {'name': 'Telugu', 'prefix': 'telugu', 'legacy': ['\u0c2a\u0c41\u0c38\u0c4d\u0c24\u0c15\u0c02', '\u0c15\u0c32\u0c02', '\u0c15\u0c3f\u0c1f\u0c3f\u0c15\u0c40', '\u0c26\u0c3e\u0c30\u0c3f', '\u0c35\u0c46\u0c32\u0c41\u0c17\u0c41', '\u0c35\u0c02\u0c24\u0c46\u0c28', '\u0c09\u0c26\u0c2f\u0c02', '\u0c15\u0c3e\u0c17\u0c3f\u0c24\u0c02', '\u0c24\u0c4b\u0c1f', '\u0c2e\u0c47\u0c18\u0c02', '\u0c36\u0c3e\u0c02\u0c24\u0c3f', '\u0c26\u0c40\u0c2a\u0c02', '\u0c15\u0c4a\u0c02\u0c21', '\u0c35\u0c3f\u0c24\u0c4d\u0c24\u0c28\u0c02', '\u0c38\u0c02\u0c17\u0c40\u0c24\u0c02', '\u0c2c\u0c32\u0c4d\u0c32', '\u0c06\u0c32\u0c4b\u0c1a\u0c28', '\u0c17\u0c2e\u0c28\u0c3f\u0c15', '\u0c0a\u0c39', '\u0c2a\u0c4d\u0c30\u0c2f\u0c24\u0c4d\u0c28\u0c02', '\u0c26\u0c42\u0c30\u0c02', '\u0c05\u0c21\u0c41\u0c17\u0c41', '\u0c38\u0c39\u0c28\u0c02', '\u0c38\u0c2e\u0c24\u0c41\u0c32\u0c4d\u0c2f\u0c02'], 'oldSeeds': [], 'pools': {'basic': {'count': 201, 'minimum': 1, 'maximum': 15, 'minG': 1, 'maxG': 8, 'keys': ' \u0c02\u0c05\u0c06\u0c07\u0c08\u0c09\u0c0e\u0c0f\u0c12\u0c15\u0c16\u0c17\u0c18\u0c1a\u0c1c\u0c1f\u0c20\u0c21\u0c23\u0c24\u0c25\u0c26\u0c27\u0c28\u0c2a\u0c2b\u0c2c\u0c2d\u0c2e\u0c2f\u0c30\u0c32\u0c33\u0c35\u0c36\u0c37\u0c38\u0c39\u0c3e\u0c3f\u0c40\u0c41\u0c42\u0c46\u0c47\u0c48\u0c4a\u0c4b\u0c4c\u0c4d', 'quotas': {'mark spaces=0': 192, 'plain spaces=0': 8, 'mark spaces=1': 1}}, '1k': {'count': 901, 'minimum': 1, 'maximum': 18, 'minG': 1, 'maxG': 9, 'keys': ' \u0c02\u0c05\u0c06\u0c07\u0c08\u0c09\u0c0a\u0c0e\u0c0f\u0c10\u0c12\u0c13\u0c15\u0c16\u0c17\u0c18\u0c1a\u0c1c\u0c1f\u0c20\u0c21\u0c23\u0c24\u0c25\u0c26\u0c27\u0c28\u0c2a\u0c2b\u0c2c\u0c2d\u0c2e\u0c2f\u0c30\u0c32\u0c33\u0c35\u0c36\u0c37\u0c38\u0c39\u0c3e\u0c3f\u0c40\u0c41\u0c42\u0c43\u0c46\u0c47\u0c48\u0c4a\u0c4b\u0c4c\u0c4d', 'quotas': {'mark spaces=0': 874, 'plain spaces=0': 22, 'mark spaces=1': 4, 'mark spaces=2': 1}}}}}
PINS = {'Tamil.jsonl': '14277cb7a242b2609905ae285920e6f85aa97668bb1df9f37df5bcfac64ff24a', 'Telugu.jsonl': 'f6a7c32ea73d125d7a2a93ae5a38c44ffa27a8a2c35f0b4073c59a6d69cb7194', 'tam_sentences_detailed.tsv.bz2': '642d33db96131bf4aa7a5fa72bc3a1acc63d1d2c57d1a0a373a4cb667ecb8144', 'tel_sentences_detailed.tsv.bz2': '833268b5ac5b18f69903594a8e8c5ab7cbfdaa9f1d6f69e6dc927282cdc9da9c'}
WHEEL_SHA = '4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473'
PUBLISHED = {'Compatibility/tamil-corpus.json': '9ef25c7d7e5e368b7e57999a948f559ac6639b7347381fac17a928dd31cb9945', 'Compatibility/telugu-corpus.json': '5f3dc24a8b8e4e20640c88e626723c0f1562c36793544f9256041651f7522315', 'Resources/TamilCorpusNotices.txt': '2cee3272afab96dc24b84f861501f9485ed57f5358697fec5fe8ee59d6475b7b', 'Resources/TamilCorpusSources.txt': 'def008a8f00bc93e8bc2bf30849e0278d210683d89726c79edfc0ac18aa1e23d', 'Resources/TeluguCorpusNotices.txt': '73cd1eda69edd8c6ed98f926329e0aecff326ea573c0ede8808d24d4c5c2736c', 'Resources/TeluguCorpusSources.txt': '1d9e46ff813a4f02a0a7cf7c0148b6e96d8fc0cfd8e5dab6bb91fdd55ac5b6cf', 'Sources/Typebar/TamilCorpus.generated.swift': 'fc20800bc0c58e36b0acfff3d124909287b7310bfb884f8c4f03c2893db0c4f7', 'Sources/Typebar/TeluguCorpus.generated.swift': 'c5348f5f3be11a7db9515df781f67221203d78e122d34da121229993b861851c'}

def valid_spelling(w, keys, maximum):
    return bool(w) and w==w.strip() and len(w) <= maximum and (set(w) <= keys) and (w == unicodedata.normalize('NFC', w)) and ('  ' not in w) and bool(w.strip()) and w.strip()[0].isalpha() and all((c == ' ' or c.isalpha() or unicodedata.category(c).startswith('M') for c in w))

def category(w):
    return ('mark' if any((unicodedata.category(c).startswith('M') for c in w)) else 'plain') + ' spaces=' + str(w.count(' '))

def token_spans(text):
    start = None
    for (i, c) in enumerate(text):
        inside = c.isalnum() or c in "_-'\u2019" or unicodedata.category(c)[0] in {'M', 'C'}
        if inside and start is None:
            start = i
        elif not inside and start is not None:
            yield (start, i)
            start = None
    if start is not None:
        yield (start, len(text))

def prepare(code, dictionary, sentences_path, wheel, node):
    name = spec[code]['name']
    require(sha(dictionary.read_bytes()) == PINS[name + '.jsonl'], 'dictionary pin mismatch')
    require(sha(sentences_path.read_bytes()) == PINS[('tam' if code == 'ta' else 'tel') + '_sentences_detailed.tsv.bz2'], 'sentence pin mismatch')
    require(sha(wheel.read_bytes()) == WHEEL_SHA, 'wheel pin mismatch')
    S = spec[code]
    keys = set(''.join((x['keys'] for x in S['pools'].values())) + ''.join(S['legacy']))
    maxlen = max((x['maximum'] for x in S['pools'].values()))
    forms = {}

    def allowed(w):
        return valid_spelling(w, keys, maxlen)
    for line in dictionary.open():
        e = json.loads(line)
        pos = e.get('pos')
        senses = e.get('senses', [])
        if e.get('lang_code') != code or pos not in set('noun verb adj adv name pron num det conj intj prep postp particle phrase abbrev counter classifier character symbol'.split()) or (not senses) or all((set(s.get('tags', [])) & {'misspelling', 'proscribed', 'nonstandard'} for s in senses)):
            continue
        title = e['word']
        for row in [{'form': title}] + e.get('forms', []):
            w = row.get('form', '')
            tags = row.get('tags', [])
            if any((t in {'romanization', 'table-tags', 'inflection-template', 'class', 'misspelling', 'proscribed', 'nonstandard'} or t.startswith('error-') for t in tags)):
                continue
            if allowed(w) and w == w.strip() and (pos not in {'character', 'symbol'} or len(w) == 1):
                forms.setdefault(w, dict(kind='dictionary-character' if pos in {'character', 'symbol'} else 'dictionary', title=title, form=w, pos=pos))
    counts = collections.Counter()
    first = {}
    authors = set()
    sentences = []
    identifiers = set()
    for line in bz2.open(sentences_path, 'rt'):
        (ident, lang, text, author, _, _) = line.rstrip('\n').split('\t')
        require(ident.isdigit() and lang == ('tam' if code == 'ta' else 'tel'), 'invalid sentence identity')
        author = author if author not in {'', '\\N'} else '(unowned)'
        require(ident not in identifiers,'duplicate sentence identifier')
        identifiers.add(ident)
        authors.add(author)
        sentences.append((ident, text, author))
        observed = set()
        ss = list(token_spans(text))
        for (a, b) in ss:
            w = text[a:b]
            if w == unicodedata.normalize('NFC', w):
                observed.add(w)
        if code == 'te':
            for (i, (a, b)) in enumerate(ss):
                if a and text[a - 1] == ' ':
                    observed.add(text[a - 1:b])
                if b < len(text) and text[b] == ' ':
                    observed.add(text[a:b + 1])
                for n in [2, 3, 4]:
                    if i + n <= len(ss):
                        observed.add(text[a:ss[i + n - 1][1]])
            for w in observed:
                if allowed(w) and ' ' in w:
                    forms.setdefault(w, dict(kind='sentence-fragment', title='https://tatoeba.org/en/sentences/show/' + ident, form=w, pos='NA'))
        for w in observed:
            if w in forms:
                counts[w] += 1
                first.setdefault(w, (ident, author))
    for w in S['legacy']+S['oldSeeds']:
        forms.setdefault(w, dict(kind='typebar-legacy', title='Typebar authored starter vocabulary', form=w, pos='NA'))
    bands = {}
    license_text = 'No wordfreq dataset is used for Telugu.\n'
    if code == 'ta':
        with zipfile.ZipFile(wheel) as z:
            license_text = z.read('wordfreq-3.1.1.dist-info/METADATA').decode()
            license_text = license_text[license_text.index('## License'):].strip() + '\n'
            member = z.read('wordfreq/data/small_ta.msgpack.gz')
            require(len(member) == 453574 and sha(member) == '68ed68a8bd703e1aafe8c0adc3827dada57eb3226837dabf26716187fb796547', 'Tamil member pin mismatch')
        import msgpack
        require(msgpack.__version__ == '1.1.2', 'requires msgpack 1.1.2')
        bins = msgpack.unpackb(gzip.decompress(member), raw=False)
        require(bins[0] == {'format': 'cB', 'version': 1}, 'invalid frequency format')
        for (i, words) in enumerate(bins[1:]):
            require(type(words) is list and words == sorted(set(words)), 'invalid frequency bin')
            for w in words:
                require(type(w) is str and w not in bands, 'invalid frequency token')
                bands[w] = i
        require(len(bands) == 68526, 'unexpected Tamil token count')
    words = sorted(forms)
    program = "if(process.version!=='v24.19.0'||process.versions.unicode!=='17.0')throw Error('Pinned Node v24.19.0 / Unicode 17.0 required');const fs=require('fs');let w=JSON.parse(fs.readFileSync(0,'utf8')),s=new Intl.Segmenter('" + code + "',{granularity:'grapheme'});process.stdout.write(JSON.stringify(w.map(x=>[...s.segment(x)].length)));"
    p = subprocess.run([str(node), '-e', program], input=json.dumps(words), text=True, capture_output=True)
    require(p.returncode == 0, 'grapheme runtime failure: ' + p.stderr)
    g = dict(zip(words, json.loads(p.stdout)))

    def rank(w):
        return (w not in bands, bands.get(w, 0), w not in counts, -counts.get(w, 0), forms[w]['kind'] == 'dictionary-character', forms[w]['form'] != forms[w]['title'], w)
    pools = {}
    for (pool, s) in S['pools'].items():
        allowedkeys = set(s['keys'] + ''.join(S['legacy']))
        eligible = {w for w in forms if set(w) <= allowedkeys and s['minimum'] <= len(w) <= s['maximum'] and (s['minG'] <= g[w] <= s['maxG']) and (category(w) in s['quotas']) and (pool=='old' or w not in S['oldSeeds'] or forms[w]['kind']!='typebar-legacy')}
        chosen = set(S['legacy']) | (set(S['oldSeeds']) if pool=='old' else set(pools.get('basic', [])))
        require(chosen <= eligible, 'source preparation contract')
        used = collections.Counter((category(w) for w in chosen))

        def add(options):
            w = min((w for w in options if w not in chosen and used[category(w)] < s['quotas'][category(w)]), key=rank, default=None)
            require(w is not None, 'source preparation contract')
            chosen.add(w)
            used[category(w)] += 1
            return w
        for length in [s['minimum'], s['maximum']]:
            if not any((len(w) == length for w in chosen)):
                add((w for w in eligible if len(w) == length))
        if not any((g[w] == s['maxG'] for w in chosen)):
            add((w for w in eligible if g[w] == s['maxG']))
        missing = allowedkeys - set(''.join(chosen))
        while missing:
            options = [w for w in eligible - chosen if used[category(w)] < s['quotas'][category(w)] and set(w) & missing]
            require(options, 'source preparation contract')
            w = min(options, key=lambda w: (-len(set(w) & missing), rank(w)))
            chosen.add(w)
            used[category(w)] += 1
            missing -= set(w)
        for (c, quota) in s['quotas'].items():
            require(used[c] <= quota, 'source preparation contract')
            options = sorted((w for w in eligible - chosen if category(w) == c and (not w.startswith(' ') and (not w.endswith(' ')))), key=rank)
            need = quota - used[c]
            require(len(options) >= need, 'source preparation contract')
            chosen.update(options[:need])
        pools[pool] = sorted(chosen, key=rank)
        require(len(chosen) == s['count'], 'source preparation contract')
        require(dict(collections.Counter((category(w) for w in chosen))) == s['quotas'], 'category mismatch')
        require(set(''.join(chosen)) == allowedkeys, 'key mismatch')
    return (pools, forms, counts, first, sorted(authors), len(sentences), g, bands, license_text)

def artifacts(code, dictionary, sentences, wheel, node):
    (pools, forms, counts, first, authors, sentence_count, graphemes, bands, license_text) = prepare(code, dictionary, sentences, wheel, node)
    name = spec[code]['name']
    revision = 'kaikki-' + code + '-20261103-literal-v1'
    swift_path = 'Sources/Typebar/' + name + 'Corpus.generated.swift'
    rows_path = 'Resources/' + name + 'CorpusSources.txt'
    notice_path = 'Resources/' + name + 'CorpusNotices.txt'
    manifest_path = 'Compatibility/' + name.lower() + '-corpus.json'
    swift = '// Independent literal entries; see bundled provenance and licenses.\nenum ' + name + 'Corpus {\n  static let revision = ' + json.dumps(revision) + '\n'
    for (pool, words) in pools.items():
        swift += '  static let ' + {'basic':'basic','1k':'words1k','old':'wordsOld'}[pool] + ': [String] = [\n' + ''.join('    '+json.dumps(w,ensure_ascii=False)+',\n' for w in words) + '  ]\n'
    swift += '}\n'
    union = sorted(set().union(*map(set, pools.values())))
    rows = '# word\tsourceKind\tsourceTitle\tsourceForm\tpartOfSpeech\tadaptation\twordfreqWholeTokenBand\tobservationMode\twholeTokenSentenceCount\tfirstSentenceID\tfirstSentenceAuthor (NA means unobserved)\n'
    for w in union:
        f = forms[w]
        (ident, author) = first.get(w, ('NA', 'NA'))
        rows += '\t'.join([w, f['kind'], f['title'], f['form'], f['pos'], 'none', str(bands[w]) if w in bands else 'NA', 'literal-whole-token-or-contiguous-fragment', str(counts[w]) if w in counts else 'NA', ident, author]) + '\n'
    unattested = sorted((w for w in spec[code]['legacy']+spec[code]['oldSeeds'] if forms[w]['kind'] == 'typebar-legacy'))
    notice = f"Typebar independent {name} literal entries\nRevision: {revision}\nEnglish Wiktionary contributors via Kaikki.org / Wiktextract.\nDictionary: https://kaikki.org/dictionary/{name}/kaikki.org-dictionary-{name}.jsonl\nSnapshot SHA-256: {sha(dictionary.read_bytes())}\nIndex reports extraction {'2026-10-30' if code=='ta' else '2026-10-25'}; enwiktionary dump 2026-10-01;\nWiktextract {'19f9a30' if code=='ta' else 'f9fe161'} / 6f96ddf.\nDictionary selection: CC BY-SA 4.0 International.\nhttps://creativecommons.org/licenses/by-sa/4.0/\nContributor pages: https://en.wiktionary.org/wiki/ + encoded sourceTitle.\nOnly unchanged NFC titles/forms of lang_code={code} are selected.\nNonstandard/proscribed/misspelling-only senses, romanizations, template/error\nforms are excluded. Dictionary character/symbol entries are single characters\nand explicitly identified as dictionary-character; they are character practice,\nnot claimed to be complete lexical words. Other entries retain their source POS.\nAll 24 original Typebar starters remain in every pool; three explicit original\nTamil-old exercises also remain in the old pool. No old-word length exceptions.\nSelected lexical attestation missing for: {', '.join(unattested) or '(none)'}.\nThis concerns selected lexical categories, not all raw dictionary occurrences.\nNo artificial spelling, case edits, numbered padding, or original Monkeytype\nword values, source code or assets are used. Reference character sets and shape\ncounts alone constrain selection. Runtime Zipf support is unchanged: Tamil basic/1k supported; Tamil old and\nTelugu unknown. Observation bands do not create new runtime support.\nSource units are BMP UTF-16 units, not graphemes. Pinned Node v24.19.0 /\nUnicode 17.0 segmentation is required: maximum Tamil basic/1k/old 10/11/8 graphemes,\nTelugu basic/1k 8/9. Native Swift independently checks selected-word maxima.\nPer-item provenance: {rows_path.split('/')[-1]}.\n\nTatoeba {name} contributors: CC BY 2.0 France.\nhttps://creativecommons.org/licenses/by/2.0/fr/\nhttps://tatoeba.org/en/downloads\nSentences: https://downloads.tatoeba.org/exports/per_language/{('tam' if code == 'ta' else 'tel')}/{('tam' if code == 'ta' else 'tel')}_sentences_detailed.tsv.bz2\nSnapshot SHA-256: {sha(sentences.read_bytes())}\nSentence rows: {sentence_count}; contributor identifiers: {len(authors)}.\nWhole-token observations preserve digits, hyphens, underscores, apostrophes,\nmarks and controls wittam token boundaries. Tokens and contiguous excerpts\nare used unchanged; no normalization creates an observation. One observation\nper sentence; missing data is NA, never zero or estimated component frequency.\nTelugu multiword options may be literal contiguous sentence excerpts, marked\nsentence-fragment and credited separately. The original Tamil-old phrase is\nexplicitly retained as authored legacy practice. Exact internal spaces remain; normal word generation trims borders and consumes\none slot per component, as it did before this corpus change. No border spaces, repeated spaces, artificial spelling or sentence\nconcatenation is added. Only selected excerpts are bundled;\nno full sentence collection, translations or audio is distributed.\n\n"
    if code == 'ta':
        notice += 'wordfreq 3.1.1 observations: https://pypi.org/project/wordfreq/3.1.1/\nWheel SHA-256: ' + WHEEL_SHA + '\nMember: wordfreq/data/small_ta.msgpack.gz\nMember SHA-256: 68ed68a8bd703e1aafe8c0adc3827dada57eb3226837dabf26716187fb796547\n68526 observed whole tokens; bands rank independently attested spellings,\nnot usage counts or runtime Zipf values. No frequency-only entries are added.\n\n'
    notice += 'Tatoeba contributor identifiers (all processed rows):\n' + '\n'.join((a if a == '(unowned)' else a + ' https://tatoeba.org/en/user/profile/' + quote(a, safe='') for a in authors)) + '\n\n' + license_text
    notice = notice.rstrip() + '\n'
    output = {swift_path: swift.encode(), rows_path: rows.encode(), notice_path: notice.encode()}
    doc = dict(dictionaryURL='https://kaikki.org/dictionary/'+name+'/kaikki.org-dictionary-'+name+'.jsonl', frequencyWheelSHA256=WHEEL_SHA if code=='ta' else None, frequencyMember='wordfreq/data/small_ta.msgpack.gz' if code=='ta' else None, frequencyMemberSHA256='68ed68a8bd703e1aafe8c0adc3827dada57eb3226837dabf26716187fb796547' if code=='ta' else None, schemaVersion=1, revision=revision, dictionarySHA256=sha(dictionary.read_bytes()), sentencesSHA256=sha(sentences.read_bytes()), sentenceRows=sentence_count, contributorIdentifiers=len(authors), legacyUnattested=unattested, artifacts={n: sha(b) for (n, b) in output.items()}, pools={})
    for (pool, words) in pools.items():
        doc['pools'][pool] = dict(count=len(words), minimumUTF16Length=min(map(len, words)), maximumUTF16Length=max(map(len, words)), minimumGraphemeCount=min((graphemes[w] for w in words)), maximumGraphemeCount=max((graphemes[w] for w in words)), characters=''.join(sorted(set(''.join(words)))), categories=dict(collections.Counter((category(w) for w in words))), leadingSpaces=sum((w.startswith(' ') for w in words)), trailingSpaces=sum((w.endswith(' ') for w in words)), sourceKinds=dict(collections.Counter((forms[w]['kind'] for w in words))), sentenceObserved=sum((w in counts for w in words)), wordfreqObserved=sum((w in bands for w in words)), wordsSHA256=sha(('\n'.join(words) + '\n').encode()))
    output[manifest_path] = (json.dumps(doc, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()
    return output

def verify_bundled(root):
    require(len(PUBLISHED) == 8, 'eight immutable pins required')
    for (name, digest) in PUBLISHED.items():
        require(sha((root / name).read_bytes()) == digest, 'published pin mismatch: ' + name)
    for (code, S) in spec.items():
        name = S['name']
        native = (root / ('Sources/Typebar/' + name + 'Corpus.generated.swift')).read_text()
        pools = {{'basic':'basic','words1k':'1k','wordsOld':'old'}[n]: [json.loads(w) for w in re.findall(r'"[^"]*"', values)] for n, values in re.findall(r'static let (basic|words1k|wordsOld): \[String\] = \[\n(.*?)\n  \]', native, re.S)}
        require(list(pools) == list(S['pools']), 'missing native pools')
        raw = (root / ('Resources/' + name + 'CorpusSources.txt')).read_text().splitlines()
        rows = [x.split('\t') for x in raw if not x.startswith('#')]
        require(all((len(x) == 11 for x in rows)), 'invalid source fields')
        provenance = {x[0]: x for x in rows}
        require(len(provenance) == len(rows) and set(provenance) == set().union(*map(set, pools.values())), 'missing provenance')
        for row in rows:
            require(row[0] == row[3] and row[5] == 'none' and (row[1] in {'dictionary', 'dictionary-character', 'sentence-fragment', 'typebar-legacy'}), 'source identity mismatch')
            require(row[6] == 'NA' or row[6].isdigit(), 'invalid frequency observation')
            require(row[8:] == ['NA', 'NA', 'NA'] or (row[8].isdigit() and int(row[8]) > 0 and row[9].isdigit() and row[10]), 'invalid sentence observation')
            if row[1] == 'sentence-fragment':
                require(code == 'te' and ' ' in row[0] and (row[9] != 'NA') and (row[2] == 'https://tatoeba.org/en/sentences/show/' + row[9]), 'uncredited fragment')
            if row[1] == 'dictionary-character':
                require(len(row[0]) == 1 and row[4] in {'character', 'symbol'}, 'false character attestation')
        doc = json.loads((root / ('Compatibility/' + name.lower() + '-corpus.json')).read_text())
        for (pool, words) in pools.items():
            p = S['pools'][pool]
            keys = set(p['keys'] + ''.join(S['legacy']))
            require(len(words) == len(set(words)) == p['count'] and set(S['legacy']) <= set(words), 'count or legacy mismatch')
            require(pool!='1k' or set(pools['basic']) <= set(words), 'basic vocabulary retention mismatch')
            require(pool!='old' or set(S['oldSeeds'])<=set(words),'old exercise retention mismatch')
            require(set(''.join(words)) == keys and all((valid_spelling(w, keys, p['maximum']) and len(w) >= p['minimum'] for w in words)), 'literal shape mismatch')
            require(dict(collections.Counter((category(w) for w in words))) == p['quotas'], 'category mismatch')
            require(doc['pools'][pool]['wordsSHA256'] == sha(('\n'.join(words) + '\n').encode()), 'word pin mismatch')
            require(sum((w.startswith(' ') for w in words)) == 0 and sum((w.endswith(' ') for w in words)) == 0, 'border shape mismatch')

class ContractTests(unittest.TestCase):
    def test_literal_shapes_and_old_exercises(self):
        for w in ['\u0baa\u0bc1\u0ba4\u0bcd\u0ba4\u0b95\u0bae\u0bcd','\u0b87\u0b9a\u0bc8 \u0ba8\u0b9f\u0bc8','\u0c2a\u0c41\u0c38\u0c4d\u0c24\u0c15\u0c02']:
            self.assertTrue(valid_spelling(w,set(w),19))
        for w in ['\u0bbf','\u0c3f\u0c15','\u0b85  \u0b95','\u0b95\u200d\u0b95']:
            self.assertFalse(valid_spelling(w,set(w),19))
    def test_combining_and_control_token_boundaries(self):
        for w in ['\u0b95-\u0b95','\u0c15_2',"\u0c15'\u0c15",'\u0c15\u200d\u0c15','\u0b95\u0301']:
            self.assertNotIn(w[0],[w[a:b] for a,b in token_spans(w)])
        self.assertEqual([ '\u0baa\u0bc1\u0ba4\u0bcd\u0ba4\u0b95\u0bae\u0bcd \u0c2a\u0c41\u0c38\u0c4d\u0c24\u0c15\u0c02'[a:b] for a,b in token_spans('\u0baa\u0bc1\u0ba4\u0bcd\u0ba4\u0b95\u0bae\u0bcd \u0c2a\u0c41\u0c38\u0c4d\u0c24\u0c15\u0c02')],['\u0baa\u0bc1\u0ba4\u0bcd\u0ba4\u0b95\u0bae\u0bcd','\u0c2a\u0c41\u0c38\u0c4d\u0c24\u0c15\u0c02'])
    def test_wrong_source_pin_fails_before_parsing(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'bad';p.write_bytes(b'{}')
            with self.assertRaisesRegex(ValueError,'dictionary pin mismatch'):prepare('ta',p,p,p,p)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    for code in spec:
        p.add_argument('--' + code + '-dictionary', type=Path)
        p.add_argument('--' + code + '-sentences', type=Path)
    p.add_argument('--wordfreq-wheel', type=Path)
    p.add_argument('--grapheme-node', type=Path)
    p.add_argument('--output', type=Path)
    p.add_argument('--check', action='store_true')
    p.add_argument('--self-test', action='store_true')
    p.add_argument('--check-bundled', action='store_true')
    args = p.parse_args()
    if args.self_test:
        raise SystemExit(not unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests)).wasSuccessful())
    if args.check_bundled:
        verify_bundled(ROOT)
        print('Tamil/Telugu pinned corpus/provenance check passed')
        return
    require(args.output and args.wordfreq_wheel and args.grapheme_node, 'output, wordfreq wheel and pinned grapheme node required')
    output = {}
    for code in spec:
        (dictionary, sentences) = (getattr(args, code + '_dictionary'), getattr(args, code + '_sentences'))
        require(dictionary and sentences, 'both fixed snapshots required')
        output.update(artifacts(code, dictionary, sentences, args.wordfreq_wheel, args.grapheme_node))
    if PUBLISHED:
        require({n: sha(b) for (n, b) in output.items()} == PUBLISHED, 'source reconstruction pins mismatch')
    for (n, b) in output.items():
        path = args.output / n
        if args.check:
            require(path.read_bytes() == b, 'source reconstruction mismatch: ' + n)
        else:
            require(not path.exists(), 'refusing to overwrite: ' + n)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b)
    print('Tamil/Telugu source reproduction checked' if args.check else 'Tamil/Telugu corpora prepared')
if __name__ == '__main__':
    main()
