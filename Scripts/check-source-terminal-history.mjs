// Owned fixtures run the complete pinned stats/helpers/strings/numbers modules.
// No source is copied into the implementation. No browser or input handler runs.
// Config/key types are adapters; Korean disassembly is intentionally unsupported.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs'; import path from 'node:path'; import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const reference=path.resolve(process.argv[2]??'');
if(!process.argv[2] || execFileSync('git',['-C',reference,'rev-parse','HEAD'],{encoding:'utf8'}).trim()!=='91bd24bb8513785c7364cbea29296ff7adafac41')throw Error('Pinned checkout required');
if(execFileSync('git',['-C',reference,'status','--porcelain'],{encoding:'utf8'}).trim())throw Error('Reference must be clean');
const actual=new Set(['test/events/stats','test/events/helpers','utils/strings','utils/numbers']);
const bindings={'config/store':{Config:{funbox:[]}},'constants/keys':{Keycode:{}},'@monkeytype/schemas/languages':{Language:{}},
 '@monkeytype/util/numbers':{roundTo2:v=>Math.round(v*100)/100},
 'test/events/types':{InputEventNoMs:{},TestEventNoMs:{},EventLog:{}},
 'hangul-js':{default:{disassemble:()=>{throw Error('Korean is outside this probe')}}}};
const modules=new Map();
function moduleFor(id){
 if(modules.has(id))return modules.get(id);
 // Single-file stripping cannot resolve an imported erased type. Remove
 // only this type name, leaving every source behavior function intact.
 const source=actual.has(id)?fs.readFileSync(path.join(reference,'frontend/src/ts',id+'.ts'),'utf8').replace('import { CharCounts, countChars, isSpace }','import { countChars, isSpace }'):null;
 const mod=source!==null?new vm.SourceTextModule(stripTypeScriptTypes(source,{mode:'transform'}),{identifier:id}):
  new vm.SyntheticModule(Object.keys(bindings[id]??{}),function(){if(!bindings[id])throw Error('Unknown binding '+id);for(const[k,v]of Object.entries(bindings[id]))this.setExport(k,v)},{identifier:id});
 modules.set(id,mod);return mod;
}
const main=moduleFor('test/events/stats');
await main.link((id,from)=>moduleFor(id.startsWith('.')?path.posix.normalize(path.posix.join(path.posix.dirname(from.identifier),id)):id));await main.evaluate();
const stats=main.namespace; const helpers=modules.get('test/events/helpers').namespace;
const event=(testMs,wordIndex,inputValue,inputType='insertText',data='b',extra={})=>({type:'input',testMs,data:{inputType,wordIndex,inputValue,data,correct:true,...extra}});
const log=(events,targetWords=['ab','cd'])=>({events,context:{mode:'custom',mode2:'2',customTextLimitMode:'none',customTextLimitValue:2,bailedOut:true,koreanStatus:false,targetWords}});
const opening=[event(0,0,'ab'),event(0,1,'cd','insertText','d')];
const later=log([...opening,event(1000,0,'a','deleteContentBackward','',{clearedNextWord:true})]);
assert.equal(helpers.getInputFromDom(helpers.getEventsForWord(later.events,1)),'cd');
assert.deepEqual(stats.getInputHistory(later),['a','']);
assert.deepEqual(stats.getChars(later),{allCorrect:3,correctWord:2,incorrect:0,extra:0,missed:1});
assert.equal(stats.__testing.inferActiveWordIndex(helpers.getEventsPerWord(later.events)),1);
const equal=log([...opening,event(0,0,'a','deleteContentBackward','',{clearedNextWord:true})]);
assert.deepEqual(stats.getInputHistory(equal),['a','cd']);
assert.equal(stats.getChars(equal).correctWord,2);
const reentry=log([...later.events,event(2000,0,'ab'),event(3000,1,'c','insertText','c')]);
assert.deepEqual(stats.getInputHistory(reentry),['ab','c']);
assert.equal(stats.getChars(reentry).correctWord,3);
const emoji=log([event(0,0,'ab'),event(0,1,'🙂'),event(1000,0,'a','deleteContentBackward','',{clearedNextWord:true})],['ab','🙂']);
assert.equal(stats.getChars(emoji).allCorrect,3);assert.equal(stats.getChars(emoji).correctWord,2);
assert.deepEqual(stats.getInputHistory(emoji),['a','']);
const cleared=log([...opening,event(1000,0,'','deleteWordBackward','',{clearedNextWord:true})]);
assert.deepEqual(stats.getInputHistory(cleared),['','']);
assert.equal(stats.getChars(cleared).correctWord,2);
const stopped=log([...later.events,event(2000,0,'ab'),event(3000,1,'','insertText','x',{inputStopped:true,correct:false})]);
assert.equal(stats.getChars(stopped).correctWord,2);assert.equal(stats.getChars(stopped).allCorrect,2);
assert.deepEqual(stats.getInputHistory(stopped),['ab','']);
console.log('6 pinned-source terminal-history fixtures passed (4 complete actual modules; adapters, no browser/handler/Korean parity claim).');
const classificationCases=[
 ['ab','ab',false,[2,2,0,0,0]], ['ax ','ab ',false,[1,0,1,1,0]],
 ['ab','ab ',false,[2,0,0,0,1]], ['abx','ab ',false,[2,0,0,1,0]],
 ['ab ','ab cd',true,[2,3,0,1,0]], ['ax','abcd',true,[1,0,1,0,0]],
 ['ax','abcd',false,[1,0,1,0,2]], ['abxx','ab',true,[2,0,0,2,0]],
 ['','abcd',false,[0,0,0,0,4]], ['','abcd',true,[0,0,0,0,0]],
 ['🙂','🙂',false,[2,2,0,0,0]], ['e\u0301','e\u0301b',true,[2,2,0,0,0]],
 ['a\n','ab\n',false,[1,0,1,0,1]], ['x y','ab ',false,[0,0,3,0,0]],
 ['\ud83d','🙂',true,[1,1,0,0,0]], ['\ud83d','🙂',false,[1,0,0,0,1]],
];
for(const [input,target,partial,expected] of classificationCases){
 const result=modules.get('utils/strings').namespace.countChars(input,target,partial);
 assert.deepEqual([result.allCorrect,result.correctWord,result.incorrect,result.extra,result.missed],expected);
 assert.equal(result.allCorrect+result.incorrect+result.extra,input.length);
}
const normalizedSpace=log([event(0,0,'a\u3000')],['a ']);
assert.deepEqual(stats.getChars(normalizedSpace),{allCorrect:2,correctWord:2,incorrect:0,extra:0,missed:0});
const absentTarget=log([event(0,7,'a\u3000')],['ab']);
assert.deepEqual(stats.getChars(absentTarget),{allCorrect:2,correctWord:2,incorrect:0,extra:0,missed:0});
const knownEmptyTarget=log([event(0,0,'a\u3000')],['']);
assert.deepEqual(stats.getChars(knownEmptyTarget),{allCorrect:0,correctWord:0,incorrect:0,extra:2,missed:0});
const failedInfinite=log([event(0,0,'ax')],['abcd']);
failedInfinite.context.mode='words'; failedInfinite.context.mode2='0'; failedInfinite.context.bailedOut=false;
assert.deepEqual(stats.getChars(failedInfinite),{allCorrect:1,correctWord:0,incorrect:1,extra:0,missed:0});
failedInfinite.context.mode2='1';
assert.deepEqual(stats.getChars(failedInfinite),{allCorrect:1,correctWord:0,incorrect:1,extra:0,missed:2});
console.log('21 owned UTF-16 classification fixtures passed (16 countChars cases and 5 normalized/fallback/mode getChars cases; result.ts/TestLogic display inspected, not executed).');
