// Owned, bounded VM harness: loads official modules from disk; never copies them.
// Run with Node supporting stripTypeScriptTypes and --experimental-vm-modules.
// UI/layout, config, catalog generation and lifecycle are explicit test bindings.
// The textarea is an in-memory sentinel adapter, NOT a browser or real IME.
// Passing proves these source observations, not native parity or full UI behavior.
import assert from 'node:assert/strict'; import {execFileSync} from 'node:child_process'; import fs from 'node:fs'; import path from 'node:path'; import vm from 'node:vm'; import {stripTypeScriptTypes} from 'node:module';
const reference=path.resolve(process.argv[2] ?? '');
if (!process.argv[2] || execFileSync('git',['-C',reference,'rev-parse','HEAD'],{encoding:'utf8'}).trim() !== '91bd24bb8513785c7364cbea29296ff7adafac41') throw new Error('Provide the pinned read-only reference checkout.');
if (execFileSync('git',['-C',reference,'status','--porcelain'],{encoding:'utf8'}).trim()) throw new Error('Reference checkout must be clean.');
const root=path.join(reference,'frontend/src/ts'); const actual=new Set(['utils/strings','input/helpers/util','input/helpers/validation','input/helpers/fail-or-finish','input/handlers/before-insert-text','input/handlers/insert-text','input/helpers/word-navigation','input/input-element','test/events/data','test/events/helpers','test/events/live-cache']);
let browserDeletedSentinel=false;
let growNext=false;let wordIndex=0,targets=[]; let element='',field='',target='',active=false,events=[],feedback=[],failed=false,completed=false; const noop=()=>{};
const Config={mode:'words',language:'english',oppositeShiftMode:'off',stopOnError:'off',deleteOnError:'off',difficulty:'normal',strictSpace:false,blindMode:true,hideExtraLetters:false,keymapMode:'off',minBurst:'off',liveBurstStyle:'off',confidenceMode:'off',freedomMode:false,quickEnd:false};
const bindings={
'config/store':{Config},'test/funbox/list':{isFunboxActiveWithProperty:()=>false,getActiveFunboxesWithFunction:()=>[]},
'input/input-element':{getInputElementValue:()=>({inputValue:element,realInputValue:' '+element}),setInputElementValue:v=>{element=v},appendToInputElementValue:v=>{element+=v},replaceInputElementLastValueChar:v=>{element=element.slice(0,-1)+v}},
 'test/events/data':{getCurrentInput:()=>events.filter(e=>e.wordIndex===wordIndex).at(-1)?.inputValue??'',getInputForWord:i=>events.filter(e=>e.wordIndex===i).at(-1)?.inputValue??'',buildEventLog:noop,logTestEvent:(type,now,event)=>{events.push({...event,time:now});field=event.inputValue}},
 'test/test-words':{words:{getCurrent:()=>({textWithCommit:targets[wordIndex]??'',text:targets[wordIndex]??'',display:targets[wordIndex]??''}),get:i=>targets[i]===undefined?undefined:{textWithCommit:targets[i],text:targets[i]},get length(){return targets.length}}},
 'test/test-ui':{afterTestTextInput:correct=>feedback.push(correct),pendingWordData:new Map(),getWordElement:()=>({}),beforeTestWordChange:noop,afterTestWordChange:noop,afterTestDelete:noop,
  // Bounded no-wrap geometry only; never browser layout evidence.
  activeWordTop:0,activeWordHeight:1,getActiveWordTopAndHeightWithDifferentData:()=>({top:0,height:1})},
 'input/state':{setAwaitingNextWord:noop,isAwaitingNextWord:()=>false,isCorrectShiftUsed:()=>true,getIncorrectShiftsInARow:()=>0,incrementIncorrectShiftsInARow:noop,resetIncorrectShiftsInARow:noop},
 'legacy-states/slow-timer':{get:()=>false},'states/test':{isTestRestarting:()=>false,getActiveWordIndex:()=>wordIndex,increaseActiveWordIndex:()=>wordIndex++,decreaseActiveWordIndex:()=>wordIndex--,isResultCalculating:()=>false,wordsHaveNewline:()=>false,isTestActive:()=>active},
 'test/test-logic':{addWord:()=>{if(growNext && wordIndex===targets.length-1){targets.push('c');growNext=false}},startTest:()=>{active=true},fail:()=>{failed=true},finish:()=>{completed=true}},'events/keymap':{flash:noop},'test/weak-spot':{updateScore:noop},'legacy-states/composition':{getComposing:()=>false},'states/notifications':{showNoticeNotification:noop},
 'input/helpers/word-navigation':{goToPreviousWord:noop,goToNextWord:async()=>({lastBurst:null,increasedWordIndex:true})},'test/pace-caret':{handleSpace:noop},'test/funbox/funbox':{toggleScript:noop},'states/loader-bar':{showLoaderBar:noop,hideLoaderBar:noop},'test/events/stats':{getWordBurst:()=>null},'test/words-generator':{areAllWordsGenerated:()=>Config.mode!=='time'},'utils/misc':{whorf:()=>0},'input/helpers/input-type':{DeleteInputType:{}},'@monkeytype/schemas/languages':{Language:{}}};
Object.assign(bindings['states/test'],{getKoreanStatus:()=>false,getCurrentQuote:()=>null,getBailedOut:()=>false});Object.assign(bindings,{'constants/keys':{Keycode:{}},'test/events/types':{EVENT_LOG_VERSION:1,InputEventNoMs:{},TestEventNoMs:{},CompositionTestEvent:{},CompositionTestEventData:{},EventLog:{},InputEvent:{},InputEventData:{},KeydownEvent:{},KeydownEventData:{},KeyupEvent:{},KeyupEventData:{},TestEvent:{},TestEventData:{},TestEventType:{},TimerEvent:{},TimerEventData:{}},'test/custom-text':{getLimit:()=>({mode:'none',value:0})},'test/funbox/active':{isFunboxActiveWithProperty:p=>p==='nospace'},'@monkeytype/util/numbers':{roundTo2:v=>Math.round(v*100)/100,isSafeNumber:Number.isFinite,mean:a=>a.reduce((x,y)=>x+y,0)/a.length}});bindings['utils/misc'].getMode2=()=>2;bindings['test/funbox/list'].isFunboxActiveWithProperty=p=>p==='nospace';bindings['states/test'].wordsHaveNewline=()=>targets.some(t=>t.includes('\n'));console.debug=()=>{};globalThis.document={querySelector:()=>({get value(){return ' '+element},set value(v){element=v.slice(1)}})};const modules=new Map();function getModule(id){if(modules.has(id))return modules.get(id);let mod;if(actual.has(id))mod=new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(path.join(root,id+'.ts'),'utf8'),{mode:'transform'}),{identifier:id});else{const data=bindings[id];if(!data)throw new Error('Unknown import '+id);mod=new vm.SyntheticModule(Object.keys(data),function(){for(const [key,value]of Object.entries(data))this.setExport(key,value)},{identifier:id});}modules.set(id,mod);return mod;}
const main=getModule('input/handlers/insert-text');await main.link((specifier,from)=>getModule(specifier.startsWith('.')?path.posix.normalize(path.posix.join(path.posix.dirname(from.identifier),specifier)):specifier));await main.evaluate();

const eventData=modules.get('test/events/data').namespace;
function reset(words,{stop='off',strict=false,mode='words',grow=false}={}) {
 targets=[...words];wordIndex=0;element='';active=false;completed=false;failed=false;growNext=grow;
 Object.assign(Config,{mode,strictSpace:strict,stopOnError:stop,funbox:[]});
 eventData.resetTestEvents();
}
function inputEvents(){return eventData.getAllTestEvents().filter(e=>e.type==='input').map(e=>e.data)}
function positions(){return inputEvents().map(e=>e.charIndex)}
reset(['hi\n_','next']);
await main.namespace.emulateInsertText({data:'hi\n_next',now:0});
assert.equal(wordIndex,1);assert.equal(completed,false);assert.equal(element,'t');
assert.equal(eventData.getCurrentInput(),'t');
assert.deepEqual(positions(),[0,1,2,0,1,2,3,4]);
assert.equal(inputEvents().at(-2).inputValue,'_nex');
assert.equal(inputEvents().at(-2).commitsWord,true);
assert.equal(inputEvents().at(-1).inputValue,'t');
assert.equal(inputEvents().at(-1).lastWord,true);
assert.equal(inputEvents().filter(e=>e.correct).length,3);
await main.namespace.emulateInsertText({data:'n',now:1});
assert.equal(positions().at(-1),1);assert.equal(inputEvents().at(-1).inputValue,'tn');
assert.equal(completed,false);

reset(['hi\n_','next']);
for(const key of 'hi\n_next') {
 await main.namespace.emulateInsertText({data:key,now:0});
 if(completed)break;
}
assert.equal(completed,true);assert.equal(inputEvents().length,7);
assert.equal(inputEvents().at(-1).data,'x');assert.equal(wordIndex,1);

reset(['ab'],{stop:'letter'});
await main.namespace.emulateInsertText({data:'abx',now:0});
assert.equal(completed,false);assert.equal(wordIndex,0);assert.equal(element,'');
assert.deepEqual(positions(),[0,1,2]);assert.equal(inputEvents().at(-1).inputValue,'');
assert.equal(inputEvents().at(-1).inputStopped,true);assert.equal(inputEvents().at(-1).lastWord,true);
assert.equal(eventData.getCurrentInput(),'');

reset(['🙂x','tail'],{stop:'letter'});
await main.namespace.emulateInsertText({data:'🙃',now:0});
assert.deepEqual(positions(),[0,1]);
assert.deepEqual(inputEvents().map(e=>e.correct),[true,false]);
assert.deepEqual(Array.from(element,c=>c.charCodeAt(0)),[55357]);
assert.equal(inputEvents().at(-1).inputStopped,true);

reset(['a','\n'],{strict:true});
await main.namespace.emulateInsertText({data:'a\n',now:0});
assert.equal(completed,true);assert.equal(wordIndex,1);
assert.deepEqual(positions(),[0,0]);assert.equal(inputEvents().at(-1).lastWord,true);
assert.equal(inputEvents().at(-1).commitsWord,undefined);

reset(['ab','cd']);
await main.namespace.emulateInsertText({data:'abcd',now:0});
assert.deepEqual(positions(),[0,1,0,1]);
assert.deepEqual(inputEvents().map(e=>e.lastWord===true),[false,false,true,true]);
assert.equal(completed,true);

reset(['a','b'],{mode:'time',grow:true});
await main.namespace.emulateInsertText({data:'ab',now:0});
assert.equal(inputEvents().at(-1).lastWord,true);
assert.equal(targets.length,3);assert.equal(wordIndex,2);
assert.equal(eventData.getCurrentInput(),'');assert.equal(completed,false);
reset(['a','b'],{grow:true});
await main.namespace.emulateInsertText({data:'ab',now:0});
assert.equal(inputEvents().at(-1).lastWord,true);
assert.equal(targets.length,3);assert.equal(wordIndex,2);
assert.equal(completed,false);
await main.namespace.emulateInsertText({data:'c',now:1});
assert.equal(completed,true);assert.equal(wordIndex,2);
console.log('8 pinned-source insertion scenarios passed (11 actual modules; bounded adapters, no browser/native parity claim).');

// Read the actual delete handlers. Browser editing below is an explicit
// sentinel/UTF-16 slice adapter; no real browser or platform word-delete used.
actual.add('input/handlers/delete'); actual.add('input/handlers/before-delete');
const linkModule=(specifier,from)=>getModule(specifier.startsWith('.')?path.posix.normalize(path.posix.join(path.posix.dirname(from.identifier),specifier)):specifier);
const deleteModule=getModule('input/handlers/delete'); await deleteModule.link(linkModule); await deleteModule.evaluate();
const beforeDeleteModule=getModule('input/handlers/before-delete'); await beforeDeleteModule.link(linkModule); await beforeDeleteModule.evaluate();
// The actual input module already captured this textarea object; replace its
// accessor rather than replace document or modify a source behavior function.
const textarea=modules.get('input/input-element').namespace.getInputElement();
Object.defineProperty(textarea,'value',{get(){return browserDeletedSentinel?'':' '+element},set(v){browserDeletedSentinel=false;element=v.slice(1)}});
let noSpaceDelete=true;
// Synthetic bindings expose values at evaluation time, so update the module's
// exported function deliberately; the official module is never modified.
modules.get('test/funbox/list').setExport('isFunboxActiveWithProperty',p=>p==='nospace'&&noSpaceDelete);
function seedDelete(targetWords,snapshots,{index=0,value=snapshots.at(-1)?.[1]??'',noSpace=true,code=false}={}) {
 reset(targetWords); noSpaceDelete=noSpace; browserDeletedSentinel=false; wordIndex=index; element=value; active=true;
 Object.assign(Config,{freedomMode:true,confidenceMode:'off',language:code?'code_javascript':'english',codeUnindentOnBackspace:code});
 for(const [wordIndex,inputValue]of snapshots)eventData.logTestEvent('input',0,{inputType:'insertText',wordIndex,inputValue,data:inputValue,correct:true});
}
function deleteInput({word=false,firefox=false,now=1}={}) {
 let prevented=false;beforeDeleteModule.namespace.onBeforeDelete({preventDefault(){prevented=true}});
 if(prevented)return false;
 if(element===''||firefox){browserDeletedSentinel=true;element=''}else element=word?'':element.slice(0,-1);
 deleteModule.namespace.onDelete(word?'deleteWordBackward':'deleteContentBackward',now);return true;
}
seedDelete(['abc','tail'],[[0,'ab']]); deleteInput();
assert.deepEqual([inputEvents().at(-1).wordIndex,inputEvents().at(-1).charIndex,inputEvents().at(-1).inputValue],[0,2,'a']);
seedDelete(['🙂x','tail'],[[0,'🙂']]); deleteInput();
assert.equal(inputEvents().at(-1).charIndex,2);assert.equal(inputEvents().at(-1).inputValue,'\ud83d');
deleteInput();assert.equal(inputEvents().at(-1).charIndex,1);assert.equal(inputEvents().at(-1).inputValue,'');
seedDelete(['ab','cd'],[[0,'ab']],{index:1,value:''}); deleteInput();
assert.deepEqual([inputEvents().at(-1).wordIndex,inputEvents().at(-1).charIndex,inputEvents().at(-1).inputValue],[0,1,'a']);
seedDelete(['ab','cd'],[[0,'ab']],{index:1,value:''}); deleteInput({word:true});
assert.deepEqual([inputEvents().at(-1).wordIndex,inputEvents().at(-1).charIndex,inputEvents().at(-1).inputValue],[0,0,'']);
seedDelete(['abcd','tail'],[[0,'abc']]); deleteInput({word:true});
assert.deepEqual([inputEvents().at(-1).charIndex,inputEvents().at(-1).inputValue],[3,'']);
seedDelete(['ab','cd'],[[0,'ab'],[1,'cd']],{index:1,value:''}); deleteInput();
assert.equal(inputEvents().at(-1).charIndex,1);assert.equal(inputEvents().at(-1).clearedNextWord,true);
seedDelete(['ab\n','\t\tx'],[[0,'ab\n'],[1,'\t\t']],{index:1,noSpace:false,code:true}); deleteInput();
assert.deepEqual(inputEvents().slice(-2).map(e=>[e.inputType,e.wordIndex,e.charIndex,e.inputValue]),[['deleteWordBackward',1,2,''],['deleteContentBackward',0,2,'ab']]);
seedDelete(['\t\tx'],[[0,'\t\t']],{code:true,noSpace:false}); deleteInput({word:true});
assert.deepEqual(inputEvents().slice(-2).map(e=>[e.inputType,e.wordIndex,e.charIndex,e.inputValue]),[['deleteWordBackward',0,2,''],['deleteContentBackward',0,0,'']]);
seedDelete(['ab','cd'],[[0,'ab'],[1,'c']],{index:1}); deleteInput({word:true,firefox:true});
assert.equal(inputEvents().at(-1).charIndex,0);assert.equal(inputEvents().at(-1).clearedNextWord,true);
seedDelete(['abc','tail'],[[0,'ab']]); Config.freedomMode=false;Config.confidenceMode='max';
const before=inputEvents().length;assert.equal(deleteInput(),false);assert.equal(inputEvents().length,before);
console.log('10 pinned-source deletion scenarios passed (13 actual modules; seeded snapshots and browser editing adapters, no native/Firefox/IME parity claim).');

// Ordinary source targets carry their literal commits. Switch both explicit
// funbox adapters; don't let the earlier no-space binding prove ordinary input.
modules.get('test/funbox/active').setExport('isFunboxActiveWithProperty',p=>p==='nospace'&&noSpaceDelete);
const ordinaryWord=i=>targets[i]===undefined?undefined:{
 textWithCommit:targets[i],text:targets[i].replace(/[ \n]$/,''),display:targets[i],
};
modules.get('test/test-words').setExport('words',{
 getCurrent:()=>ordinaryWord(wordIndex),get:i=>i===undefined?targets.map((_,i)=>ordinaryWord(i)):ordinaryWord(i),
 get length(){return targets.length},
});
function resetOrdinary(words,options={}) {
 noSpaceDelete=false;browserDeletedSentinel=false;reset(words,options);
 Object.assign(Config,{blindMode:false,freedomMode:false,confidenceMode:'off',language:'english',
  codeUnindentOnBackspace:false,quickEnd:false,oppositeShiftMode:'off',deleteOnError:'off',difficulty:'normal'});
}
resetOrdinary(['ab ','cd']);
await main.namespace.emulateInsertText({data:'ax cd',now:0});
assert.deepEqual(positions(),[0,1,2,0,1]);
assert.deepEqual(inputEvents().map(e=>e.lastWord===true),[false,false,false,true,true]);
assert.equal(inputEvents()[2].commitsWord,true);assert.equal(completed,true);
resetOrdinary(['ab']);
await main.namespace.emulateInsertText({data:'ab ',now:0});
assert.equal(completed,true);assert.equal(inputEvents().at(-1).correct,false);
assert.equal(inputEvents().at(-1).commitsWord,true);assert.equal(inputEvents().at(-1).lastWord,true);
assert.equal(inputEvents().at(-1).inputValue,'ab ');
assert.equal(modules.get('test/events/helpers').namespace.getInputFromDom(eventData.getAllTestEvents()),'ab');
resetOrdinary(['ab']);
await main.namespace.emulateInsertText({data:'ax ',now:0});
assert.equal(completed,true);
assert.equal(modules.get('test/events/helpers').namespace.getInputFromDom(eventData.getAllTestEvents()),'ax');
resetOrdinary(['ab'],{stop:'letter'});
await main.namespace.emulateInsertText({data:'a ',now:0});
assert.equal(inputEvents().at(-1).inputStopped,true);assert.equal(inputEvents().at(-1).commitsWord,undefined);
assert.equal(inputEvents().at(-1).inputValue,'a');assert.equal(completed,false);
resetOrdinary(['ab'],{stop:'word'});
await main.namespace.emulateInsertText({data:'ax ',now:0});
assert.equal(inputEvents().at(-1).commitsWord,undefined);
assert.equal(inputEvents().at(-1).inputValue,'ax ');assert.equal(completed,false);
resetOrdinary(['ab '],{mode:'time',grow:true});
await main.namespace.emulateInsertText({data:'ab ',now:0});
assert.equal(inputEvents().at(-1).correct,true);assert.equal(inputEvents().at(-1).lastWord,true);
assert.equal(targets.length,2);assert.equal(wordIndex,1);assert.equal(completed,false);
resetOrdinary(['🙂 ','e\u0301']);
await main.namespace.emulateInsertText({data:'🙂 e\u0301',now:0});
assert.deepEqual(positions(),[0,1,2,0,1]);assert.equal(completed,true);
resetOrdinary(['ab\n','\n','cd']);
await main.namespace.emulateInsertText({data:'ab\n\ncd',now:0});
assert.deepEqual(inputEvents().map(e=>e.wordIndex),[0,0,0,1,2,2]);
assert.equal(completed,true);
console.log('8 pinned-source ordinary insertion scenarios passed (13 actual modules; catalog/funbox/DOM adapters, no browser/IME/full-generation parity claim).');
for(const text of ['ab','🙂']) {
 resetOrdinary([text]);
 await main.namespace.emulateInsertText({data:text+' x',now:0});
 assert.equal(completed,false);assert.equal(wordIndex,0);assert.equal(element,'x');
 assert.equal(inputEvents().at(-1).charIndex,3);assert.equal(inputEvents().at(-1).inputValue,'x');
 await main.namespace.emulateInsertText({data:'b',now:1});
 assert.equal(inputEvents().at(-1).charIndex,1);
}
console.log('2 pinned-source ordinary terminal SPACE batch-reentry scenarios passed (same bounded adapters).');

// Primary language, not a candidate's identity, selects code indentation.
// Polyglot generation/selection is NOT run here. Targets and its config tag
// are owned adapters; these are the complete actual insertion/delete modules.
// Capture source zero-delay callbacks to drain deterministically, never wait
// for wall-clock scheduling or pretend this is a browser event loop.
const originalSetTimeout=globalThis.setTimeout;
let callbacks=[];
globalThis.setTimeout=(callback,delay)=>{
 assert.equal(delay,0);callbacks.push(callback);return callbacks.length;
};
function resetPolyglotInput(base,words) {
 resetOrdinary(words);callbacks=[];
 Object.assign(Config,{language:base,funbox:['polyglot'],codeUnindentOnBackspace:true});
 // getAllTestEvents exposes relative testMs, not raw timestamps. Give its
 // actual projection an explicit zero-start timer rather than assume a field.
 eventData.logTestEvent('timer',0,{event:'start'});
}
async function drainCodeCallbacks() {
 let count=0;
 while(callbacks.length) {
  assert.ok(++count<10,'bounded owned target must not schedule an unbounded chain');
  callbacks.shift()();
  // The source callback discards its async result; settle the actual
  // insertion/navigation microtasks before executing a successor callback.
  for(let i=0;i<8;i++)await Promise.resolve();
 }
}
try {
 for(const base of ['code_javascript','english','dockerfile']) {
  resetPolyglotInput(base,['ab ','\t\tgo() ','tail']);
  await main.namespace.emulateInsertText({data:'ab ',now:7});
  assert.equal(callbacks.length,base==='code_javascript'?1:0);
  assert.equal(element,'');await drainCodeCallbacks();
  assert.equal(element,base==='code_javascript'?'\t\t':'');
  assert.deepEqual(inputEvents().filter(e=>e.automatic).map(e=>e.data),base==='code_javascript'?['\t','\t']:[]);
  assert.ok(eventData.getAllTestEvents().filter(e=>e.type==='input'&&e.data.automatic).every(e=>e.testMs===7));
 }
 resetPolyglotInput('code_javascript',['\t\tgo() ','tail']);
 await main.namespace.emulateInsertText({data:'\tX',now:7});
 assert.equal(element,'\tX');assert.equal(callbacks.length,1);
 await drainCodeCallbacks();
 assert.equal(element,'\tX\t');assert.equal(inputEvents().at(-1).correct,false);
 assert.deepEqual(inputEvents().map(e=>e.automatic===true),[false,false,true]);
 resetPolyglotInput('code_javascript',['ab ','\t\tgo() ','tail']);
 await main.namespace.emulateInsertText({data:'a ',now:7});
 assert.equal(wordIndex,1);assert.equal(callbacks.length,0);
 for(const word of [false,true]) {
  resetPolyglotInput('code_javascript',['ab\n','\t\tgo() ','tail']);
  await main.namespace.emulateInsertText({data:'ab\n',now:7});await drainCodeCallbacks();
  assert.equal(element,'\t\t');deleteInput({word,now:8});
  assert.deepEqual(inputEvents().slice(-2).map(e=>[e.inputType,e.wordIndex,e.charIndex,e.inputValue]),[
   ['deleteWordBackward',1,2,''],['deleteContentBackward',0,word?0:2,word?'':'ab']]);
 }
 for(const base of ['english','dockerfile']) {
  resetPolyglotInput(base,['ab ','\t\tgo() ','tail']);
  await main.namespace.emulateInsertText({data:'ab \t\t',now:7});
  assert.equal(callbacks.length,0);deleteInput({now:8});
  assert.equal(wordIndex,1);assert.equal(element,'\t');
  assert.equal(inputEvents().at(-1).charIndex,2);
 }
 resetPolyglotInput('code_javascript',['ab ','\t\tgo() ','tail']);
 Config.codeUnindentOnBackspace=false;
 await main.namespace.emulateInsertText({data:'ab ',now:7});await drainCodeCallbacks();
 deleteInput({now:8});assert.equal(wordIndex,1);assert.equal(element,'\t');
 resetPolyglotInput('code_javascript',['ab ','\t\tgo() ','tail']);
 Config.confidenceMode='max';
 await main.namespace.emulateInsertText({data:'ab ',now:7});await drainCodeCallbacks();
 assert.equal(deleteInput({word:true,now:8}),false);assert.equal(element,'\t\t');
 for(const base of ['english','code_javascript']) {
  resetPolyglotInput(base,['ab ','tail']);
  assert.equal(modules.get('input/handlers/before-insert-text').namespace.onBeforeInsertText('\n'),true);
  resetPolyglotInput(base,['ab\n','tail']);
  assert.equal(modules.get('input/handlers/before-insert-text').namespace.onBeforeInsertText('\n'),false);
 }
 console.log('13 pinned-source primary-language code input scenarios passed (same 13 actual modules; owned Polyglot tag/targets, FIFO/microtask and sentinel deletion adapters; no generation/browser/AppKit/IME parity claim).');

 // Remove the Polyglot adapter tag: standalone Dockerfile is likewise NOT
 // selected by the source code prefix. No upstream vocabulary is copied.
 function resetStandaloneInput(base,words) {
  resetPolyglotInput(base,words);Config.funbox=[];
 }
 resetStandaloneInput('dockerfile',['ab ','\t\tgo() ','tail']);
 await main.namespace.emulateInsertText({data:'ab ',now:7});
 assert.equal(element,'');assert.equal(callbacks.length,0);
 assert.equal(inputEvents().filter(e=>e.automatic).length,0);
 resetStandaloneInput('dockerfile',['\t\tgo() ','tail']);
 await main.namespace.emulateInsertText({data:'\t',now:7});
 assert.equal(element,'\t');assert.equal(callbacks.length,0);
 for(const word of [false,true]) {
  resetStandaloneInput('dockerfile',['ab\n','\t\tgo() ','tail']);
  await main.namespace.emulateInsertText({data:'ab\n\t\t',now:7});
  const before=inputEvents().length;deleteInput({word,now:8});
  assert.equal(inputEvents().length,before+1);
  assert.deepEqual([inputEvents().at(-1).inputType,wordIndex,inputEvents().at(-1).charIndex,element],
   [word?'deleteWordBackward':'deleteContentBackward',1,2,word?'':'\t']);
 }
 resetStandaloneInput('dockerfile',['ab ','\t\tgo() ','tail']);
 Config.confidenceMode='max';
 await main.namespace.emulateInsertText({data:'ab \t\t',now:7});
 assert.equal(deleteInput({now:8}),false);assert.equal(element,'\t\t');
 seedDelete(['ab','\t\tgo()','tail'],[[0,'ab'],[1,'\t\t']],{index:1,noSpace:true});
 Object.assign(Config,{language:'dockerfile',funbox:['nospace'],codeUnindentOnBackspace:true});
 deleteInput();assert.equal(wordIndex,1);assert.equal(element,'\t');
 resetStandaloneInput('dockerfile',['ab\n','tail']);
 assert.equal(modules.get('input/handlers/before-insert-text').namespace.onBeforeInsertText('\n'),false);
 resetStandaloneInput('code_javascript',['ab ','\t\tgo() ','tail']);
 await main.namespace.emulateInsertText({data:'ab ',now:7});await drainCodeCallbacks();
 assert.equal(element,'\t\t');deleteInput({now:8});
 assert.deepEqual(inputEvents().slice(-2).map(e=>e.inputType),['deleteWordBackward','deleteContentBackward']);
 assert.equal(wordIndex,0);assert.equal(element,'ab');
 console.log('8 pinned-source standalone Dockerfile/code-prefix input scenarios passed (same 13 actual modules; owned targets, FIFO and sentinel deletion adapters; no generation/browser/device equivalence claim).');

 // The actual source substitutions read Config.language (the primary), not
 // candidate identity. Owned targets/tag do not exercise Polyglot generation
 // or its direction preflight; native tests cover that separate boundary.
 let normalizationScenarios=0;
 async function checkNormalization(base,target,entered,retained,correct) {
  resetPolyglotInput(base,[target+' ','tail']);
  await main.namespace.emulateInsertText({data:entered,now:7});
  assert.equal(element,retained);assert.equal(eventData.getCurrentInput(),retained);
  assert.deepEqual(inputEvents().map(e=>e.correct),correct);
  assert.deepEqual(positions(),correct.map((_,index)=>index));
  assert.equal(callbacks.length,0);normalizationScenarios++;
 }
 for(const target of ['ё','е','e'])for(const entered of ['ё','е','e']) {
  await checkNormalization('russian',target,entered,target,[true]);
  assert.equal(inputEvents()[0].data,target);
 }
 for(const base of ['russian','russian_1k','russian_5k','russian_10k','russian_25k','russian_50k','russian_375k']) {
  await checkNormalization(base,'ёл','eл','ёл',[true,true]);
 }
 for(const base of ['russian_abbreviations','russian_contractions','russian_contractions_1k']) {
  await checkNormalization(base,'ёл','eл','eл',[false,true]);
 }
 for(const base of ['dutch','dutch_1k','dutch_10k']) {
  await checkNormalization(base,'ij','ĳ','ij',[true,true]);
  assert.deepEqual(inputEvents().map(e=>e.data),['i','j']);
  assert.deepEqual(eventData.getAllTestEvents().filter(e=>e.type==='input').map(e=>e.testMs),[7,7]);
 }
 await checkNormalization('dutch','ĳ','ĳ','ĳ',[true]);
 await checkNormalization('dutch','IJ','Ĳ','Ĳ',[false]);
 await checkNormalization('english','ё','e','e',[false]);
 await checkNormalization('english','ij','ĳ','ĳ',[false]);
 await checkNormalization('dutch','ijx','ĳx','ijx',[true,true,true]);
 resetPolyglotInput('russian',['ёл','tail']);noSpaceDelete=true;
 Config.funbox=['polyglot','nospace'];
 await main.namespace.emulateInsertText({data:'eл',now:7});
 assert.equal(wordIndex,1);assert.equal(element,'');
 assert.deepEqual(inputEvents().map(e=>[e.data,e.correct,e.wordIndex,e.charIndex]),
  [['ё',true,0,0],['л',true,0,1]]);normalizationScenarios++;
 await checkNormalization('russian',"'",'’',"'",[true]);
 await checkNormalization('dutch','é','e\u0301','e\u0301',[false,false]);
 for(const base of ['russian','dutch']) {
  resetPolyglotInput(base,[base==='russian'?'ёл ':'ij ','tail']);
  await main.namespace.emulateInsertText({data:base==='russian'?'e':'ĳ',now:7});
  deleteInput({now:8});assert.equal(element,base==='russian'?'':'i');
  await main.namespace.emulateInsertText({data:base==='russian'?'e':'j',now:9});
  assert.equal(element,base==='russian'?'ё':'ij');
  assert.equal(inputEvents().at(-1).charIndex,base==='russian'?0:1);
  assert.equal(inputEvents().at(-1).correct,true);normalizationScenarios++;
 }
 assert.equal(normalizationScenarios,32);
 console.log(`${normalizationScenarios} pinned-source primary-language normalization scenarios passed (same 13 actual modules; owned Polyglot tag/targets and DOM deletion adapters; no generation/direction/browser/IME/Zen parity claim).`);
} finally {
 globalThis.setTimeout=originalSetTimeout;
}
