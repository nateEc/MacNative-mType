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
function deleteInput({word=false,firefox=false}={}) {
 let prevented=false;beforeDeleteModule.namespace.onBeforeDelete({preventDefault(){prevented=true}});
 if(prevented)return false;
 if(element===''||firefox){browserDeletedSentinel=true;element=''}else element=word?'':element.slice(0,-1);
 deleteModule.namespace.onDelete(word?'deleteWordBackward':'deleteContentBackward',1);return true;
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
