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
