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
const actual=new Set(['test/words-generator','test/funbox/funbox-functions','test/wordset','test/weak-spot','test/test-words']);
const config={mode:'words',words:3,language:'english',showAllLines:false,lazyMode:false,
  punctuation:false,numbers:false,britishEnglish:false};
let activeNames=['backwards','binary'], functions, drawIndex=0;
let ownedIndexes=[], spacingMs=0, ownedRepeated=false;
let ownedActiveWordIndex=0;
let ownedSection, sectionCalls=0;
let ownedSectionQueue=[];
const toggledSources=[];
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
  'config/setters':{toggleFunbox:name=>toggledSources.push(name)},
  'test/poetry':{getPoem:async()=>{sectionCalls++;return ownedSectionQueue.length?ownedSectionQueue.shift():ownedSection}},
  'test/custom-text':{getPipeDelimiter:()=>false},
  'test/practise-words':{before:{mode:null}},
  'controllers/quotes-controller':{default:{}},
  'states/test':{isRepeated:()=>ownedRepeated,getCurrentQuote:()=>null,setCurrentQuote:()=>{},getSelectedQuoteId:()=>null,
    getActiveWordIndex:()=>ownedActiveWordIndex},
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
// Provider responses are authored adapters, not HTTP or parser evidence.
// Execute the real section selection and word admission: a successful empty
// section must not be conflated with false/undefined provider failure.
config.language='english';config.words=1;activeNames=['poetry'];ownedRepeated=false;
for(const [response,message,disabled] of [
  [{words:[]},'Random word is empty',false],
  [false,'Failed to pull section',true],
  [undefined,'Failed to pull section',true],
]) {
  ownedSection=response;sectionCalls=0;toggledSources.length=0;
  await assert.rejects(main.namespace.generateWords({name:'english',words:['owned']}),error=>{
    assert.equal(error.message,message);
    assert.equal(error instanceof bindings['utils/word-gen-error'].WordGenError,!disabled);
    return true;
  });
  assert.equal(sectionCalls,1,'Neither failure path silently refetches');
  assert.deepEqual(toggledSources,disabled?['poetry']:[]);
}
ownedSection={words:['harbor']};sectionCalls=0;toggledSources.length=0;
assert.deepEqual((await main.namespace.generateWords({name:'english',words:['owned']})).words,['harbor ']);
assert.equal(sectionCalls,1);assert.deepEqual(toggledSources,[]);
console.log('4 pinned section-admission cases passed (actual generator and funbox functions; authored provider responses distinguish empty generation failure from requested source-disable on fetch failure; toggle recorder is not setter-admission evidence; no parser/HTTP/UI/recovery equivalence claim).');
// Execute the complete actual addWord function, not a paraphrase of its branch
// conditions. Its surrounding module/startup is deliberately outside this
// probe. The exact pinned source range is read only and remains in memory.
const logicSource=fs.readFileSync(path.join(root,'frontend/src/ts/test/test-logic.ts'),'utf8');
const addStart=logicSource.indexOf('export async function addWord(): Promise<void> {');
const addEnd=logicSource.indexOf('\ntype RetrySaving = {',addStart);
assert.ok(addStart>=0&&addEnd>addStart,'Pinned complete addWord range must exist');
const addBody=stripTypeScriptTypes(logicSource.slice(addStart,addEnd),{mode:'transform'})
  .replace(/^export /,'');
const testWords=modules.get('test/test-words').namespace;
let restarts=0;
const failures=[],notices=[],displayed=[];
const addWord=vm.compileFunction(addBody+'\nreturn addWord;',[
  'Config','TestWords','WordsGenerator','TestUI','getActiveFunboxes','getActiveWordIndex',
  'findSingleActiveFunboxWithFunction','showErrorNotification','toggleFunbox','restart','timerEvent',
])(config,testWords,main.namespace,
  {addWord:word=>displayed.push(word),appendEmptyWordElement:unexpected},active,()=>ownedActiveWordIndex,
  name=>active().find(value=>typeof value.functions[name]==='function'),
  (...args)=>notices.push(args),bindings['config/setters'].toggleFunbox,
  async()=>{restarts++},{dispatch:value=>failures.push(value)});
config.words=50;
for(const fixture of [
  {name:'empty with retained generator tail',tail:['retained'],responses:[{words:[]}],calls:1,added:['retained'],fails:0,restarts:0,disabled:false},
  {name:'empty then valid generator section',tail:[],responses:[{words:[]},{words:['fresh']}],calls:2,added:['fresh'],fails:0,restarts:0,disabled:false},
  {name:'empty then empty generator section',tail:[],responses:[{words:[]},{words:[]}],calls:2,added:[],fails:1,restarts:0,disabled:false},
  {name:'false prefetch with retained tail',tail:['retained'],responses:[false],calls:1,added:[],fails:0,restarts:1,disabled:true},
  {name:'undefined prefetch with retained tail',tail:['retained'],responses:[undefined],calls:1,added:[],fails:0,restarts:0,disabled:false},
  {name:'valid prefetch still consumes generator tail',tail:['retained'],responses:[{words:['first','second']}],calls:1,added:['first','second','retained'],fails:0,restarts:0,disabled:false},
]){
  testWords.words.reset();testWords.words.push('opening ',0);
  main.namespace.currentSection.splice(0,main.namespace.currentSection.length,...fixture.tail);
  ownedSectionQueue=[...fixture.responses];ownedSection=undefined;
  sectionCalls=0;restarts=0;toggledSources.length=0;
  failures.length=0;notices.length=0;displayed.length=0;
  await addWord();
  assert.equal(sectionCalls,fixture.calls,fixture.name);
  assert.deepEqual(testWords.words.get().slice(1).map(word=>word.text),fixture.added,fixture.name);
  assert.deepEqual(displayed,fixture.added,fixture.name);
  assert.equal(failures.length,fixture.fails,fixture.name);
  if(fixture.fails) assert.deepEqual(failures,[{key:'fail',value:'word generation error'}]);
  assert.equal(restarts,fixture.restarts,fixture.name);
  assert.deepEqual(toggledSources,fixture.disabled?['poetry']:[],fixture.name);
  assert.equal(notices.length,fixture.fails+fixture.restarts,fixture.name);
  assert.equal(ownedSectionQueue.length,0,fixture.name);
}
console.log('6 pinned complete-addWord cases passed with actual generator/functions/word storage (owned provider, UI, active index, notification and timer boundaries; no full test-logic module, HTTP, DOM or native recovery equivalence claim).');
config.words=103;
testWords.words.reset();
for(let i=0;i<100;i++)testWords.words.push(`owned${i} `,0);
main.namespace.currentSection.splice(0,main.namespace.currentSection.length,'north\nsouth','e\u0301','tail');
sectionCalls=0;displayed.length=0;failures.length=0;toggledSources.length=0;
for(let i=0;i<3;i++){
  // word-navigation calls addWord before increasing the active index.
  ownedActiveWordIndex=i;
  await addWord();
  assert.equal(testWords.words.length,101+i);
  assert.equal(main.namespace.currentSection.length,2-i);
  assert.equal(sectionCalls,0,'A retained generator tail supplies one new field per forward transition');
}
assert.deepEqual(displayed,['north\nsouth','e\u0301','tail']);
assert.equal(testWords.words.get(102).commit,'','Final finite target has no commit');
assert.deepEqual(failures,[]);assert.deepEqual(toggledSources,[]);
ownedActiveWordIndex=3;
await addWord();
assert.equal(testWords.words.length,103);assert.equal(sectionCalls,0);
console.log('Pinned sequential forward-tail case passed (100 published fields plus 3 retained fields; actual addWord/generator/storage, owned forward index; no navigation or physical-input execution claim).');
// Generator demand is distinct from the <20-field side pull. A full visible
// window can still require the generator to acquire its next retained section.
config.words=300;ownedActiveWordIndex=0;
for(const fixture of [
  {name:'empty generator with full visible window',published:100,response:{words:['fresh','later']},calls:1,added:['fresh'],tail:['later'],fails:0,disabled:false},
  {name:'empty generator with inclusive future bound',published:101,response:{words:['fresh','later']},calls:1,added:['fresh'],tail:['later'],fails:0,disabled:false},
  {name:'future window beyond bound',published:102,response:{words:['unused']},calls:0,added:[],tail:[],fails:0,disabled:false},
  {name:'successful empty generator pull',published:100,response:{words:[]},calls:1,added:[],tail:[],fails:1,disabled:false},
  {name:'false generator pull',published:100,response:false,calls:1,added:[],tail:[],fails:1,disabled:true},
  {name:'undefined generator pull',published:100,response:undefined,calls:1,added:[],tail:[],fails:1,disabled:true},
]){
  testWords.words.reset();
  for(let i=0;i<fixture.published;i++)testWords.words.push(`owned${i} `,0);
  main.namespace.currentSection.splice(0,main.namespace.currentSection.length);
  ownedSection=fixture.response;ownedSectionQueue=[];sectionCalls=0;restarts=0;
  displayed.length=0;failures.length=0;notices.length=0;toggledSources.length=0;
  await addWord();
  assert.equal(sectionCalls,fixture.calls,fixture.name);
  assert.deepEqual(displayed,fixture.added,fixture.name);
  assert.deepEqual(testWords.words.get().slice(fixture.published).map(word=>word.text),fixture.added,fixture.name);
  assert.deepEqual([...main.namespace.currentSection],fixture.tail,fixture.name);
  assert.deepEqual(failures,fixture.fails?[{key:'fail',value:'word generation error'}]:[],fixture.name);
  assert.deepEqual(toggledSources,fixture.disabled?['poetry']:[],fixture.name);
  assert.equal(notices.length,fixture.fails,fixture.name);
  assert.equal(restarts,0,fixture.name);
}
console.log('6 pinned generator-demand cases passed (100/101/102 published fields; real addWord/generator/storage; authored provider and UI boundaries, toggle recorder is not actual setter admission; no HTTP/navigation/device equivalence claim).');
testWords.words.reset();
for(let i=0;i<100;i++)testWords.words.push(`owned${i} `,0);
main.namespace.currentSection.splice(0,main.namespace.currentSection.length,'lastRetained');
ownedSection={words:['fresh','later']};ownedSectionQueue=[];sectionCalls=0;displayed.length=0;
ownedActiveWordIndex=0;
await addWord();
assert.equal(sectionCalls,0,'Consuming the last retained field does not itself pull a new section');
assert.equal(main.namespace.currentSection.length,0);
ownedActiveWordIndex=1;
await addWord();
assert.equal(sectionCalls,1,'The next forward action sees an already-empty pool and pulls');
assert.deepEqual(displayed,['lastRetained','fresh']);
assert.deepEqual([...main.namespace.currentSection],['later']);
console.log('Pinned last-retained-field transition passed (no pull while consuming the tail; next forward action pulls exactly once; owned active-index boundary, not complete navigation execution).');
// The earlier recorder boundaries prove requests to toggle/restart, not that
// those requests are admitted. Execute both complete pinned functions on the
// active no_quit path; unknown downstream dependencies remain unresolved so
// crossing either guard fails instead of inventing successful mutation.
const settersSource=fs.readFileSync(path.join(root,'frontend/src/ts/config/setters.ts'),'utf8');
const toggleStart=settersSource.indexOf('export function toggleFunbox(');
assert.ok(toggleStart>=0);
const toggleBody=stripTypeScriptTypes(settersSource.slice(toggleStart),{mode:'transform'}).replace(/^export /,'');
const restartStart=logicSource.indexOf('export async function restart(');
const restartEnd=logicSource.indexOf('\nlet lastInitError:',restartStart);
assert.ok(restartStart>=0&&restartEnd>restartStart);
const restartBody=stripTypeScriptTypes(logicSource.slice(restartStart,restartEnd),{mode:'transform'}).replace(/^export /,'');
const guardNotices=[];
config.funbox=['poetry','no_quit'];config.words=50;ownedActiveWordIndex=0;
const activeToggle=vm.compileFunction(toggleBody+'\nreturn toggleFunbox;',
  ['Config','isTestActive','showNoticeNotification'])(config,()=>true,(...args)=>guardNotices.push(args));
const activeRestart=vm.compileFunction(restartBody+'\nreturn restart;',
  ['isTestActive','isFunboxActive','showNoticeNotification'])(()=>true,
  name=>config.funbox.includes(name),(...args)=>guardNotices.push(args));
const guardedAddWord=vm.compileFunction(addBody+'\nreturn addWord;',[
  'Config','TestWords','WordsGenerator','TestUI','getActiveFunboxes','getActiveWordIndex',
  'findSingleActiveFunboxWithFunction','showErrorNotification','toggleFunbox','restart','timerEvent',
])(config,testWords,main.namespace,
  {addWord:word=>displayed.push(word),appendEmptyWordElement:unexpected},active,()=>ownedActiveWordIndex,
  name=>active().find(value=>typeof value.functions[name]==='function'),
  (...args)=>notices.push(args),activeToggle,activeRestart,{dispatch:value=>failures.push(value)});
testWords.words.reset();testWords.words.push('opening ',0);
main.namespace.currentSection.splice(0,main.namespace.currentSection.length,'retained');
ownedSection=false;ownedSectionQueue=[];sectionCalls=0;
notices.length=0;failures.length=0;displayed.length=0;
await guardedAddWord();
assert.equal(sectionCalls,1);
assert.deepEqual(config.funbox,['poetry','no_quit'],'Actual active NoQuit setter keeps the source enabled');
assert.equal(guardNotices.length,2,'Both toggle and restart reject the active NoQuit attempt');
assert.equal(notices.length,1,'The section-fetch error is still reported');
assert.deepEqual(failures,[],'False prefetch does not dispatch a generation failure');
assert.deepEqual(displayed,[]);assert.equal(testWords.words.length,1);
assert.deepEqual([...main.namespace.currentSection],['retained']);
ownedSection={words:['first','second']};
await guardedAddWord();
assert.equal(sectionCalls,2);
assert.deepEqual(displayed,['first','second','retained'],
  'A later valid response can append its section and the preserved generator tail');
assert.equal(testWords.words.length,4);assert.deepEqual(failures,[]);
assert.deepEqual(config.funbox,['poetry','no_quit']);assert.equal(guardNotices.length,2);
console.log('Pinned active-NoQuit false-prefetch case passed (complete actual addWord/toggleFunbox/restart functions, real generator/storage; owned active/config/notification boundaries; no full event bus, UI or backend execution claim).');
