#!/usr/bin/env python3
"""Rebuild independent Egyptian/Moroccan content from fixed dictionary/sentence inputs.
No Monkeytype word values or files are inputs. Python 3.9+; standard library only.
"""
from pathlib import Path
import argparse,bz2,collections,hashlib,json,unicodedata
ROOT=Path(__file__).resolve().parents[1]
def require(value,message):
    if not value:raise ValueError(message)
def sha(data):return hashlib.sha256(data).hexdigest()
def category(w):return (w.count(' '),w.startswith(' '),any(unicodedata.category(c)[0]=='M' for c in w))
def graphemes(w):return sum(unicodedata.category(c)[0]!='M' for c in w)
def bare(w):return ''.join(c for c in w if unicodedata.category(c)[0]!='M')
def normalized(w,code):return ''.join(c for c in unicodedata.normalize('NFC',w) if unicodedata.category(c)[0]!='M' or code=='ary' and c in '\u064B\u0651')
SHAPE={'arabic_egypt': {'count': 210, 'keys': ' ءابةتجحخدرزسشصضطعغفقكلمنهوىي', 'histogram': {'2': 15, '3': 83, '4': 71, '5': 21, '6': 13, '7': 1, '8': 6}, 'categories': [[[0, False, False], 203], [[1, False, False], 7]], 'graphemeHistogram': {'2': 15, '3': 83, '4': 71, '5': 21, '6': 13, '7': 1, '8': 6}}, 'arabic_egypt_1k': {'count': 1141, 'keys': ' ءأإئابةتثجحخدذرزسشصضطظعغفقكلمنهوىي', 'histogram': {'2': 46, '3': 253, '4': 304, '5': 301, '6': 115, '7': 69, '8': 32, '9': 9, '10': 3, '11': 1, '12': 2, '13': 3, '14': 2, '16': 1}, 'categories': [[[0, False, False], 1078], [[1, False, False], 55], [[2, False, False], 6], [[3, False, False], 1], [[1, True, False], 1]], 'graphemeHistogram': {'2': 46, '3': 253, '4': 304, '5': 301, '6': 115, '7': 69, '8': 32, '9': 9, '10': 3, '11': 1, '12': 2, '13': 3, '14': 2, '16': 1}}, 'arabic_morocco': {'count': 229, 'keys': ' آأئابةتثجحخدرزسشصضطعغـفقكلمنهوىيًّ', 'histogram': {'2': 12, '3': 56, '4': 91, '5': 48, '6': 17, '7': 4, '8': 1}, 'categories': [[[0, False, False], 221], [[0, False, True], 5], [[1, False, True], 1], [[1, False, False], 2]], 'graphemeHistogram': {'2': 12, '3': 57, '4': 93, '5': 46, '6': 16, '7': 5}}}
PINS={'Egyptian-Arabic.jsonl': 'fe499e5af052d9f78602ca12b75792b7fc5aab7348bcacd439ed67db0a9d419e', 'Moroccan-Arabic.jsonl': '2161dec55655817c8e519fb4d2a3e1d54eae0f35f53bfb0343266e14467b1ab3', 'arz_sentences_detailed.tsv.bz2': '9f1126f2c0338cf0d7b4a8d8c1a1289ab6c4c0ee1b90d3da8c48d7c7e89d5def', 'ary_sentences_detailed.tsv.bz2': 'd09ee6b556be3424587c8d4607bfd240d5e16a114fad75334b420041872ab9cc'}
LEGACY={'arz': ['دلوقتي', 'بكرة', 'شباك', 'شارع', 'قهوة', 'شغل', 'صاحب', 'مركب', 'بحر', 'نور', 'صوت', 'هدوء', 'خطوة', 'مساحة', 'فكرة', 'كراسة', 'رسالة', 'وقت', 'حكاية', 'مكان', 'طريق', 'موسيقى', 'صورة', 'تجربة', 'راحة', 'لمحة', 'مفتاح', 'نقطة', 'اختيار', 'محاولة'], 'ary': ['اليوم', 'غدا', 'شرجم', 'درب', 'أتاي', 'خدمة', 'صاحبي', 'فلوكة', 'بحر', 'ضو', 'صوت', 'سكون', 'خطوة', 'بلاصة', 'فكرة', 'كناش', 'رسالة', 'وقت', 'حكاية', 'مكان', 'زنقة', 'موسيقى', 'تصويرة', 'تجربة', 'راحة', 'لمحة', 'مفتاح', 'نقطة', 'اختيار', 'محاولة']}
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

def artifacts(source):
    for name,h in PINS.items():require(sha((source/name).read_bytes())==h,'source pin mismatch: '+name)
    forms={};counts={};authors={};sentence_counts={}
    for code,file in [('arz','Egyptian-Arabic.jsonl'),('ary','Moroccan-Arabic.jsonl')]:
        keys=set(''.join(s['keys'] for n,s in SHAPE.items() if ('morocco' in n)==(code=='ary')));f={}
        for line in (source/file).open():
            e=json.loads(line)
            if e.get('lang_code')!=code or e.get('pos') in {'character','symbol','prefix','suffix','root','infix'}:continue
            senses=e.get('senses',[])
            if not senses or all(set(x.get('tags',[]))&{'misspelling','proscribed','nonstandard'} for x in senses):continue
            for row in [{'form':e['word']}]+e.get('forms',[]):
                raw=row.get('form','');tags=row.get('tags',[])
                if any(t in {'romanization','table-tags','inflection-template','class','misspelling','proscribed','nonstandard'} or t.startswith('error-') for t in tags):continue
                w=normalized(raw,code)
                if w and w==w.strip() and '  ' not in w and set(w)<=keys:
                    f.setdefault(w,dict(kind='dictionary',sourceTitle=e['word'],sourceForm=raw,pos=e.get('pos',''),adaptation='NFC and dialect mark removal' if raw!=w else 'none'))
        pointed=collections.defaultdict(list)
        if code=='ary':
            for w in f:
                if w!=bare(w):pointed[bare(w)].append(w)
        observed=collections.Counter();people=set();rows=0;identifiers=set()
        for line in bz2.open(source/(code+'_sentences_detailed.tsv.bz2'),'rt'):
            ident,lang,text,author,created,modified=line.rstrip('\n').split('\t')
            require(ident.isdigit() and lang==code and ident not in identifiers,'invalid sentence identity');identifiers.add(ident);rows+=1
            author=author if author not in {'',r'\N'} else '(unowned)';people.add(author);words=text.split(' ');seen=set()
            for i in range(len(words)):
                for size in range(1,5):
                    segment=words[i:i+size]
                    if len(segment)!=size or not all(segment):continue
                    raw=' '.join(segment);w=normalized(raw,code)
                    if not set(w)<=keys:continue
                    seen.add(bare(w))
                    f.setdefault(w,dict(kind='sentence',sourceTitle='',sourceForm=raw,sentenceID=ident,author=author,pos='',adaptation='NFC and dialect mark removal' if w!=raw else 'none'))
                    if code=='ary' and size==2:
                        pieces=bare(w).split(' ')
                        for k,token in enumerate(pieces):
                            for variant in pointed.get(token,[]):
                                candidate=' '.join(pieces[:k]+[variant]+pieces[k+1:])
                                if len(candidate)<=8 and set(candidate)<=keys:
                                    witness=f[variant]
                                    require(bare(candidate)==bare(w),'pointing changed letters')
                                    f.setdefault(candidate,dict(kind='sentence-dictionary-pointing',sourceTitle=witness['sourceTitle'],sourceForm=raw,sentenceID=ident,author=author,pointedComponent=k,pointedComponentForm=witness['sourceForm'],pos=witness['pos'],adaptation='dictionary-attested pointing of the same unpointed component'))
            observed.update(seen)
        for w in LEGACY[code]:f.setdefault(w,dict(kind='typebar-legacy',sourceTitle='Typebar prior dialect starter vocabulary',sourceForm=w,pos='practice',adaptation='none'))
        forms[code]=f;counts[code]=observed;authors[code]=sorted(people);sentence_counts[code]=rows
    pools={};witnesses={}
    for name,s in SHAPE.items():
        code='ary' if 'morocco' in name else 'arz';f=dict(forms[code])
        if name=='arabic_egypt_1k':
            for w,row in list(f.items()):
                if ' ' not in w:f[' '+w]=dict(row,rawFraming='prepend one ASCII space')
        hist={int(k):v for k,v in s['histogram'].items()};quotas={tuple(k):v for k,v in s['categories']};lo=min(map(int,s['graphemeHistogram']));hi=max(map(int,s['graphemeHistogram']))
        eligible={w for w in f if len(w) in hist and set(w)<=set(s['keys']) and lo<=graphemes(w)<=hi and category(w) in quotas}
        chosen=set(LEGACY[code]);require(chosen<=eligible,'old starter entries no longer fit')
        def rank(w):return (-counts[code].get(bare(w.removeprefix(' ')),0),len(w),w)
        def add(options):
            used=collections.Counter(category(w) for w in chosen);lengths=collections.Counter(map(len,chosen))
            options=[w for w in options if w not in chosen and used[category(w)]<quotas[category(w)] and lengths[len(w)]<hist[len(w)]]
            require(options,'required shape unavailable');chosen.add(min(options,key=rank))
        for c,n in sorted(quotas.items(),key=lambda x:x[1]):
            if n==1 and not any(category(w)==c for w in chosen):add(w for w in eligible if category(w)==c)
        for n in [lo,hi]:
            if not any(graphemes(w)==n for w in chosen):add(w for w in eligible if graphemes(w)==n)
        missing=set(s['keys'])-set(''.join(chosen))
        while missing:add(w for w in eligible if set(w)&missing);missing=set(s['keys'])-set(''.join(chosen))
        chosen.update(allocate(eligible,chosen,quotas,hist,rank));words=sorted(chosen,key=rank);pools[name]=words;witnesses[name]={w:f[w] for w in words}
        require(len(words)==len(set(words))==s['count'],'pool count mismatch')
        require(dict(collections.Counter(map(len,words)))==hist,'unit histogram mismatch')
        require(dict(collections.Counter(map(category,words)))==quotas,'spacing/mark category mismatch')
        require(set(''.join(words))==set(s['keys']),'character coverage mismatch')
    revision='kaikki-dialects-20261103-literal-v1';swift='// Independent Arabic dialect content; see bundled provenance and licenses.\nenum ArabicDialectCorpus {\n  static let revision = '+json.dumps(revision)+'\n'
    props={'arabic_egypt':'egyptBasic','arabic_egypt_1k':'egypt1k','arabic_morocco':'moroccoBasic'}
    for name,words in pools.items():swift+='  static let '+props[name]+': [String] = [\n'+''.join('    '+json.dumps(w,ensure_ascii=False)+',\n' for w in words)+'  ]\n'
    swift+='}\n';rows='';used_authors={code:set() for code in forms}
    for name,words in pools.items():
        code='ary' if 'morocco' in name else 'arz'
        for w in words:
            row=dict(witnesses[name][w],pool=name,rawEntry=w,lang=code,wholeUnpointedSpanSentenceObservations=counts[code].get(bare(w.removeprefix(' '))))
            if 'author' in row:used_authors[code].add(row['author'])
            rows+=json.dumps(row,ensure_ascii=False,sort_keys=True)+'\n'
    notice=f'''Typebar independent Egyptian and Moroccan Arabic practice
Revision: {revision}
English Wiktionary contributors via Kaikki.org / Wiktextract.
https://kaikki.org/dictionary/Egyptian%20Arabic/index.html
https://kaikki.org/dictionary/Moroccan%20Arabic/index.html
Both index snapshots report extraction 2026-10-25, enwiktionary dump 2026-10-01,
Wiktextract f9fe161 / 6f96ddf. Fixed inputs:\n'''+''.join(n+' SHA-256: '+h+'\n' for n,h in PINS.items())+f'''
Dictionary content and its adaptations: CC BY-SA 4.0 International.
https://creativecommons.org/licenses/by-sa/4.0/
Contributor pages: https://en.wiktionary.org/wiki/ + encoded sourceTitle.
Only explicit lang_code=arz / ary entries are used, never generic Arabic
entries relabeled as a dialect. NFC is applied first. Egyptian content removes
combining marks; Moroccan content removes marks other than fathatan/shadda.
Original titles/forms and each adaptation remain in the per-entry JSON lines.
Nonstandard/proscribed/misspelling-only senses and romanization/template/error
forms are excluded. Spaces are not used to invent new combinations.
All 30 prior Typebar starter spellings remain in their respective pools.
Unattested legacy spellings are explicitly typebar-legacy, not dictionary claims.

Tatoeba contributors: CC BY 2.0 France.
https://creativecommons.org/licenses/by/2.0/fr/
https://tatoeba.org/en/downloads
https://downloads.tatoeba.org/exports/per_language/arz/arz_sentences_detailed.tsv.bz2
https://downloads.tatoeba.org/exports/per_language/ary/ary_sentences_detailed.tsv.bz2
Rows: arz={sentence_counts['arz']}, ary={sentence_counts['ary']}.
Only contiguous whole ASCII-space-separated token spans are selected. Punctuation
and unsupported characters are never stripped to create smaller word matches.
One normalized, unpointed observation per sentence; absent observations are null,
not measured zero or runtime Zipf values. Ranked within fixed shape quotas.
Moroccan marked phrases may point one component using an independently attested
dialect dictionary form. The unpointed letter sequence must equal the original
sentence span; both sentence and component witnesses are retained. Such derived
phrases are never labeled unchanged sentence text or full-phrase dictionary entries.
Contributors used by selected sentence witnesses:\n'''+''.join(code+': '+', '.join(sorted(names))+'\n' for code,names in used_authors.items())+'''
Full source-unit histograms, letter sets, joint space/leading/mark categories
and grapheme extrema match the fixed reference aggregates. Full Moroccan
grapheme, usage, difficulty and linguistic quality distributions are not proven
equivalent. Complete unmarked Egyptian grapheme histograms follow their unit
histograms. Public download URLs are mutable; reconstruction requires pinned inputs.
One Egyptian 1k entry adds a leading ASCII space as explicit raw framing.
Actual generation retains existing collapse/trim/component and pending-word rules.
Stored prior targets are never regenerated or normalized during replay/repeat.
No Monkeytype word values, code, fonts or assets are imported.
'''
    output={'Sources/Typebar/ArabicDialectCorpus.generated.swift':swift,'Resources/ArabicDialectCorpusNotices.txt':notice,'Resources/ArabicDialectCorpusSources.txt':rows}
    manifest={'revision':revision,'sourceSha256':PINS,'referenceAggregates':SHAPE,'legacy':LEGACY,'pools':{n:{'count':len(ws),'kindCounts':dict(collections.Counter(witnesses[n][w]['kind'] for w in ws)),'graphemeHistogram':dict(sorted(collections.Counter(map(graphemes,ws)).items()))} for n,ws in pools.items()},'artifactSha256':{n:sha(s.encode()) for n,s in output.items()}}
    output['Compatibility/arabic-dialect-corpus.json']=json.dumps(manifest,ensure_ascii=False,indent=2)+'\n';return output

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source-root',type=Path,required=True);p.add_argument('--output-root',type=Path,default=ROOT);p.add_argument('--check',action='store_true');a=p.parse_args()
    for name,data in artifacts(a.source_root).items():
        target=a.output_root/name
        if a.check:require(target.read_bytes()==data.encode(),'published mismatch: '+name)
        else:target.parent.mkdir(parents=True,exist_ok=True);target.write_text(data)
    print('Arabic dialect reconstruction '+('verified' if a.check else 'prepared'))
if __name__=='__main__':main()
