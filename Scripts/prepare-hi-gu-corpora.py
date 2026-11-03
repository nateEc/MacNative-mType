#!/usr/bin/env python3
"""Reproduce independent Hindi/Gujarati literal entries and source-preserved phrases.

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
spec = {'hi': {'name': 'Hindi', 'prefix': 'hindi', 'legacy': ['\u092a\u0941\u0938\u094d\u0924\u0915', '\u0915\u0932\u092e', '\u0916\u093f\u0921\u093c\u0915\u0940', '\u0930\u093e\u0938\u094d\u0924\u093e', '\u0930\u094b\u0936\u0928\u0940', '\u092a\u0941\u0932', '\u0938\u0941\u092c\u0939', '\u0915\u093e\u0917\u091c\u093c', '\u092c\u0917\u0940\u091a\u093e', '\u092c\u093e\u0926\u0932', '\u0936\u093e\u0902\u0924\u093f', '\u0926\u0940\u092a\u0915', '\u092a\u0939\u093e\u0921\u093c', '\u092c\u0940\u091c', '\u0938\u0902\u0917\u0940\u0924', '\u092e\u0947\u091c\u093c', '\u0935\u093f\u091a\u093e\u0930', '\u091f\u093f\u092a\u094d\u092a\u0923\u0940', '\u0915\u0932\u094d\u092a\u0928\u093e', '\u092a\u094d\u0930\u092f\u093e\u0938', '\u0926\u0942\u0930\u0940', '\u0915\u0926\u092e', '\u0927\u0948\u0930\u094d\u092f', '\u0938\u0902\u0924\u0941\u0932\u0928'], 'pools': {'basic': {'count': 200, 'minimum': 2, 'maximum': 10, 'maxG': 5, 'keys': '\u0901\u0902\u0905\u0906\u0907\u0908\u0909\u090a\u090f\u0910\u0915\u0916\u0917\u091a\u091b\u091c\u091f\u0920\u0921\u0923\u0924\u0925\u0926\u0927\u0928\u092a\u092b\u092c\u092d\u092e\u092f\u0930\u0932\u0935\u0936\u0937\u0938\u0939\u093c\u093e\u093f\u0940\u0941\u0942\u0943\u0947\u0948\u094b\u094d', 'quotas': {'mark spaces=0': 193, 'plain spaces=0': 7}}, '1k': {'count': 999, 'minimum': 1, 'maximum': 12, 'maxG': 6, 'keys': '\u0901\u0902\u0903\u0905\u0906\u0907\u0908\u0909\u090a\u090f\u0910\u0913\u0914\u0915\u0916\u0917\u0918\u091a\u091b\u091c\u091d\u091e\u091f\u0920\u0921\u0922\u0923\u0924\u0925\u0926\u0927\u0928\u092a\u092b\u092c\u092d\u092e\u092f\u0930\u0932\u0935\u0936\u0937\u0938\u0939\u093c\u093e\u093f\u0940\u0941\u0942\u0943\u0947\u0948\u094b\u094c\u094d\u0950', 'quotas': {'mark spaces=0': 956, 'plain spaces=0': 43}}}}, 'gu': {'name': 'Gujarati', 'prefix': 'gujarati', 'legacy': ['\u0aac\u0abe\u0ab0\u0ac0', '\u0aaa\u0aa4\u0a82\u0a97', '\u0aa8\u0aa6\u0ac0', '\u0aa6\u0ac0\u0ab5\u0acb', '\u0aaa\u0ab0\u0acd\u0aa3', '\u0ab0\u0a82\u0a97', '\u0a9a\u0abf\u0aa4\u0acd\u0ab0', '\u0a98\u0aa1\u0abf\u0aaf\u0abe\u0ab3', '\u0ab8\u0aab\u0ab0', '\u0ab8\u0ac2\u0ab0\u0a9c', '\u0ab5\u0abe\u0aa6\u0ab3', '\u0aaa\u0ac1\u0ab2', '\u0a95\u0abf\u0aa8\u0abe\u0ab0\u0acb', '\u0ab8\u0a82\u0a97\u0ac0\u0aa4', '\u0aaa\u0acd\u0ab0\u0ab6\u0acd\u0aa8', '\u0a9c\u0ab5\u0abe\u0aac', '\u0a95\u0ab2\u0acd\u0aaa\u0aa8\u0abe', '\u0aa8\u0acb\u0a82\u0aa7\u0aaa\u0acb\u0aa5\u0ac0', '\u0aaa\u0acd\u0ab0\u0aaf\u0aa4\u0acd\u0aa8', '\u0ab5\u0abf\u0ab0\u0abe\u0aae', '\u0ab9\u0abf\u0a82\u0aae\u0aa4', '\u0aa7\u0ac0\u0ab0\u0a9c', '\u0ab8\u0ab0\u0ab3\u0aa4\u0abe', '\u0aa4\u0abe\u0ab2'], 'pools': {'basic': {'count': 214, 'minimum': 1, 'maximum': 12, 'maxG': 6, 'keys': '\u0a82\u0a85\u0a86\u0a88\u0a89\u0a8f\u0a93\u0a95\u0a96\u0a97\u0a98\u0a9a\u0a9b\u0a9c\u0a9f\u0aa0\u0aa1\u0aa3\u0aa4\u0aa5\u0aa6\u0aa7\u0aa8\u0aaa\u0aab\u0aac\u0aad\u0aae\u0aaf\u0ab0\u0ab2\u0ab3\u0ab5\u0ab6\u0ab7\u0ab8\u0ab9\u0abe\u0abf\u0ac0\u0ac1\u0ac2\u0ac3\u0ac7\u0acb\u0acd', 'quotas': {'mark spaces=0': 199, 'plain spaces=0': 15}}, '1k': {'count': 1004, 'minimum': 1, 'maximum': 19, 'maxG': 12, 'keys': ' \u0a82\u0a83\u0a85\u0a86\u0a87\u0a88\u0a89\u0a8a\u0a8f\u0a90\u0a93\u0a94\u0a95\u0a96\u0a97\u0a98\u0a99\u0a9a\u0a9b\u0a9c\u0a9d\u0a9e\u0a9f\u0aa0\u0aa1\u0aa2\u0aa3\u0aa4\u0aa5\u0aa6\u0aa7\u0aa8\u0aaa\u0aab\u0aac\u0aad\u0aae\u0aaf\u0ab0\u0ab2\u0ab3\u0ab5\u0ab6\u0ab7\u0ab8\u0ab9\u0abe\u0abf\u0ac0\u0ac1\u0ac2\u0ac3\u0ac7\u0ac8\u0ac9\u0acb\u0acc\u0acd', 'quotas': {'mark spaces=0': 868, 'mark spaces=1': 27, 'mark spaces=2': 3, 'mark spaces=3': 2, 'plain spaces=0': 103, 'plain spaces=1': 1}}}}}
PINS = {'Hindi.jsonl': 'f4a417e93e7d494712a974e0ce167d071d01a75898917e194f4ca58ec7817e6c', 'Gujarati.jsonl': '8811fd6d77cf380066a01c0b5df4d784651101b923f9e4cf62401f2d0fda8405', 'hin_sentences_detailed.tsv.bz2': '596c48494d1e76ac7d5954d53a930342628cae9f4c884ae10c080986834bc10f', 'guj_sentences_detailed.tsv.bz2': '5702f42ba49c53a570f6550285254acea0a4d8dbfb80a9d9d0d6d7652edce04b'}
WHEEL_SHA = '4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473'
PUBLISHED = {'Compatibility/gujarati-corpus.json': '0a20b87a94305118b0922d709f666b0b269d54b93474329c7bc160af703bc7c3', 'Compatibility/hindi-corpus.json': 'a72832ba3bf7025187045934ebe78c26cf0faf4605491374c04a3276b35944a4', 'Resources/GujaratiCorpusNotices.txt': '03be99a46c365e3d7a2cbdde823bd1687dfcb7b6769dde676fa2b88470d82211', 'Resources/GujaratiCorpusSources.txt': '4fa618a7b7864bfa38e7b5568e57125f343a2d53eaed1a1e04b507a261018257', 'Resources/HindiCorpusNotices.txt': '398121a277b6c82e396cf611e5dabf2e207f7ec15bb8b0ce36edd2f6f7dfb6c5', 'Resources/HindiCorpusSources.txt': '338114066d72c01fa415839528f61a638d1eb24df3cd60baa59109662a7419d4', 'Sources/Typebar/GujaratiCorpus.generated.swift': '017576cabb0f55d2f978933893e81936314726c6e11e8323aeccd0d3d963c0da', 'Sources/Typebar/HindiCorpus.generated.swift': 'aaf17114ed66a55990edd27d084594e935cb2cd475327476171c12ddac02145e'}

def valid_spelling(w, keys, maximum):
    return bool(w) and len(w) <= maximum and (set(w) <= keys) and (w == unicodedata.normalize('NFC', w)) and ('  ' not in w) and bool(w.strip()) and w.strip()[0].isalpha() and all((c == ' ' or c.isalpha() or unicodedata.category(c).startswith('M') for c in w))

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
    require(sha(sentences_path.read_bytes()) == PINS[('hin' if code == 'hi' else 'guj') + '_sentences_detailed.tsv.bz2'], 'sentence pin mismatch')
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
        require(ident.isdigit() and lang == ('hin' if code == 'hi' else 'guj'), 'invalid sentence identity')
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
        if code == 'gu':
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
    for w in S['legacy']:
        forms.setdefault(w, dict(kind='typebar-legacy', title='Typebar authored starter vocabulary', form=w, pos='NA'))
    bands = {}
    license_text = 'No wordfreq dataset is used for Gujarati.\n'
    if code == 'hi':
        with zipfile.ZipFile(wheel) as z:
            license_text = z.read('wordfreq-3.1.1.dist-info/METADATA').decode()
            license_text = license_text[license_text.index('## License'):].strip() + '\n'
            member = z.read('wordfreq/data/small_hi.msgpack.gz')
            require(len(member) == 148115 and sha(member) == '92ccbf70297d28e97af55a2a517b95c3d8b599e4cc943fb6d4612a3d44a86992', 'Hindi member pin mismatch')
        import msgpack
        require(msgpack.__version__ == '1.1.2', 'requires msgpack 1.1.2')
        bins = msgpack.unpackb(gzip.decompress(member), raw=False)
        require(bins[0] == {'format': 'cB', 'version': 1}, 'invalid frequency format')
        for (i, words) in enumerate(bins[1:]):
            require(type(words) is list and words == sorted(set(words)), 'invalid frequency bin')
            for w in words:
                require(type(w) is str and w not in bands, 'invalid frequency token')
                bands[w] = i
        require(len(bands) == 26653, 'unexpected Hindi token count')
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
        eligible = {w for w in forms if set(w) <= allowedkeys and s['minimum'] <= len(w) <= s['maximum'] and (g[w] <= s['maxG']) and (category(w) in s['quotas'])}
        chosen = set(S['legacy']) | set(pools.get('basic', []))
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
        if code == 'gu' and pool == '1k':
            for side in ['leading', 'trailing']:
                add((w for w in eligible if w.startswith(' ') if side == 'leading')) if side == 'leading' else add((w for w in eligible if w.endswith(' ')))
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
        swift += '  static let ' + ('basic' if pool == 'basic' else 'words1k') + ': [String] = [\n' + ''.join('    '+json.dumps(w,ensure_ascii=False)+',\n' for w in words) + '  ]\n'
    swift += '}\n'
    union = sorted(set().union(*map(set, pools.values())))
    rows = '# word\tsourceKind\tsourceTitle\tsourceForm\tpartOfSpeech\tadaptation\twordfreqWholeTokenBand\tobservationMode\twholeTokenSentenceCount\tfirstSentenceID\tfirstSentenceAuthor (NA means unobserved)\n'
    for w in union:
        f = forms[w]
        (ident, author) = first.get(w, ('NA', 'NA'))
        rows += '\t'.join([w, f['kind'], f['title'], f['form'], f['pos'], 'none', str(bands[w]) if w in bands else 'NA', 'literal-whole-token-or-contiguous-fragment', str(counts[w]) if w in counts else 'NA', ident, author]) + '\n'
    unattested = sorted((w for w in spec[code]['legacy'] if forms[w]['kind'] == 'typebar-legacy'))
    notice = f"Typebar independent {name} literal entries\nRevision: {revision}\nEnglish Wiktionary contributors via Kaikki.org / Wiktextract.\nDictionary: https://kaikki.org/dictionary/{name}/kaikki.org-dictionary-{name}.jsonl\nSnapshot SHA-256: {sha(dictionary.read_bytes())}\nIndex reports extraction 2026-10-30; enwiktionary dump 2026-10-01;\nWiktextract 19f9a30 / 6f96ddf.\nDictionary selection: CC BY-SA 4.0 International.\nhttps://creativecommons.org/licenses/by-sa/4.0/\nContributor pages: https://en.wiktionary.org/wiki/ + encoded sourceTitle.\nOnly unchanged NFC titles/forms of lang_code={code} are selected.\nNonstandard/proscribed/misspelling-only senses, romanizations, template/error\nforms are excluded. Dictionary character/symbol entries are single characters\nand explicitly identified as dictionary-character; they are character practice,\nnot claimed to be complete lexical words. Other entries retain their source POS.\nAll 24 old Typebar starters remain in both pools; no old-word length exceptions.\nSelected lexical attestation missing for: {', '.join(unattested) or '(none)'}.\nThis concerns selected lexical categories, not all raw dictionary occurrences.\nNo artificial spelling, case edits, numbered padding, or original Monkeytype\nword values, source code or assets are used. Reference character sets and shape\ncounts alone constrain selection. Runtime Zipf support remains unknown.\nSource units are BMP UTF-16 units, not graphemes. Pinned Node v24.19.0 /\nUnicode 17.0 segmentation is required: maximum Hindi basic/1k 5/6 graphemes,\nGujarati basic/1k 6/12. Native Swift independently checks selected-word maxima.\nPer-item provenance: {rows_path.split('/')[-1]}.\n\nTatoeba {name} contributors: CC BY 2.0 France.\nhttps://creativecommons.org/licenses/by/2.0/fr/\nhttps://tatoeba.org/en/downloads\nSentences: https://downloads.tatoeba.org/exports/per_language/{('hin' if code == 'hi' else 'guj')}/{('hin' if code == 'hi' else 'guj')}_sentences_detailed.tsv.bz2\nSnapshot SHA-256: {sha(sentences.read_bytes())}\nSentence rows: {sentence_count}; contributor identifiers: {len(authors)}.\nWhole-token observations preserve digits, hyphens, underscores, apostrophes,\nmarks and controls within token boundaries. Tokens and contiguous excerpts\nare used unchanged; no normalization creates an observation. One observation\nper sentence; missing data is NA, never zero or estimated component frequency.\nGujarati multiword and border-space options may be literal contiguous sentence\nexcerpts, identified as sentence-fragment and credited separately. Their exact\nspaces remain in the corpus; normal word generation trims borders and consumes\none slot per component, as it did before this corpus change. No artificial\nspaces or sentence concatenation is used. Only selected excerpts are bundled;\nno full sentence collection, translations or audio is distributed.\n\n"
    if code == 'hi':
        notice += 'wordfreq 3.1.1 observations: https://pypi.org/project/wordfreq/3.1.1/\nWheel SHA-256: ' + WHEEL_SHA + '\nMember: wordfreq/data/small_hi.msgpack.gz\nMember SHA-256: 92ccbf70297d28e97af55a2a517b95c3d8b599e4cc943fb6d4612a3d44a86992\n26653 observed whole tokens; bands rank independently attested spellings,\nnot usage counts or runtime Zipf values. No frequency-only entries are added.\n\n'
    notice += 'Tatoeba contributor identifiers (all processed rows):\n' + '\n'.join((a if a == '(unowned)' else a + ' https://tatoeba.org/en/user/profile/' + quote(a, safe='') for a in authors)) + '\n\n' + license_text
    notice = notice.rstrip() + '\n'
    output = {swift_path: swift.encode(), rows_path: rows.encode(), notice_path: notice.encode()}
    doc = dict(dictionaryURL='https://kaikki.org/dictionary/'+name+'/kaikki.org-dictionary-'+name+'.jsonl', frequencyWheelSHA256=WHEEL_SHA if code=='hi' else None, frequencyMember='wordfreq/data/small_hi.msgpack.gz' if code=='hi' else None, frequencyMemberSHA256='92ccbf70297d28e97af55a2a517b95c3d8b599e4cc943fb6d4612a3d44a86992' if code=='hi' else None, schemaVersion=1, revision=revision, dictionarySHA256=sha(dictionary.read_bytes()), sentencesSHA256=sha(sentences.read_bytes()), sentenceRows=sentence_count, contributorIdentifiers=len(authors), legacyUnattested=unattested, artifacts={n: sha(b) for (n, b) in output.items()}, pools={})
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
        pools = {('basic' if n == 'basic' else '1k'): [json.loads(w) for w in re.findall(r'"[^"]*"', values)] for n, values in re.findall(r'static let (basic|words1k): \[String\] = \[\n(.*?)\n  \]', native, re.S)}
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
                require(code == 'gu' and ' ' in row[0] and (row[9] != 'NA') and (row[2] == 'https://tatoeba.org/en/sentences/show/' + row[9]), 'uncredited fragment')
            if row[1] == 'dictionary-character':
                require(len(row[0]) == 1 and row[4] in {'character', 'symbol'}, 'false character attestation')
        doc = json.loads((root / ('Compatibility/' + name.lower() + '-corpus.json')).read_text())
        for (pool, words) in pools.items():
            p = S['pools'][pool]
            keys = set(p['keys'] + ''.join(S['legacy']))
            require(len(words) == len(set(words)) == p['count'] and set(S['legacy']) <= set(words), 'count or legacy mismatch')
            require(set(pools['basic']) <= set(words), 'basic vocabulary retention mismatch')
            require(set(''.join(words)) == keys and all((valid_spelling(w, keys, p['maximum']) and len(w) >= p['minimum'] for w in words)), 'literal shape mismatch')
            require(dict(collections.Counter((category(w) for w in words))) == p['quotas'], 'category mismatch')
            require(doc['pools'][pool]['wordsSHA256'] == sha(('\n'.join(words) + '\n').encode()), 'word pin mismatch')
            require(sum((w.startswith(' ') for w in words)) == (1 if code == 'gu' and pool == '1k' else 0) and sum((w.endswith(' ') for w in words)) == (1 if code == 'gu' and pool == '1k' else 0), 'border shape mismatch')

class ContractTests(unittest.TestCase):

    def test_literal_shapes_reject_bare_marks_and_synthetic_keys(self):
        self.assertTrue(valid_spelling('\u0915\u093f\u0924\u093e\u092c', set('\u0915\u093f\u0924\u093e\u092c'), 12))
        self.assertFalse(valid_spelling('\u093f\u0915', set('\u093f\u0915'), 12))
        self.assertFalse(valid_spelling('\u093f', set('\u093f'), 12))
        self.assertFalse(valid_spelling('\u0979\u0915', set('\u0915'), 12))
        self.assertFalse(valid_spelling('\u0a95  \u0a96', set('\u0a95\u0a96 '), 19))
        self.assertTrue(valid_spelling(' \u0a95', set('\u0a95 '), 19))

    def test_combining_and_control_token_boundaries(self):
        self.assertEqual(['\u0915\u093f\u0924\u093e\u092c \u0918\u0930'[a:b] for (a, b) in token_spans('\u0915\u093f\u0924\u093e\u092c \u0918\u0930')], ['\u0915\u093f\u0924\u093e\u092c', '\u0918\u0930'])
        for text in ['\u0918\u0930-\u0918\u0930', '\u0918\u0930_2', "\u0918\u0930'\u0918\u0930", '\u0918\u0930\u200d\u0918\u0930', '\u0918\u0930\u0301']:
            self.assertNotIn('\u0918\u0930', [text[a:b] for (a, b) in token_spans(text)])

    def test_wrong_source_pin_fails_before_parsing(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'bad'
            p.write_bytes(b'{}')
            with self.assertRaisesRegex(ValueError, 'dictionary pin mismatch'):
                prepare('hi', p, p, p, p)

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
        print('Hindi/Gujarati pinned corpus/provenance check passed')
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
    print('Hindi/Gujarati source reproduction checked' if args.check else 'Hindi/Gujarati corpora prepared')
if __name__ == '__main__':
    main()
