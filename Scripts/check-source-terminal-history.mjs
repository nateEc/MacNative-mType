// Owned fixtures run the complete pinned stats/helpers/strings/numbers modules.
// No source is copied into the implementation. No browser or input handler runs.
// Config/key types are adapters. An optional external, integrity-checked
// dependency is a read-only oracle, never a native or packaged dependency.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs'; import path from 'node:path'; import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const reference=path.resolve(process.argv[2]??'');
if(!process.argv[2] || execFileSync('git',['-C',reference,'rev-parse','HEAD'],{encoding:'utf8'}).trim()!=='91bd24bb8513785c7364cbea29296ff7adafac41')throw Error('Pinned checkout required');
if(execFileSync('git',['-C',reference,'status','--porcelain'],{encoding:'utf8'}).trim())throw Error('Reference must be clean');
const actual=new Set(['test/events/stats','test/events/helpers','utils/strings','utils/numbers','@monkeytype/util/numbers']);
let koreanOracle;
if(process.argv[3]){
 const root=path.resolve(process.argv[3]);
 const locked=fs.readFileSync(path.join(reference,'pnpm-lock.yaml'),'utf8')
  .match(/hangul-js@0\.2\.6:\r?\n\s+resolution: \{integrity: sha512-([^}]+)\}/)?.[1];
 assert.ok(locked,'Pinned dependency integrity required');
 assert.equal(crypto.createHash('sha512').update(fs.readFileSync(path.join(root,'hangul-js-0.2.6.tgz'))).digest('base64'),locked);
 const code=fs.readFileSync(path.join(root,'package/hangul.js'));
 assert.equal(crypto.createHash('sha256').update(code).digest('hex'),'94362dfdd81723a3cb94e5d27c7c0ef09b6949dc25002ecc06aff5448602bfc8');
 assert.equal(JSON.parse(fs.readFileSync(path.join(root,'package/package.json'),'utf8')).version,'0.2.6');
 const sandbox={module:{exports:{}}};
 vm.runInNewContext(code.toString('utf8'),sandbox,{timeout:1000,filename:'external-hangul-js-0.2.6'});
 koreanOracle=sandbox.module.exports;
}
const bindings={'config/store':{Config:{funbox:[]}},'constants/keys':{Keycode:{}},'@monkeytype/schemas/languages':{Language:{}},
 'test/events/types':{InputEventNoMs:{},TestEventNoMs:{},EventLog:{}},
 'hangul-js':{default:koreanOracle??{disassemble:()=>{throw Error('Korean is outside this probe')}}}};
const modules=new Map();
function moduleFor(id){
 if(modules.has(id))return modules.get(id);
 // Single-file stripping cannot resolve an imported erased type. Remove
 // only this type name, leaving every source behavior function intact.
 const source=actual.has(id)?fs.readFileSync(id==='@monkeytype/util/numbers'
  ?path.join(reference,'packages/util/src/numbers.ts'):path.join(reference,'frontend/src/ts',id+'.ts'),'utf8')
  .replace('import { CharCounts, countChars, isSpace }','import { countChars, isSpace }'):null;
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
console.log('6 pinned-source terminal-history fixtures passed (5 complete actual modules; adapters, no browser/handler/Korean parity claim).');
const numbers=modules.get('@monkeytype/util/numbers').namespace;
const consistencyOf=history=>{
 const value=numbers.roundTo2(numbers.kogasa(numbers.stdDev(history)/numbers.mean(history)));
 return Number.isNaN(value)?0:value;
};
const cadenceCases=[
 [[event(0,0,'a','insertText','a'),event(1200,0,'ab','insertText','b'),event(2200,0,'abc','insertText','c')],['abc'],3000,100,100],
 [[event(0,0,'x','insertText','x',{correct:false}),event(500,0,'','deleteContentBackward',''),event(1200,0,'a','insertText','a')],['ab'],2000,8.9,100],
 [[event(0,0,'a','insertText','a')],['a'],150000,0,0],
 [[event(0,0,'ab ','insertText',' ',{lastWord:true,commitsWord:true,correct:false})],['ab'],2000,66.67,8.9],
 [[event(0,0,'a','insertText','a'),event(1500,0,'ab','insertText','b')],['ab'],3500,76.64,8.9],
 [[event(0,0,'a','insertText','a')],['a'],24000,2.72,0],
];
for(const [events,targets,duration,wpmExpected,burstExpected] of cadenceCases){
 const value=log([...events,{type:'timer',testMs:duration,data:{event:'end'}}],targets);
 value.context.mode='words';value.context.mode2='1';value.context.bailedOut=false;
 const wpm=stats.getWpmHistory(value),burst=stats.getBurstHistory(value);
 assert.equal(consistencyOf(wpm),wpmExpected);
 assert.equal(consistencyOf(burst),burstExpected);
}
const longCadence=log([...Array.from({length:122},(_,i)=>event(i*1000,0,'a'.repeat(i+1),'insertText','a')),
 event(122100,0,'','deleteWordBackward',''),{type:'timer',testMs:150000,data:{event:'end'}}],['a'.repeat(150)]);
longCadence.context.mode='words';longCadence.context.mode2='1';longCadence.context.bailedOut=false;
assert.equal(consistencyOf(stats.getWpmHistory(longCadence)),50.72);
const heapCadence=log([event(0,1,'b','insertText','b'),event(1200,0,'a ','insertText',' '),
 event(2200,1,'','deleteContentBackward',''),event(3200,2,'c','insertText','c'),
 event(4200,2,'','deleteContentBackward',''),event(5200,1,'b ','insertText',' '),
 event(6200,2,'c','insertText','c'),{type:'timer',testMs:7000,data:{event:'end'}}],['a ','b ','c']);
heapCadence.context.mode='words';heapCadence.context.mode2='1';heapCadence.context.bailedOut=false;
assert.deepEqual(stats.getWpmHistory(heapCadence),[12,6,0,9,0,8,9]);
console.log('8 input-cadence versus WPM-consistency fixtures passed (5 complete modules, including actual util statistics; seeded context, no full buildCompletedEvent execution).');
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

// Zen has an empty target directory, not a directory built from final text.
// These are source stats fixtures, not evidence for physical Zen input/IME.
const zenLog=events=>{
 const value=log(events,[]);
 value.context.mode='zen'; value.context.mode2='zen'; value.context.bailedOut=false;
 return value;
};
const zenCases=[
 [[event(0,0,'🙂 ','insertText',' ',{commitsWord:true}),event(1000,1,'e\u0301','insertText','\u0301')],5],
 [[event(0,0,'','insertText','x',{inputStopped:true}),event(1000,0,'a','insertText','a')],1],
 [[event(0,0,'','insertText','x',{inputStopped:true})],0],
 [[event(0,0,'a\n','insertText','\n',{commitsWord:true}),event(1000,1,'\n','insertText','\n',{commitsWord:true}),event(1500,2,'b')],4],
 [[event(0,0,'ab ','insertText',' ',{lastWord:true,commitsWord:true})],3],
 [[event(0,0,'가 ','insertText',' ',{commitsWord:true}),event(1000,1,'🙂')],4],
 [[event(0,0,'a\u3000','insertText','\u3000')],2],
 [[event(0,0,'ab ','insertText',' ',{commitsWord:true}),event(500,1,'c'),event(1000,1,'','deleteContentBackward','')],3],
 [[event(0,0,'ab ','insertText',' ',{commitsWord:true}),event(500,1,'c'),event(1000,1,'','deleteContentBackward',''),event(1500,1,'d')],4],
 [[event(0,0,'ab ','insertText',' ',{commitsWord:true}),event(1000,1,'\t🙂')],6],
];
for(const [events,count] of zenCases){
 assert.deepEqual(stats.getChars(zenLog(events)),{allCorrect:count,correctWord:count,incorrect:0,extra:0,missed:0});
}
console.log('10 owned target-free Zen getChars fixtures passed (same 5 complete actual modules; Korean status false, no handler/browser/IME claim).');

const ordinaryCases=[
 [[event(0,0,'ax ','insertText',' ',{commitsWord:true}),event(1000,1,'cd')],['ab ','cd'],[3,2,1,1,0]],
 [[event(0,0,'ab ','insertText',' ',{lastWord:true,commitsWord:true,correct:false})],['ab'],[2,2,0,0,0]],
 [[event(0,0,'ax ','insertText',' ',{lastWord:true,commitsWord:true,correct:false})],['ab'],[1,0,1,0,0]],
 [[event(0,0,'a ','insertText',' ',{commitsWord:true,correct:false}),event(1000,1,'ef')],['abcd ','ef'],[3,2,1,0,3]],
 [[event(0,0,'a','insertText',' ',{lastWord:true,inputStopped:true,correct:false})],['ab'],[1,0,0,0,1]],
 [[event(0,0,'ax ','insertText',' ',{lastWord:true,correct:false})],['ab'],[1,0,1,1,0]],
 [[event(0,0,'🙂 ','insertText',' ',{commitsWord:true}),event(1000,1,'e\u0301')],['🙂 ','e\u0301'],[5,5,0,0,0]],
 [[event(0,0,'ab\n','insertText','\n',{commitsWord:true}),event(1000,1,'\n','insertText','\n',{commitsWord:true}),event(1500,2,'cd')],['ab\n','\n','cd'],[6,6,0,0,0]],
 [[event(0,0,'ab ','insertText',' ',{lastWord:true,commitsWord:true,correct:false}),event(1000,0,'x')],['ab'],[0,0,1,0,0]],
 [[event(0,0,'a\ud83d\uFEFF ','insertText',' ',{lastWord:true,commitsWord:true,correct:false})],['a\ud83d'],[2,2,0,0,0]],
 [[event(0,0,'a\u0085 ','insertText',' ',{lastWord:true,commitsWord:true,correct:false})],['a'],[1,0,0,1,0]],
];
for(const [events,targets,expected] of ordinaryCases){
 const result=stats.getChars(log(events,targets));
 assert.deepEqual([result.allCorrect,result.correctWord,result.incorrect,result.extra,result.missed],expected);
}
console.log('11 owned ordinary getChars fixtures passed (same 5 actual modules; includes stopped SPACE active inference and source trim, no browser/IME/Korean claim).');
const terminalSpace=log([event(0,0,'ab ','insertText',' ',{lastWord:true,commitsWord:true,correct:false})],['ab']);
terminalSpace.context.bailedOut=false;
const terminalChars=stats.getChars(terminalSpace);
assert.equal(modules.get('utils/numbers').namespace.calculateWpm(terminalChars.correctWord,1),24);
assert.equal(modules.get('utils/numbers').namespace.calculateWpm(terminalChars.allCorrect+terminalChars.incorrect+terminalChars.extra,1),24);
console.log('Ordinary terminal SPACE WPM/Raw numerators passed actual getChars + calculateWpm (buildCompletedEvent mapping read, full lifecycle not executed).');

if(koreanOracle){
 const hash=crypto.createHash('sha256');
 for(let unit=0;unit<=0xffff;unit++){
  const result=koreanOracle.disassemble(String.fromCharCode(unit)).join('');
  const tuple=Buffer.alloc(4+2*result.length);
  tuple.writeUInt16LE(unit,0);tuple.writeUInt16LE(result.length,2);
  for(let i=0;i<result.length;i++)tuple.writeUInt16LE(result.charCodeAt(i),4+2*i);
  hash.update(tuple);
 }
 const fingerprint=hash.digest('hex');
 assert.equal(fingerprint,'3ce3e56e227e9d618cd7b00e63c65ffd783807a110e071bde31d1172d05144a7');
 console.log('Korean complete-BMP oracle fingerprint (65536 single-unit inputs): '+fingerprint);
 const cases=[
  ['각','각',true,[3,3,0,0,0]],['가','각',true,[2,2,0,0,0]],
  ['가','각',false,[2,0,0,0,1]],['갃','갃',true,[4,4,0,0,0]],
  ['괅','괅',true,[5,5,0,0,0]],['갂','갂',true,[3,3,0,0,0]],
  ['ㄲㅄㅙ','ㄲㅄㅙ',true,[5,5,0,0,0]],['가','가',true,[0,0,2,0,0]],
  ['가🙂','가🙂',true,[4,4,0,0,0]],['가\ud83d','가\ud83d',true,[3,3,0,0,0]],
  ['가\u3000','가 ',true,[3,3,0,0,0]],['\ud83d','🙂',false,[1,0,0,0,1]],
 ];
 for(const [input,target,partial,expected]of cases){
  const value=log([event(0,0,input)],[target]);
  value.context.koreanStatus=true;value.context.bailedOut=partial;
  const result=stats.getChars(value);
  assert.deepEqual([result.allCorrect,result.correctWord,result.incorrect,result.extra,result.missed],expected);
 }
 console.log('12 Korean getChars fixtures passed (5 complete source modules + verified complete hangul-js 0.2.6; seeded context, no IME/state-capture/native-publication parity claim).');
 const historyCases=[
  [[event(0,0,'괅','insertText','괅')],['괅'],2000,[60,30],[60,30],[12,0],[0,0]],
  [[event(0,0,'가','insertText','가',{correct:false}),event(1500,0,'각','insertText','각')],
   ['각'],3500,[24,18,12,10],[24,18,12,10],[12,12,0,0],[1,0,0,0]],
  [[event(0,0,'괅 ','insertText',' ',{lastWord:true,commitsWord:true,correct:false})],
   ['괅'],2000,[60,30],[60,30],[12,0],[1,0]],
  [[event(0,0,'가','insertText',' ',{lastWord:true,inputStopped:true,correct:false})],
   ['각'],2000,[0,0],[24,12],[12,0],[1,0]],
  [[event(0,0,'괅x'),event(500,1,'가'),event(1500,0,'괅','deleteContentBackward','',{clearedNextWord:true})],
   ['괅x','가'],2000,[96,12],[96,42],[24,0],[0,0]],
  [[event(0,0,'가\ud83d','insertText','\ud83d',{correct:false})],
   ['가🙂'],2000,[36,18],[36,18],[12,0],[1,0]],
  [[event(0,1,'가','insertText','가'),event(500,0,'괅 ','insertText',' ')],
   ['괅 ','가'],2000,[24,12],[24,12],[24,0],[0,0]],
 ];
 for(const [events,targets,duration,wpm,raw,burst,errors] of historyCases){
  const value=log([...events,{type:'timer',testMs:duration,data:{event:'end'}}],targets);
  value.context.koreanStatus=true;value.context.mode='words';value.context.mode2='1';value.context.bailedOut=false;
  assert.deepEqual(stats.getWpmHistory(value),wpm);
  assert.deepEqual(stats.getRawHistory(value),raw);
  assert.deepEqual(stats.getBurstHistory(value),burst);
  assert.deepEqual(stats.getErrorCountHistory(value),errors);
 }
 console.log('7 Korean WPM/Raw/Burst/error history fixtures passed (complete source functions and verified oracle; synthetic end timer, seeded context, no physical IME or real timer claim).');
}
