#!/usr/bin/env python3
"""Rebuild independent Arabic content; original Monkeytype data is not an input.
Requires msgpack 1.1.2. All reference facts below are aggregates only.
"""
from pathlib import Path
import argparse,collections,gzip,hashlib,json,unicodedata,zipfile
ROOT=Path(__file__).resolve().parents[1]
def require(value,message):
    if not value:raise ValueError(message)
def sha(data):return hashlib.sha256(data).hexdigest()
def category(w):return any(unicodedata.category(c)[0]=='M' for c in w)
def graphemes(w):return sum(unicodedata.category(c)[0]!='M' for c in w)
SHAPE={'arabic': {'count': 199, 'histogram': {'3': 3, '4': 4, '5': 7, '6': 19, '7': 32, '8': 34, '9': 38, '10': 26, '11': 15, '12': 9, '13': 7, '14': 3, '15': 1, '16': 1}, 'keys': 'ءأؤإئابةتثجحخدذرزسشصضطظعغفقكلمنهوىيًٌٍَُِّْ', 'marked': 198, 'prefix': '', 'graphemeHistogram': {'2': 7, '3': 22, '4': 59, '5': 55, '6': 37, '7': 16, '8': 2, '9': 1}}, 'arabic_10k': {'count': 9281, 'histogram': {'2': 1, '3': 3, '4': 23, '5': 80, '6': 258, '7': 585, '8': 999, '9': 1318, '10': 1720, '11': 1358, '12': 1130, '13': 888, '14': 396, '15': 303, '16': 126, '17': 39, '18': 25, '19': 18, '20': 7, '21': 4}, 'keys': ' Hءآأؤإئابةتثجحخدذرزسشصضطظعغفقكلمنهوىيًٌٍَُِّْی', 'marked': 8988, 'prefix': ' ', 'graphemeHistogram': {'2': 1, '3': 96, '4': 810, '5': 2333, '6': 2635, '7': 1857, '8': 1038, '9': 379, '10': 87, '11': 30, '12': 11, '13': 3, '15': 1}}}
LEGACY=['كِتاب', 'قَلَم', 'نافِذة', 'طَريق', 'ضَوْء', 'جِسْر', 'صَباح', 'وَرَقة', 'حَديقة', 'سَحابة', 'هُدوء', 'مَنارة', 'جَبَل', 'بِذرة', 'إيقاع', 'مَكْتَب', 'تَأَمُّل', 'مُلاحَظة', 'فِكْرة', 'تَجْرِبة', 'مَسافة', 'خُطْوة', 'صَبْر', 'تَوازُن']
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

def artifacts(dictionary,wheel):
    require(sha(dictionary.read_bytes())=='19eee17681c23b3da039878ee7c970d93b75a339989a17a842f14aa7f44ea236','dictionary pin mismatch')
    require(sha(wheel.read_bytes())=='4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473','wordfreq wheel pin mismatch')
    import msgpack
    require(msgpack.__version__=='1.1.2','requires msgpack 1.1.2')
    with zipfile.ZipFile(wheel) as z:
        member=z.read('wordfreq/data/large_ar.msgpack.gz')
        require(sha(member)=='aa12410764f1946f21d986a920c289c22accb069d9b287d71b61657005516eec','Arabic frequency member pin mismatch')
        license_text=z.read('wordfreq-3.1.1.dist-info/METADATA').decode();license_text=license_text[license_text.index('## License'):].strip()+'\n'
    bins=msgpack.unpackb(gzip.decompress(member),raw=False);require(bins[0]=={'format':'cB','version':1},'invalid frequency format')
    bands={}
    for i,words in enumerate(bins[1:]):
        require(type(words) is list and words==sorted(set(words)),'invalid frequency bin')
        for w in words:
            require(type(w) is str and w not in bands,'duplicate frequency token');bands[w]=i
    require(len(bands)==620701,'unexpected Arabic token count')
    keys=set(''.join(s['keys'] for s in SHAPE.values()))-{' '};forms={}
    def valid(w):return 1<=len(w)<=20 and set(w)<=keys and w[0].isalpha() and all(c.isalpha() or unicodedata.category(c)[0]=='M' for c in w)
    for line in dictionary.open():
        e=json.loads(line)
        if e.get('lang_code')!='ar' or e.get('pos') not in {'noun','verb','adj','adv','name','pron','num','det','conj','intj','prep','postp','particle','phrase','abbrev'}:continue
        senses=e.get('senses',[])
        if not senses or all(set(x.get('tags',[]))&{'misspelling','proscribed','nonstandard'} for x in senses):continue
        for row in [{'form':e['word']}]+e.get('forms',[]):
            raw=row.get('form','');tags=row.get('tags',[])
            if any(t in {'romanization','table-tags','inflection-template','class','misspelling','proscribed','nonstandard'} or t.startswith('error-') for t in tags):continue
            w=unicodedata.normalize('NFC',raw)
            if valid(w):forms.setdefault(w,{'kind':'dictionary','sourceTitle':e['word'],'sourceForm':raw,'pos':e['pos'],'adaptation':'NFC' if raw!=w else 'none'})
    for w in LEGACY:
        canonical=unicodedata.normalize('NFC',w);f=forms.pop(canonical,None)
        if f is None:f={'kind':'typebar-legacy','sourceTitle':'Typebar prior starter vocabulary','sourceForm':w,'pos':'practice','adaptation':'none'}
        elif w!=canonical:f=dict(f,adaptation='prior Typebar canonical-equivalent spelling')
        forms[w]=f
    forms['Hی']={'kind':'typebar-character-practice','sourceTitle':'Typebar mixed-script keyboard contrast: U+0048 LATIN CAPITAL LETTER H / U+06CC ARABIC LETTER FARSI YEH','sourceForm':'Hی','pos':'practice','adaptation':'not a lexical word'}
    def bare(w):return ''.join(c for c in w if unicodedata.category(c)[0]!='M')
    def rank(w):return (bands.get(bare(w),99999),len(w),w)
    pools={}
    for name,s in SHAPE.items():
        prefix=s['prefix'];hist={int(n)-len(prefix):v for n,v in s['histogram'].items()};minG=min(map(int,s['graphemeHistogram']))-len(prefix);maxG=max(map(int,s['graphemeHistogram']))-len(prefix)
        eligible={w for w in forms if len(w) in hist and set(w)<=set(s['keys']) and minG<=graphemes(w)<=maxG}
        chosen=set();quotas={True:s['marked'],False:s['count']-s['marked']}
        for w in LEGACY:
            if sum(len(x)==len(w) for x in chosen)<hist[len(w)] and sum(category(x)==category(w) for x in chosen)<quotas[category(w)]:chosen.add(w)
        if prefix:chosen.add('Hی')
        require(chosen<=eligible,'legacy bounds changed')
        def add(options):
            used=collections.Counter(category(w) for w in chosen);lengths=collections.Counter(map(len,chosen))
            options=[w for w in options if w not in chosen and used[category(w)]<quotas[category(w)] and lengths[len(w)]<hist[len(w)]]
            require(options,'cannot satisfy required shape');w=min(options,key=rank);chosen.add(w);return w
        for bound in [minG,maxG]:
            if not any(graphemes(w)==bound for w in chosen):add(w for w in eligible if graphemes(w)==bound)
        missing=set(s['keys'])-set(prefix+''.join(chosen))
        while missing:
            add(w for w in eligible if set(w)&missing);missing=set(s['keys'])-set(prefix+''.join(chosen))
        chosen.update(allocate(eligible,chosen,quotas,hist,rank))
        words=[prefix+w for w in sorted(chosen,key=rank)];pools[name]=words
        require(len(words)==len(set(words))==s['count'],'count mismatch')
        require(dict(collections.Counter(map(len,words)))=={int(n):v for n,v in s['histogram'].items()},'histogram mismatch')
        require(sum(map(category,words))==s['marked'],'mark count mismatch')
        require(set(''.join(words))==set(s['keys']),'key mismatch')
    revision='kaikki-ar-20261103-literal-v1'
    swift='// Independent Arabic practice content; see bundled provenance and licenses.\nenum ArabicCorpus {\n  static let revision = '+json.dumps(revision)+'\n'
    for name,words in pools.items():swift+='  static let '+('basic' if name=='arabic' else 'words10k')+': [String] = [\n'+''.join('    '+json.dumps(w,ensure_ascii=False)+',\n' for w in words)+'  ]\n'
    swift+='}\n'
    rows='# rawEntry\tsourceKind\tsourceTitle\tsourceForm\tpartOfSpeech\tadaptation\twordfreqWholeUnmarkedTokenBand (NA means unobserved)\n'
    for raw in sorted(set().union(*map(set,pools.values()))):
        w=raw.removeprefix(' ');f=forms[w];rows+='\t'.join([raw,f['kind'],f['sourceTitle'],f['sourceForm'],f['pos'],f['adaptation']+('; prepend one ASCII space' if raw.startswith(' ') else ''),str(bands[bare(w)]) if bare(w) in bands else 'NA'])+'\n'
    unattested=[w for w in LEGACY if forms[w]['kind']=='typebar-legacy']
    retired=[w for w in LEGACY if w not in pools['arabic']]
    notice=f'''Typebar independent Arabic word practice
Revision: {revision}
English Wiktionary contributors via Kaikki.org / Wiktextract.
https://kaikki.org/dictionary/Arabic/kaikki.org-dictionary-Arabic.jsonl
Snapshot SHA-256: 19eee17681c23b3da039878ee7c970d93b75a339989a17a842f14aa7f44ea236
Index reports extraction 2026-10-30, enwiktionary dump 2026-10-01,
Wiktextract 19f9a30 / 6f96ddf.
Dictionary selection and canonical-equivalent adaptations: CC BY-SA 4.0.
https://creativecommons.org/licenses/by-sa/4.0/
Contributor pages: https://en.wiktionary.org/wiki/ + encoded sourceTitle.
Lexical titles/forms are selected from lang_code=ar, normalized to NFC.
Misspelling/proscribed/nonstandard-only senses and romanization/template/error
forms are excluded. No frequency-only spellings or constructed word roots.
All 24 prior spellings remain in 10k and stored/custom targets keep their units.
Basic retains the first 20 prior entries that fit the original length quotas;
four later five-unit entries retire only from new basic draws. They are:
{", ".join(retired)}.
Missing selected lexical witnesses: {', '.join(unattested)}.
This is not proof that these words are absent from the full raw dictionary.
The single Hی entry is an independently authored mixed-script keyboard exercise,
not an attested Arabic word. It covers Latin H and Persian yeh explicitly.
No Monkeytype words, source code, fonts or assets are imported.
10k raw entries deliberately prepend one ASCII space, matching the raw-entry
framing aggregate. Production generation handles this through existing trimming.
Complete UTF-16 length histograms, character sets, marked-entry counts and
minimum/maximum grapheme counts are retained. Full grapheme, frequency,
difficulty and linguistic quality distributions are not certified equivalent.
Selection uses independent whole unmarked token observations, then length and
mark quota allocation; frequency bands are not runtime Zipf metadata.
No new input sanitization or stored-target migration is performed.

wordfreq 3.1.1, Robyn Speer: https://pypi.org/project/wordfreq/3.1.1/
Wheel SHA-256: 4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473
Arabic member SHA-256: aa12410764f1946f21d986a920c289c22accb069d9b287d71b61657005516eec
620701 observed whole tokens. Data CC BY-SA 4.0; code Apache 2.0.
The upstream metadata license section follows.

{license_text}'''
    output={'Sources/Typebar/ArabicCorpus.generated.swift':swift,'Resources/ArabicCorpusNotices.txt':notice,'Resources/ArabicCorpusSources.txt':rows}
    manifest={'revision':revision,'dictionarySha256':'19eee17681c23b3da039878ee7c970d93b75a339989a17a842f14aa7f44ea236','referenceAggregates':SHAPE,'legacy':LEGACY,'legacyWithoutSelectedLexicalWitness':unattested,'retiredFromNewBasicDraws':retired,'pools':{name:{'count':len(words),'graphemeHistogram':dict(sorted(collections.Counter(map(graphemes,words)).items())),'kindCounts':dict(collections.Counter(forms[w.removeprefix(' ')]['kind'] for w in words))} for name,words in pools.items()},'artifactSha256':{path:sha(data.encode()) for path,data in output.items()}}
    output['Compatibility/arabic-corpus.json']=json.dumps(manifest,ensure_ascii=False,indent=2)+'\n';return output

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--dictionary',type=Path,required=True);p.add_argument('--wordfreq-wheel',type=Path,required=True);p.add_argument('--output-root',type=Path,default=ROOT);p.add_argument('--check',action='store_true');a=p.parse_args()
    for name,data in artifacts(a.dictionary,a.wordfreq_wheel).items():
        target=a.output_root/name
        if a.check:require(target.read_bytes()==data.encode(),'published mismatch: '+name)
        else:target.parent.mkdir(parents=True,exist_ok=True);target.write_text(data)
    print('Arabic source reconstruction '+('verified' if a.check else 'prepared'))
if __name__=='__main__':main()
