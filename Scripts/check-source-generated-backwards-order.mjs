// Read-only complete pinned generator/functions/wordset modules. GetText,
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
const actual=new Set(['test/words-generator','test/funbox/funbox-functions','test/wordset']);
const config={mode:'words',words:3,language:'english',showAllLines:false,lazyMode:false,
  punctuation:false,numbers:false,britishEnglish:false};
let activeNames=['backwards','binary'], functions, drawIndex=0;
const binary=i=>(i%256).toString(2).padStart(8,'0');
const unexpected=()=>{throw Error('Unexpected adapter call outside ordering probe')};
const active=()=>activeNames.map(name=>({name,properties:name==='backwards'?['wordOrder:reverse']:
  name==='underscore_spaces'?['nospace']:[],functions:functions[name]}));
const arrays={randomElementFromArray:words=>words[0],shuffle:unexpected,
  nthElementFromArray:(words,index)=>words.at(index)};
const bindings={
  'config/store':{Config:config},
  'test/custom-text':{getPipeDelimiter:()=>false},
  'test/practise-words':{before:{mode:null}},
  'controllers/quotes-controller':{default:{}},
  'states/test':{isRepeated:()=>false,getCurrentQuote:()=>null,setCurrentQuote:()=>{},getSelectedQuoteId:()=>null},
  'test/funbox/list':{
    getActiveFunboxes:active,
    getActiveFunboxesWithFunction:name=>active().filter(value=>typeof value.functions[name]==='function'),
    findSingleActiveFunboxWithFunction:name=>active().find(value=>typeof value.functions[name]==='function'),
    isFunboxActiveWithFunction:name=>active().some(value=>typeof value.functions[name]==='function'),
    isFunboxActiveWithProperty:name=>active().some(value=>value.properties.includes(name)),
  },
  'utils/arrays':arrays,
  'utils/misc':{zipfyRandomArrayIndex:unexpected},
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
console.log('4 generated-backwards ordering fixtures passed (3 complete actual modules; GetText/random/config/metadata/UI adapters, no RNG, corpus, browser or layout parity claim).');
