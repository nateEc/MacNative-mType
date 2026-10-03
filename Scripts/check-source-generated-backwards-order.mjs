// Read-only complete pinned generator/functions/wordset/weak-spot modules. GetText,
// configuration, active metadata, random draws and UI are owned adapters.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??'');
assert.ok(process.argv[2],'Reference checkout required');
assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),
  '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
const actual=new Set(['test/words-generator','test/funbox/funbox-functions','test/wordset','test/weak-spot']);
const config={mode:'words',words:3,language:'english',showAllLines:false,lazyMode:false,
  punctuation:false,numbers:false,britishEnglish:false};
let activeNames=['backwards','binary'], functions, drawIndex=0;
let ownedIndexes=[], spacingMs=0, ownedRepeated=false;
const languages={english:{name:'english',words:['ab','cd'],rightToLeft:false},
  owned:{name:'owned',words:['ef','gh'],rightToLeft:false}};
const binary=i=>(i%256).toString(2).padStart(8,'0');
const unexpected=()=>{throw Error('Unexpected adapter call outside ordering probe')};
const active=()=>activeNames.map(name=>({name,properties:name==='backwards'?['wordOrder:reverse']:
  name==='underscore_spaces'?['nospace']:[],functions:functions[name]}));
const arrays={randomElementFromArray:words=>words[ownedIndexes.shift()??0],shuffle:words=>words,
  nthElementFromArray:(words,index)=>words.at(index)};
const bindings={
  'config/store':{Config:config},
  'test/custom-text':{getPipeDelimiter:()=>false},
  'test/practise-words':{before:{mode:null}},
  'controllers/quotes-controller':{default:{}},
  'states/test':{isRepeated:()=>ownedRepeated,getCurrentQuote:()=>null,setCurrentQuote:()=>{},getSelectedQuoteId:()=>null},
  'test/funbox/list':{
    getActiveFunboxes:active,
    getActiveFunboxesWithFunction:name=>active().filter(value=>typeof value.functions[name]==='function'),
    findSingleActiveFunboxWithFunction:name=>active().find(value=>typeof value.functions[name]==='function'),
    isFunboxActiveWithFunction:name=>active().some(value=>typeof value.functions[name]==='function'),
    isFunboxActiveWithProperty:name=>active().some(value=>value.properties.includes(name)),
  },
  'utils/arrays':arrays,
  'utils/misc':{zipfyRandomArrayIndex:()=>ownedIndexes.shift()??0},
  'utils/json-data':{getLanguage:async name=>languages[name]},
  'test/events/live-cache':{getLiveCachedMsSinceLastInputEvent:()=>spacingMs},
  'utils/generate':{getBinary:()=>binary(drawIndex++)},
  'utils/word-gen-error':{WordGenError:class extends Error {}},
};
// Erased imported type names are explicit inert exports. Unknown unused
// bindings throw if called; they are not replacement behavior implementations.
const modules=new Map();
const requested=new Map();
function resolve(id,from){
  return id.startsWith('.')?path.posix.normalize(path.posix.join(path.posix.dirname(from),id)):id;
}
for(const id of actual){
  const source=fs.readFileSync(path.join(root,'frontend/src/ts',id+'.ts'),'utf8');
  const code=stripTypeScriptTypes(source,{mode:'transform'});
  for(const match of code.matchAll(/import\s+([\s\S]*?)\s+from\s+["']([^"']+)["'];/g)){
    const target=resolve(match[2],id), names=requested.get(target)??new Set();
    const clause=match[1];
    if(!clause.startsWith('*')){
      if(!clause.startsWith('{')) names.add('default');
      const fields=clause.match(/\{([\s\S]*?)\}/)?.[1]??'';
      for(const field of fields.split(',')){
        const name=field.trim().split(/\s+as\s+/)[0];if(name)names.add(name);
      }
    }
    requested.set(target,names);
  }
  // These are type-only exports erased in the real target module. Exposing
  // inert names repairs single-file stripping, leaving all functions intact.
  const extras=id==='test/wordset'?'\nexport const FunboxWordsFrequency=undefined;':'';
  modules.set(id,new vm.SourceTextModule(code+extras,{identifier:id,
    context:undefined}));
}
function moduleFor(id){
  if(modules.has(id))return modules.get(id);
  const values={...Object.fromEntries([...(requested.get(id)??[])].map(name=>[name,unexpected])),...bindings[id]};
  const mod=new vm.SyntheticModule(Object.keys(values),function(){
    for(const[key,value]of Object.entries(values))this.setExport(key,value);
  },{identifier:id});
  modules.set(id,mod);return mod;
}
const main=moduleFor('test/words-generator');
await main.link((id,from)=>moduleFor(resolve(id,from.identifier)));
await main.evaluate();
functions=modules.get('test/funbox/funbox-functions').namespace.getFunboxFunctions();
// Run the replay fixture first so the real generator's retained results begin
// at index zero. Only the external repeated flag and rank draws are adapters.
config.language='code_swift';activeNames=[];ownedIndexes=[0,2,1];
const codeOpening=await main.namespace.generateWords({name:'code_swift',words:['ab','cd','ef']});
assert.deepEqual(codeOpening.words,['ab ','ef ','cd ']);
ownedRepeated=true;ownedIndexes=[2,2,2];
const codeRepeated=await main.namespace.generateWords({name:'code_swift',words:['other','owned','pool']});
assert.deepEqual(codeRepeated.words,codeOpening.words);
assert.deepEqual(ownedIndexes,[2,2,2],'Repeat uses actual saved targets without rank draws');
ownedRepeated=false;ownedIndexes=[];config.language='english';
for(const [limit,showAll,underscore] of [[3,false,false],[3,false,true],[101,false,true],[101,true,true]]){
  config.words=limit;config.showAllLines=showAll;drawIndex=0;
  activeNames=['backwards','binary',...(underscore?['underscore_spaces']:[])];
  const pool=['oak','elm','ash'];
  const generated=await main.namespace.generateWords({name:'english',words:pool});
  assert.deepEqual(pool,['ash','elm','oak'],'Only the source candidate pool reverses');
  const bound=showAll?limit:Math.min(100,limit);
  const expected=Array.from({length:bound},(_,i)=>binary(i).split('').reverse().join('')+
    (underscore?(i===bound-1?'':'_'):' '));
  assert.deepEqual(generated.words,expected);
  if(limit>bound){
    const next=await main.namespace.getNextWord(bound,100,expected.at(-1),expected.at(-2));
    assert.equal(next.word,binary(bound).split('').reverse().join('')+'_');
  }
}
console.log('4 generated-backwards ordering fixtures passed (GetText/config/metadata/random adapters).');
for(const backwards of [false,true]){
  for(const zipf of [false,true]){
    config.words=3;config.showAllLines=false;
    activeNames=[...(backwards?['backwards']:[]),...(zipf?['zipf']:[])];
    ownedIndexes=[0,2,1];
    const pool=['ab','cd','ef'];
    const generated=await main.namespace.generateWords({name:'english',words:pool});
    assert.deepEqual(pool,backwards?['ef','cd','ab']:['ab','cd','ef']);
    assert.deepEqual(generated.words,backwards?['fe ','ba ','dc ']:['ab ','ef ','cd ']);
    assert.equal(ownedIndexes.length,0);
  }
}
const weakspot=modules.get('test/weak-spot').namespace;
spacingMs=1000;weakspot.updateScore('a',true);
spacingMs=800;weakspot.updateScore('b',true);
ownedIndexes=[0,...Array(19).fill(1)];
const wordset=modules.get('test/wordset').namespace;
assert.equal(weakspot.getWord(new wordset.Wordset(['aaax','bb'])),'aaax');
assert.equal(ownedIndexes.length,0,'Exactly twenty candidates, unknown letters excluded from the mean');
// Fresh keys keep these fixtures independent of the learned a/b scores above.
for(const [character,milliseconds] of [['z',0],['y',1000],['v',750]]){
  spacingMs=milliseconds;weakspot.updateScore(character,true);
}
ownedIndexes=[0,...Array(19).fill(1)];
assert.equal(weakspot.getWord(new wordset.Wordset(['zy','v'])),'v',
  'A learned zero stays in the average; an unknown character does not');
assert.equal(ownedIndexes.length,0);
for(const [character,candidate] of [['e','e\u0301'],['🙂','🙂x']]){
  spacingMs=1000;weakspot.updateScore(character,true);
  ownedIndexes=[0,...Array(19).fill(1)];
  assert.equal(weakspot.getWord(new wordset.Wordset([candidate,'bb'])),candidate,
    'Source for-of scores known code points inside a combining or astral word');
  assert.equal(ownedIndexes.length,0);
}
config.words=3;config.customPolyglot=['english','owned'];
activeNames=['backwards','polyglot'];ownedIndexes=[0,3,1];
const primary=['oak','elm','ash'];
const polyglot=await main.namespace.generateWords({name:'english',words:primary});
assert.deepEqual(primary,['ash','elm','oak']);
assert.deepEqual(polyglot.words,['ba ','hg ','dc '],'Polyglot builds a fresh combined pool, not the reversed primary list');
assert.equal(ownedIndexes.length,0);
console.log('9 ordinary/Zipf/weakspot/polyglot fixtures passed (4 complete actual modules; deterministic rank/shuffle/spacing/language adapters, no source RNG/distribution, physical input, corpus or browser parity claim).');
config.language='code_swift';config.showAllLines=false;
for(const zipf of [false,true]){
  config.words=3;activeNames=['backwards',...(zipf?['zipf']:[])];ownedIndexes=[0,2,1];
  const pool=['ab','cd','ef'];
  const result=await main.namespace.generateWords({name:'code_swift',words:pool});
  assert.deepEqual(pool,['ef','cd','ab']);
  assert.deepEqual(result.words,['fe ','ba ','dc ']);
  assert.equal(ownedIndexes.length,0);
}
for(const [pool,indexes,expected] of [
  [['value2','func'],[0,1],['func ']],
  [['foo()','Foundation','v٢'],[0,1,2],['foo() ','Foundation ','v٢ ']],
  [['aa','AA'],[0,1,1],['aa ','AA ']],
  [['value2'],Array(101).fill(0),['value2 ']],
  [['I','Foundation'],[0,1],['Foundation ']],
]){
  config.words=expected.length;activeNames=[];ownedIndexes=[...indexes];
  const result=await main.namespace.generateWords({name:'code_swift',words:pool});
  assert.deepEqual(result.words,expected);
  assert.equal(ownedIndexes.length,0);
}
config.words=1;activeNames=['weakspot'];ownedIndexes=[1,0,...Array(19).fill(1)];
const codeWeak=await main.namespace.generateWords({name:'code_swift',words:['aaax','bb']});
assert.deepEqual(codeWeak.words,['aaax ']);assert.equal(ownedIndexes.length,0);
console.log('10 code-pool fixtures passed (normal/reverse/Zipf plumbing, real cached repeat, candidate gates and weakspot; ranks, source input words, repeated flag and runtime boundaries are owned adapters, no code corpus, source RNG, punctuation decoration, number injection or device equivalence claim).');
