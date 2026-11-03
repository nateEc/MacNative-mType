#!/usr/bin/env python3
"""Reproduce independent Bangla words and Unicode letter practice.

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
spec = {'bn': {'name': 'Bengali', 'prefix': 'bangla', 'legacy': ['\u0986\u09b2\u09cb', '\u09a8\u09a6\u09c0', '\u09aa\u09be\u09a4\u09be', '\u0998\u09c1\u09a1\u09bc\u09bf', '\u09ae\u09c7\u0998', '\u09ac\u0987', '\u0995\u09b2\u09ae', '\u099c\u09be\u09a8\u09be\u09b2\u09be', '\u09b8\u09c7\u09a4\u09c1', '\u09ac\u09be\u0997\u09be\u09a8', '\u09b8\u0995\u09be\u09b2', '\u09b8\u09c1\u09b0', '\u099a\u09bf\u09a0\u09bf', '\u09aa\u09a5', '\u09a4\u09be\u09b0\u09be', '\u099b\u09ac\u09bf', '\u09aa\u09cd\u09b0\u09b6\u09cd\u09a8', '\u0989\u09a4\u09cd\u09a4\u09b0', '\u0995\u09b2\u09cd\u09aa\u09a8\u09be', '\u09ac\u09bf\u09b0\u09a4\u09bf', '\u09b8\u09be\u09b9\u09b8', '\u09a7\u09c8\u09b0\u09cd\u09af', '\u099b\u09a8\u09cd\u09a6', '\u09af\u09be\u09a4\u09cd\u09b0\u09be'], 'oldSeeds': [], 'pools': {'basic': {'count': 199, 'minimum': 1, 'maximum': 7, 'minG': 1, 'maxG': 4, 'keys': '\u0964\u0981\u0982\u0983\u0985\u0986\u0987\u0989\u098f\u0990\u0993\u0995\u0996\u0997\u099a\u099b\u099c\u099d\u099f\u09a0\u09a1\u09a3\u09a4\u09a5\u09a6\u09a7\u09a8\u09aa\u09ab\u09ac\u09ad\u09ae\u09af\u09b0\u09b2\u09b6\u09b7\u09b8\u09b9\u09bc\u09be\u09bf\u09c0\u09c1\u09c7\u09cb\u09cd', 'quotas': {'plain punctuation=True spaces=0': 1, 'mark punctuation=False spaces=0': 176, 'plain punctuation=False spaces=0': 22}, 'histogram': {1: 3, 2: 23, 3: 60, 4: 64, 5: 29, 6: 15, 7: 5}}, '10k': {'count': 9734, 'minimum': 1, 'maximum': 16, 'minG': 1, 'maxG': 8, 'keys': '-.\u0964\u0981\u0982\u0983\u0985\u0986\u0987\u0988\u0989\u098a\u098b\u098f\u0990\u0993\u0994\u0995\u0996\u0997\u0998\u0999\u099a\u099b\u099c\u099d\u099e\u099f\u09a0\u09a1\u09a2\u09a3\u09a4\u09a5\u09a6\u09a7\u09a8\u09aa\u09ab\u09ac\u09ad\u09ae\u09af\u09b0\u09b2\u09b6\u09b7\u09b8\u09b9\u09bc\u09be\u09bf\u09c0\u09c1\u09c2\u09c3\u09c7\u09c8\u09cb\u09cc\u09cd\u09ce', 'quotas': {'plain punctuation=True spaces=0': 1, 'mark punctuation=False spaces=0': 9378, 'plain punctuation=False spaces=0': 341, 'mark punctuation=True spaces=0': 14}, 'histogram': {1: 5, 2: 211, 3: 866, 4: 1624, 5: 2190, 6: 1797, 7: 1300, 8: 831, 9: 454, 10: 242, 11: 116, 12: 59, 13: 23, 14: 11, 15: 2, 16: 3}}}}}
PINS = {'Bengali.jsonl': '3670f2c7607799ca9ae545f9903a59d0715c39ecaf432e21cdbe76d5a9615d70', 'ben_sentences_detailed.tsv.bz2': '8fb9bd01929e1a263ab73536b847c46de9f139c64dbda0fbf69899e8edfe80dd'}
WHEEL_SHA = '4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473'
PUBLISHED = {'Compatibility/bangla-corpus.json': '9ee9c260839d32f6e6e7ca89f25bdfa7eb5df29bf5626798930c932d7010a1af', 'Resources/BanglaCorpusNotices.txt': 'fa6c2f4e42eb26d6c83a8331b0140df26ef622f4e03419bf52edae53b2dff2a3', 'Resources/BanglaCorpusSources.txt': '53fa1a37c54b00aeb8e65d8b9bafbba562811215c5f4a9db348a803d08052c3a', 'Sources/Typebar/BanglaCorpus.generated.swift': '649bff4125b356545719defea1907af44369079e5fe89e4e23885da0b7962bc6'}

def valid_spelling(w,keys,maximum):
    return bool(w) and len(w)<=maximum and set(w)<=keys and w==unicodedata.normalize('NFC',w) and (w=='\u0964' or w[0].isalpha() and all(c.isalpha() or unicodedata.category(c)[0] in {'M','P'} for c in w))
def category(w):
    return ('mark' if any(unicodedata.category(c).startswith('M') for c in w) else 'plain')+' punctuation='+str(any(unicodedata.category(c).startswith('P') for c in w))+' spaces='+str(w.count(' '))

def token_spans(text):
    start = None
    for (i, c) in enumerate(text):
        inside = c.isalnum() or c in "_.-'\u2019" or unicodedata.category(c)[0] in {'M', 'C'}
        if inside and start is None:
            start = i
        elif not inside and start is not None:
            yield (start, i)
            start = None
    if start is not None:
        yield (start, len(text))

def allocate(eligible,chosen,quotas,histogram,rank):
    used=collections.Counter(category(w) for w in chosen)
    lengths=collections.Counter(map(len,chosen));buckets={}
    for w in sorted(eligible-chosen,key=rank):buckets.setdefault((category(w),len(w)),[]).append(w)
    graph={}
    def edge(a,b,n):
        require(n>=0,'negative remaining quota');graph.setdefault(a,{})[b]=n;graph.setdefault(b,{})[a]=0
    for c,n in quotas.items():edge('source',('category',c),n-used[c])
    for (c,n),words in sorted(buckets.items(),key=lambda item:rank(item[1][0])):edge(('category',c),('length',n),len(words))
    for n,limit in histogram.items():edge(('length',n),'sink',limit-lengths[n])
    total=0
    while True:
        previous={'source':None};queue=collections.deque(['source'])
        while queue and 'sink' not in previous:
            node=queue.popleft()
            for target,capacity in graph[node].items():
                if capacity>0 and target not in previous:previous[target]=node;queue.append(target)
        if 'sink' not in previous:break
        amount=sum(quotas.values());node='sink'
        while previous[node] is not None:amount=min(amount,graph[previous[node]][node]);node=previous[node]
        node='sink'
        while previous[node] is not None:
            parent=previous[node];graph[parent][node]-=amount;graph[node][parent]+=amount;node=parent
        total+=amount
    require(total==sum(quotas.values())-len(chosen),'infeasible category/length allocation')
    output=[]
    for (c,n),words in buckets.items():output.extend(words[:len(words)-graph[('category',c)][('length',n)]])
    require(len(output)==total,'allocation count mismatch');return output

def prepare(code, dictionary, sentences_path, wheel, node):
    name = spec[code]['name']
    require(sha(dictionary.read_bytes()) == PINS[name + '.jsonl'], 'dictionary pin mismatch')
    require(sha(sentences_path.read_bytes()) == PINS['ben' + '_sentences_detailed.tsv.bz2'], 'sentence pin mismatch')
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
    forms['\u0964']=dict(kind='unicode-sign',title='Unicode 17.0 U+0964 DEVANAGARI DANDA',form='\u0964',pos='punct')
    counts = collections.Counter()
    first = {}
    authors = set()
    sentences = []
    identifiers = set()
    for line in bz2.open(sentences_path, 'rt'):
        (ident, lang, text, author, _, _) = line.rstrip('\n').split('\t')
        require(ident.isdigit() and lang == 'ben', 'invalid sentence identity')
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
        for w in observed:
            if w in forms:
                counts[w] += 1
                first.setdefault(w, (ident, author))
    for w in S['legacy']+S['oldSeeds']:
        forms.setdefault(w, dict(kind='typebar-legacy', title='Typebar authored starter vocabulary', form=w, pos='NA'))
    bands = {}
    license_text = ''
    if code == 'bn':
        with zipfile.ZipFile(wheel) as z:
            license_text = z.read('wordfreq-3.1.1.dist-info/METADATA').decode()
            license_text = license_text[license_text.index('## License'):].strip() + '\n'
            member = z.read('wordfreq/data/large_bn.msgpack.gz')
            require(len(member) == 1555615 and sha(member) == 'd10ed5ca1e61a6bf210324424ee25c53ff71175398833067d810ccc6c826d581', 'Bengali member pin mismatch')
        import msgpack
        require(msgpack.__version__ == '1.1.2', 'requires msgpack 1.1.2')
        bins = msgpack.unpackb(gzip.decompress(member), raw=False)
        require(bins[0] == {'format': 'cB', 'version': 1}, 'invalid frequency format')
        for (i, words) in enumerate(bins[1:]):
            require(type(words) is list and words == sorted(set(words)), 'invalid frequency bin')
            for w in words:
                require(type(w) is str and w not in bands, 'invalid frequency token')
                bands[w] = i
        require(len(bands) == 238743, 'unexpected Bengali token count')
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
        used = collections.Counter(category(w) for w in chosen)
        lengths = collections.Counter(map(len,chosen))
        require(all(lengths[n]<=limit for n,limit in s['histogram'].items()),'legacy exceeds length quota')

        def add(options):
            w = min((w for w in options if w not in chosen and used[category(w)] < s['quotas'][category(w)] and lengths[len(w)] < s['histogram'][len(w)]), key=rank, default=None)
            require(w is not None, 'source preparation contract')
            chosen.add(w)
            used[category(w)] += 1
            lengths[len(w)] += 1
            return w
        for length in [s['minimum'], s['maximum']]:
            if not any((len(w) == length for w in chosen)):
                add((w for w in eligible if len(w) == length))
        if not any((g[w] == s['maxG'] for w in chosen)):
            add((w for w in eligible if g[w] == s['maxG']))
        missing = allowedkeys - set(''.join(chosen))
        while missing:
            options = [w for w in eligible - chosen if used[category(w)] < s['quotas'][category(w)] and lengths[len(w)] < s['histogram'][len(w)] and set(w) & missing]
            require(options, 'source preparation contract')
            w = min(options, key=lambda w: (-len(set(w) & missing), rank(w)))
            chosen.add(w)
            used[category(w)] += 1
            lengths[len(w)] += 1
            missing -= set(w)
        chosen.update(allocate(eligible,chosen,s['quotas'],s['histogram'],rank))
        pools[pool] = sorted(chosen, key=rank)
        require(len(chosen) == s['count'], 'source preparation contract')
        require(dict(collections.Counter((category(w) for w in chosen))) == s['quotas'], 'category mismatch')
        require(set(''.join(chosen)) == allowedkeys, 'key mismatch')
        require(dict(collections.Counter(map(len,chosen)))==s['histogram'],'length histogram mismatch')
    return (pools, forms, counts, first, sorted(authors), len(sentences), g, bands, license_text)

UCD_SHA='2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c'
UCD_URL='https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt'
MEMBER='wordfreq/data/large_bn.msgpack.gz'
MEMBER_SHA='d10ed5ca1e61a6bf210324424ee25c53ff71175398833067d810ccc6c826d581'

def letter_practice(ucd,forms):
    require(sha(ucd.read_bytes())==UCD_SHA,'UnicodeData pin mismatch')
    records={int(row[0],16):row for row in (line.split(';') for line in ucd.read_text().splitlines())}
    base=list('\u0985\u0986\u0987\u0988\u0989\u098a\u098b\u098f\u0990\u0993\u0994\u0995\u0996\u0997\u0998\u0999\u099a\u099b\u099c\u099d\u099e\u099f\u09a0\u09a1\u09a2\u09a3\u09a4\u09a5\u09a6\u09a7\u09a8\u09aa\u09ab\u09ac\u09ad\u09ae\u09af\u09b0\u09b2\u09b6\u09b7\u09b8\u09b9\u09ce')
    require(len(base)==44 and all(records[ord(c)][2]=='Lo' and records[ord(c)][1].startswith('BENGALI ') for c in base),'invalid independent letters')
    digits=[chr(c) for c in range(0x09E6,0x09F0)]
    require(all(records[ord(c)][2]=='Nd' and records[ord(c)][6]==str(i) for i,c in enumerate(digits)),'invalid digit properties')
    canonical=[''.join(chr(int(part,16)) for part in records[c][5].split()) for c in [0x09DC,0x09DD,0x09DF]]
    require(canonical==['\u09a1\u09bc','\u09a2\u09bc','\u09af\u09bc'] and all(w==unicodedata.normalize('NFC',w) for w in canonical),'canonical decomposition mismatch')
    require(forms.get('\u0995\u09b0\u09cd\u09ae',{}).get('kind')=='dictionary' and forms['\u0995\u09b0\u09cd\u09ae']['form']=='\u0995\u09b0\u09cd\u09ae','independent four-unit exercise needs dictionary witness')
    words=base+digits+['\u09f3','\u0964']+canonical+['\u0995\u09cd\u09b7','\u0995\u09cd\u09b0','\u0995\u09b0\u09cd\u09ae']
    for w in words:
        require(all(ord(c) in records for c in w),'missing Unicode character')
        if w not in forms:
            kind='typebar-conjunct' if w in ['\u0995\u09cd\u09b7','\u0995\u09cd\u09b0'] else 'unicode-canonical' if w in canonical else 'unicode-digit' if w in digits else 'unicode-character'
            forms[w]=dict(kind=kind,title='Typebar authored conjunct practice' if kind=='typebar-conjunct' else UCD_URL,form=w,pos='practice')
    require(len(words)==len(set(words))==62,'letter count mismatch')
    require(dict(collections.Counter(map(len,words)))=={1:56,2:3,3:2,4:1},'letter source-unit distribution mismatch')
    return words

def artifacts(dictionary,sentences,wheel,node,ucd):
    pools,forms,counts,first,authors,sentence_count,graphemes,bands,license_text=prepare('bn',dictionary,sentences,wheel,node)
    letters=letter_practice(ucd,forms);pools['letters']=letters
    program="if(process.version!=='v24.19.0'||process.versions.unicode!=='17.0')throw Error('pinned segmentation required');const fs=require('fs'),s=new Intl.Segmenter('bn',{granularity:'grapheme'});process.stdout.write(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(w=>[...s.segment(w)].length)));"
    p=subprocess.run([str(node),'-e',program],input=json.dumps(letters),capture_output=True,text=True);require(p.returncode==0,p.stderr)
    graphemes.update(dict(zip(letters,json.loads(p.stdout))))
    require(dict(collections.Counter(graphemes[w] for w in letters))=={1:61,2:1},'letter grapheme distribution mismatch')
    revision='kaikki-bn-20261103-literal-v1';swift_path='Sources/Typebar/BanglaCorpus.generated.swift';rows_path='Resources/BanglaCorpusSources.txt';notice_path='Resources/BanglaCorpusNotices.txt';manifest_path='Compatibility/bangla-corpus.json'
    native='// Independent Bengali practice content; see bundled provenance and licenses.\nenum BanglaCorpus {\n  static let revision = '+json.dumps(revision)+'\n'
    for pool,words in pools.items():native+='  static let '+{'basic':'basic','10k':'words10k','letters':'letters'}[pool]+': [String] = [\n'+''.join('    '+json.dumps(w,ensure_ascii=False)+',\n' for w in words)+'  ]\n'
    native+='}\n'
    rows='# word\tsourceKind\tsourceTitle\tsourceForm\tpartOfSpeech\tadaptation\twordfreqWholeTokenBand\tobservationMode\twholeTokenSentenceCount\tfirstSentenceID\tfirstSentenceAuthor\tunicode17LetterWitness (NA means unobserved/not applicable)\n'
    for w in sorted(set().union(*map(set,pools.values()))):
        f=forms[w];ident,author=first.get(w,('NA','NA'));witness=','.join('U+%04X'%ord(c) for c in w) if w in letters else 'NA'
        rows+='\t'.join([w,f['kind'],f['title'],f['form'],f['pos'],'none',str(bands[w]) if w in bands else 'NA','literal-whole-token-with-period',str(counts[w]) if w in counts else 'NA',ident,author,witness])+'\n'
    unattested=sorted(w for w in spec['bn']['legacy'] if forms[w]['kind']=='typebar-legacy')
    notice=f'''Typebar independent Bangla word and letter practice
Revision: {revision}
English Wiktionary contributors via Kaikki.org / Wiktextract.
Dictionary: https://kaikki.org/dictionary/Bengali/kaikki.org-dictionary-Bengali.jsonl
Snapshot SHA-256: {sha(dictionary.read_bytes())}
Index reports extraction 2026-10-25; enwiktionary dump 2026-10-01;
Wiktextract f9fe161 / 6f96ddf.
Dictionary selection: CC BY-SA 4.0 International.
https://creativecommons.org/licenses/by-sa/4.0/
Contributor pages: https://en.wiktionary.org/wiki/ + encoded sourceTitle.
Only unchanged NFC lexical titles/forms of lang_code=bn are selected.
Nonstandard/proscribed/misspelling-only senses and romanization/template/error
forms are excluded. Single dictionary-character entries are explicitly marked,
not claimed as full lexical words. No frequency-only tokens are used.
All 24 Typebar starter words remain in both word pools; no length exceptions.
Selected lexical attestation missing for: {', '.join(unattested)}.
This concerns selected lexical categories, not absence of all raw occurrences.
Basic retains old extra characters \u0998\u09c8; 10k has no extra characters.
The full UTF-16 length histograms, joint mark/punctuation categories, and
character sets are retained. Remaining entries are allocated to category/length
buckets using capacity flow, then ranked within each bucket. This does not
certify linguistic quality or frequency/difficulty equivalence to Monkeytype.
No invented spellings, artificial punctuation, case edits, numbered padding,
original Monkeytype word values, source code or assets are used.
Runtime Zipf metadata is unchanged; bands are not runtime values or usage counts.

wordfreq 3.1.1: https://pypi.org/project/wordfreq/3.1.1/
Wheel SHA-256: {WHEEL_SHA}
Member: {MEMBER}; SHA-256: {MEMBER_SHA}
238743 observed whole tokens; only independently attested entries are ranked.
The complete upstream metadata license section follows contributor credits.

Unicode 17.0 data: {UCD_URL}
Snapshot SHA-256: {UCD_SHA}
Unicode data license: Unicode License V3, bundled in UnicodeNotice.txt.
https://www.unicode.org/license.txt
Letter practice uses independently selected Unicode character facts and existing
Typebar conjuncts \u0995\u09cd\u09b7/\u0995\u09cd\u09b0. The four-unit exercise \u0995\u09b0\u09cd\u09ae is independently attested
in the dictionary. Digit zero through nine and canonical decompositions of
U+09DC/U+09DD/U+09DF are verified against the fixed UnicodeData snapshot.
The standalone danda is Unicode sign practice, not claimed as a dictionary word.
No Unicode chart images or fonts are copied. Per-letter scalar witnesses are
recorded separately even when the same entry also has dictionary attestation.
The corrected 62-item letter pool removes old extra \u098c/\u09e0/\u09e1 and vowel drills
\u0995\u09be/\u0997\u09bf/\u09b8\u09c1/\u0995\u09cd\u09b7\u09be from new letter draws, and uses NFC nukta sequences instead of
three precomposed scalars. All stored old targets retain original UTF-16 units;
no score/history migration rewrites them. Custom text still accepts these forms.

Tatoeba Bengali contributors: CC BY 2.0 France.
https://creativecommons.org/licenses/by/2.0/fr/
https://tatoeba.org/en/downloads
Sentences: https://downloads.tatoeba.org/exports/per_language/ben/ben_sentences_detailed.tsv.bz2
Snapshot SHA-256: {sha(sentences.read_bytes())}
Sentence rows: {sentence_count}; contributor identifiers: {len(authors)}.
Observations use unchanged whole tokens. Digits, periods, hyphens, underscores,
apostrophes, combining marks and controls/format characters remain inside token
boundaries; punctuation stripping never creates partial abbreviation matches.
One count per sentence; absent observations are NA, never zero or estimates.
No sentence bodies, translations or audio are distributed. Missing/unowned
contributors are explicit. Per-item provenance: BanglaCorpusSources.txt.
All processed Tatoeba contributor identifiers follow:

'''+ '\n'.join(a if a=='(unowned)' else a+' https://tatoeba.org/en/user/profile/'+quote(a,safe='') for a in authors)+'\n\n'+license_text
    notice=notice.rstrip()+'\n';output={swift_path:native.encode(),rows_path:rows.encode(),notice_path:notice.encode()}
    doc=dict(schemaVersion=1,revision=revision,dictionarySHA256=sha(dictionary.read_bytes()),sentencesSHA256=sha(sentences.read_bytes()),unicodeSHA256=UCD_SHA,frequencyWheelSHA256=WHEEL_SHA,frequencyMember=MEMBER,frequencyMemberSHA256=MEMBER_SHA,sentenceRows=sentence_count,contributorIdentifiers=len(authors),legacyUnattested=unattested,artifacts={n:sha(b) for n,b in output.items()},pools={})
    for pool,words in pools.items():doc['pools'][pool]=dict(count=len(words),UTF16Histogram=dict(collections.Counter(map(len,words))),minimumGraphemeCount=min(graphemes[w] for w in words),maximumGraphemeCount=max(graphemes[w] for w in words),characters=''.join(sorted(set(''.join(words)))),categories=dict(collections.Counter(category(w) for w in words)),sourceKinds=dict(collections.Counter(forms[w]['kind'] for w in words)),sentenceObserved=sum(w in counts for w in words),wordfreqObserved=sum(w in bands for w in words),wordsSHA256=sha(('\n'.join(words)+'\n').encode()))
    output[manifest_path]=(json.dumps(doc,ensure_ascii=False,sort_keys=True,indent=2)+'\n').encode();return output

def verify_bundled(root):
    require(len(PUBLISHED)==4,'four immutable pins required')
    for n,h in PUBLISHED.items():require(sha((root/n).read_bytes())==h,'published pin mismatch: '+n)
    native=(root/'Sources/Typebar/BanglaCorpus.generated.swift').read_text();pools={n:[json.loads(w) for w in re.findall(r'"[^"]*"',values)] for n,values in re.findall(r'static let (basic|words10k|letters): \[String\] = \[\n(.*?)\n  \]',native,re.S)};require(set(pools)=={'basic','words10k','letters'},'missing native pools')
    rows=[line.split('\t') for line in (root/'Resources/BanglaCorpusSources.txt').read_text().splitlines() if not line.startswith('#')];require(all(len(r)==12 for r in rows),'invalid source fields');provenance={r[0]:r for r in rows};require(len(rows)==len(provenance) and set(provenance)==set().union(*map(set,pools.values())),'missing provenance')
    for r in rows:
        require(r[0]==r[3] and r[5]=='none','changed source form')
        require(r[1] in {'dictionary','dictionary-character','typebar-legacy','unicode-sign','unicode-character','unicode-digit','unicode-canonical','typebar-conjunct'},'invalid source kind')
        require(r[6]=='NA' or r[6].isdigit(),'invalid frequency observation')
        require(r[8:11]==['NA','NA','NA'] or r[8].isdigit() and int(r[8])>0 and r[9].isdigit() and r[10],'invalid sentence observation')
    for pool,s in spec['bn']['pools'].items():
        words=pools['basic' if pool=='basic' else 'words10k'];require(len(words)==len(set(words))==s['count'] and set(spec['bn']['legacy'])<=set(words),'word count or legacy mismatch')
        require(set(''.join(words))==set(s['keys']+''.join(spec['bn']['legacy'])),'word key mismatch')
        require(all(valid_spelling(w,set(s['keys']+''.join(spec['bn']['legacy'])),s['maximum']) for w in words),'invalid literal word')
        require(dict(collections.Counter(map(len,words)))==s['histogram'],'full length histogram mismatch')
        require(dict(collections.Counter(category(w) for w in words))==s['quotas'],'joint category mismatch')
    letters=pools['letters'];require(len(letters)==len(set(letters))==62,'letter count mismatch')
    require(set(''.join(letters))==set('\u0964\u0985\u0986\u0987\u0988\u0989\u098a\u098b\u098f\u0990\u0993\u0994\u0995\u0996\u0997\u0998\u0999\u099a\u099b\u099c\u099d\u099e\u099f\u09a0\u09a1\u09a2\u09a3\u09a4\u09a5\u09a6\u09a7\u09a8\u09aa\u09ab\u09ac\u09ad\u09ae\u09af\u09b0\u09b2\u09b6\u09b7\u09b8\u09b9\u09bc\u09cd\u09ce\u09e6\u09e7\u09e8\u09e9\u09ea\u09eb\u09ec\u09ed\u09ee\u09ef\u09f3'),'letter key mismatch')
    require(dict(collections.Counter(map(len,letters)))=={1:56,2:3,3:2,4:1} and all(w==unicodedata.normalize('NFC',w) for w in letters),'letter shape mismatch')
    for w in letters:require(provenance[w][11]==','.join('U+%04X'%ord(c) for c in w),'missing Unicode witness')

class ContractTests(unittest.TestCase):
    def test_capacity_flow_reassigns_a_greedy_dead_end(self):
        plain=category('\u0995');mark=category('\u0995\u09bf');rank=lambda w:['\u0995\u0995','\u0995','\u0995\u09bf'].index(w)
        self.assertEqual(set(allocate({'\u0995','\u0995\u0995','\u0995\u09bf'},set(),{plain:1,mark:1},{1:1,2:1},rank)),{'\u0995','\u0995\u09bf'})
        with self.assertRaisesRegex(ValueError,'infeasible'):allocate({'\u0995','\u0995\u09bf'},set(),{plain:0,mark:2},{1:0,2:2},rank)
    def test_raw_period_tokens_do_not_invent_abbreviation_parts(self):
        for w in ['\u0995\u09b0\u09cd\u09ae.\u0995\u09b0\u09cd\u09ae','\u0995\u09b0\u09cd\u09ae-\u0995\u09b0\u09cd\u09ae','\u0995\u09b0\u09cd\u09ae_2','\u0995\u09b0\u09cd\u09ae\u200d\u0995\u09b0\u09cd\u09ae','\u0995\u09b0\u09cd\u09ae\u0301']:
            self.assertNotIn('\u0995\u09b0\u09cd\u09ae',[w[a:b] for a,b in token_spans(w)])
        self.assertTrue(valid_spelling('\u0964',{'\u0964'},1));self.assertFalse(valid_spelling('\u09bf\u0995',set('\u09bf\u0995'),7));self.assertFalse(valid_spelling('\u09f1\u0995',set('\u0995'),7))
    def test_wrong_pins_reject_before_source_parsing(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'bad';p.write_bytes(b'{}')
            with self.assertRaisesRegex(ValueError,'dictionary pin mismatch'):prepare('bn',p,p,p,p)
            with self.assertRaisesRegex(ValueError,'UnicodeData pin mismatch'):letter_practice(p,{})

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['dictionary','sentences','wordfreq-wheel','grapheme-node','unicode-data','output']:p.add_argument('--'+name,type=Path)
    p.add_argument('--check',action='store_true');p.add_argument('--self-test',action='store_true');p.add_argument('--check-bundled',action='store_true');a=p.parse_args()
    if a.self_test:raise SystemExit(not unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests)).wasSuccessful())
    if a.check_bundled:verify_bundled(ROOT);print('Bangla pinned corpus/Unicode/provenance check passed');return
    require(all([a.dictionary,a.sentences,a.wordfreq_wheel,a.grapheme_node,a.unicode_data,a.output]),'all fixed inputs and output required')
    output=artifacts(a.dictionary,a.sentences,a.wordfreq_wheel,a.grapheme_node,a.unicode_data)
    if PUBLISHED:require({n:sha(b) for n,b in output.items()}==PUBLISHED,'reconstruction pin mismatch')
    for n,b in output.items():
        path=a.output/n
        if a.check:require(path.read_bytes()==b,'source reconstruction mismatch: '+n)
        else:require(not path.exists(),'refusing to overwrite: '+n);path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b)
    print('Bangla source reproduction checked' if a.check else 'Bangla corpora prepared')

if __name__=='__main__':main()
