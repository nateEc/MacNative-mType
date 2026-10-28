// Execute the complete pinned replay UI and DOM delegation modules.
// Owned DOM/event/storage/sound adapters; no browser geometry or real audio.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const reference = path.resolve(process.argv[2] ?? '');
assert.ok(process.argv[2]);
assert.equal(execFileSync('git', ['-C', reference, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(),
  '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git', ['-C', reference, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
class Element {
  children=[]; parentNode=null; names=new Set(); text=''; listeners=new Map(); attributes=new Map();
  constructor(tagName='div') { this.tagName=tagName; }
  get parentElement() { return this.parentNode; }
  get className() { return [...this.names].join(' '); }
  set className(value) { this.names=new Set(value.split(' ').filter(Boolean)); }
  get classList() { return {add:n=>this.names.add(n),remove:n=>this.names.delete(n),contains:n=>this.names.has(n)}; }
  set innerHTML(value) { this.text=value; this.children=[]; }
  appendChild(child) { child.parentNode=this; this.children.push(child); }
  remove() { this.parentNode.children=this.parentNode.children.filter(c=>c!==this); this.parentNode=null; }
  contains(child) { return child===this || this.children.some(c=>c.contains(child)); }
  closest(selector) { return this.tagName===selector ? this : this.parentElement?.closest(selector) ?? null; }
  addEventListener(type, callback) { this.listeners.set(type, [...(this.listeners.get(type)??[]),callback]); }
  dispatch(type, target) { for (const callback of this.listeners.get(type)??[]) callback({target}); }
  setAttribute(key, value) { this.attributes.set(key,value); }
  getAttribute(key) { return this.attributes.get(key)??null; }
}
const holder=new Element(), result=new Element(), stats=new Element();
const playButton=new Element('button'), playIcon=new Element('i');
playButton.appendChild(playIcon);playIcon.className='fas fa-play';
globalThis.document={
  getElementById:id=>id==='replayWords'?holder:id==='playpauseReplayButton'?playButton:null,
  createElement:tag=>new Element(tag),
  querySelector:selector=>selector==='#replayWords'?holder:selector==='.pageTest #resultReplay'?result:
    selector==='#replayStats'?stats:selector==='.pageTest #playpauseReplayButton'?playButton:null,
};
let clock=0, timerID=0;const timers=new Map();
if(process.argv.includes('--lifecycle') || process.argv.includes('--terminal') || process.argv.includes('--statistics')) {
  globalThis.setTimeout=(callback,delay)=>{const id=++timerID;timers.set(id,{callback,due:clock+Math.max(0,delay)});return id;};
  globalThis.clearTimeout=id=>timers.delete(id);
}
function runThrough(time) {
  for(;;) {
    const next=[...timers].filter(([,t])=>t.due<=time).sort((a,b)=>a[1].due-b[1].due||a[0]-b[0])[0];
    if(!next)break;
    timers.delete(next[0]);clock=next[1].due;next[1].callback();
  }
  clock=time;
}
let words=[], events=[], sounds=[];
let eventContext={mode:'words',mode2:'1',bailedOut:false,koreanStatus:false,targetWords:[]};
const bindings={
  animejs:{animate:()=>{throw Error('Animation outside probe');},AnimationParams:{},JSAnimation:{}},
  'states/banners':{addBanner:()=>{throw Error('Banner outside probe');}},
  'controllers/sound-controller':{playClick:()=>sounds.push('click'),playError:()=>sounds.push('error')},
  'utils/arrays':{lastElementFromArray:items=>items.at(-1)},
  'config/store':{Config:{mode:'words',funbox:[],playSoundOnError:'error'}},
  'test/test-words':{words:{get:index=>index===undefined?words.map(textWithCommit=>({textWithCommit})):
    words[index]===undefined?undefined:{textWithCommit:words[index]}}},
  'test/events/data':{buildEventLog:()=>({events,context:eventContext}),getAllTestEvents:()=>events,
    getInputForWord:index=>process.argv.includes('--statistics')
      ? modules.get('test/events/helpers').namespace.getInputFromDom(modules.get('test/events/helpers').namespace.getEventsForWord(events,index))
      : events.filter(e=>e.data.wordIndex===index).at(-1)?.data.inputValue??''},
  'test/events/stats':{getInputHistory:()=>{throw Error('Zen outside probe');},getWpmHistory:()=>[]},
  'constants/keys':{Keycode:{}},'@monkeytype/schemas/languages':{Language:{}},
  'test/events/types':{InputEventNoMs:{},TestEventNoMs:{},EventLog:{}},
  'hangul-js':{default:{disassemble(){throw Error('Korean outside statistics probe');}}},
};
const bridge=`export const ownedProbe={
  opening(){refreshReplayFromEvents();wordPos=0;curPos=0;initializeReplayPrompt();},
  resumeIndex(){return loadOldReplay();},actions(){return replayData;},
  prepare(){wordsList=getWordsList();replayData=deriveReplayActions();wordPos=0;curPos=0;initializeReplayPrompt();},
  applyThrough(time){for(const action of replayData){if(action.time<=time)handleDisplayLogic(action);}},
  frame(){return {word:wordPos,position:curPos,fields:[...document.getElementById('replayWords').children].map(word=>({error:word.classList.contains('error'),letters:[...word.children].map(letter=>({text:letter.text,extra:letter.classList.contains('extra'),correct:letter.classList.contains('correct'),incorrect:letter.classList.contains('incorrect')}))}))};}
};`;
const modules=new Map();
const actual=new Set(['test/replay-ui','utils/dom']);
if(process.argv.includes('--statistics'))for(const id of ['test/events/stats','test/events/helpers','utils/strings','utils/numbers','@monkeytype/util/numbers'])actual.add(id);
function moduleFor(id) {
  if(modules.has(id)) return modules.get(id);
  let mod;
  if(actual.has(id)) {
    const file=id==='@monkeytype/util/numbers'?path.join(reference,'packages/util/src/numbers.ts'):path.join(reference,'frontend/src/ts',id+'.ts');
    const source=fs.readFileSync(file,'utf8').replace('import { CharCounts, countChars, isSpace }','import { countChars, isSpace }');
    mod=new vm.SourceTextModule(stripTypeScriptTypes(source,{mode:'transform'})+(id==='test/replay-ui'?'\n'+bridge:''),
      {identifier:id,initializeImportMeta:meta=>{meta.env={DEV:false};}});
  } else {
    assert.ok(bindings[id],'Unexpected dependency '+id);
    const values=bindings[id];
    mod=new vm.SyntheticModule(Object.keys(values),function(){for(const [key,value] of Object.entries(values))this.setExport(key,value);},{identifier:id});
  }
  modules.set(id,mod);return mod;
}
const main=moduleFor('test/replay-ui');
await main.link((id,from)=>moduleFor(id.startsWith('.')?path.posix.normalize(path.posix.join(path.posix.dirname(from.identifier),id)):id));
await main.evaluate();
const probe=main.namespace.ownedProbe;
if(process.argv.includes('--statistics')) {
  const fixtures=[];
  const cases=[
    [0,2.49,2.49,'words','abcd'],[0.49,2.5,2.5,'words','abcd'],
    [0.5,2.6,2.6,'words','abcd'],[0.7,2.6,2.9,'words','abcd'],
    [1.49,2.6,2.6,'time','abcd'],[1.5,2.6,2.6,'zen','abcd'],
    [0,150.6,150.6,'words','abcd'],[0,2.6,2.6,'words','e\u0301xy'],
    [0,2.6,2.6,'words','🙂abc'],
    [0,2.495,2.495,'words','abcd'],[0,2.499,2.499,'words','abcd'],[0,2.995,2.995,'words','abcd'],
  ];
  for(const [first,last,end,mode,target] of cases) {
    words=[target];clock=0;timers.clear();sounds=[];playIcon.className='fas fa-play';
    bindings['config/store'].Config.mode=mode;
    eventContext={mode,mode2:mode==='time'?'30':mode==='zen'?'zen':'1',bailedOut:false,koreanStatus:false,targetWords:words};
    const times=[first,first+0.1,last-0.1,last],tape=[];let value='';
    for(const [i,text] of [...target].entries()){value+=text;tape.push({time:times[i],index:0,value,text,correct:true});}
    events=tape.map(e=>({type:'input',testMs:e.time*1000,data:{wordIndex:e.index,inputValue:e.value,data:e.text,inputType:'insertText',correct:true}}));
    events.push({type:'timer',testMs:end*1000,data:{event:'end'}});
    const history=modules.get('test/events/stats').namespace.getWpmHistory({events,context:eventContext});
    const trace=[];
    const capture=(kind,extra={})=>trace.push({kind,now:clock/1000,label:stats.textContent,...extra});
    probe.opening();let index=probe.resumeIndex();capture('load',{offset:probe.actions()[index].time/1000});
    playButton.dispatch('click',playButton);index=probe.resumeIndex();capture('play',{offset:probe.actions()[index].time/1000,end:last});
    for(const time of [...new Set([0,0.25,0.55,0.95,1.25,last-first,last-first+0.5])].sort((a,b)=>a-b)){
      runThrough(time*1000);capture('advance');
    }
    main.namespace.pauseReplay();
    fixtures.push({mode,target,end,tape,history,trace});
  }
  for(const scenario of [
    {targets:['ab ','cd'],tape:[
      {time:0,index:0,value:'a',text:'a',correct:true},{time:0.1,index:0,value:'ab',text:'b',correct:true},
      {time:0.2,index:0,value:'ab ',text:' ',correct:true},{time:0.3,index:1,value:'x',text:'x',correct:false},
      {time:0.5,index:1,value:'',text:'',deletion:true,correct:true},
      {time:1.2,index:1,value:'c',text:'c',correct:true},{time:2.6,index:1,value:'cd',text:'d',correct:true}]},
    {targets:['a ','b ','cd'],tape:[
      {time:0,index:0,value:'a',text:'a',correct:true},{time:0.1,index:1,value:'b',text:'b',correct:true},
      {time:0.2,index:0,value:'a',text:'',deletion:true,correct:true},
      {time:1.2,index:2,value:'c',text:'c',correct:true},{time:1.3,index:1,value:'b',text:'b',correct:true},
      {time:2.6,index:2,value:'cd',text:'d',correct:true}]},
  ]) {
    const mode='words',end=2.6,target=scenario.targets.join(''),tape=scenario.tape;
    words=scenario.targets;clock=0;timers.clear();sounds=[];playIcon.className='fas fa-play';bindings['config/store'].Config.mode=mode;
    eventContext={mode,mode2:String(words.length),bailedOut:false,koreanStatus:false,targetWords:words};
    events=tape.map(e=>({type:'input',testMs:e.time*1000,data:{wordIndex:e.index,inputValue:e.value,data:e.text,
      inputType:e.deletion?'deleteContentBackward':'insertText',correct:e.correct}}));
    events.push({type:'timer',testMs:end*1000,data:{event:'end'}});
    const history=modules.get('test/events/stats').namespace.getWpmHistory({events,context:eventContext}),trace=[];
    const capture=(kind,extra={})=>trace.push({kind,now:clock/1000,label:stats.textContent,...extra});
    probe.opening();let index=probe.resumeIndex();capture('load',{offset:probe.actions()[index].time/1000});
    playButton.dispatch('click',playButton);index=probe.resumeIndex();capture('play',{offset:probe.actions()[index].time/1000,end});
    for(const time of [0,0.25,0.55,0.95,1.25,2.6,3.1]){runThrough(time*1000);capture('advance');}
    main.namespace.pauseReplay();fixtures.push({mode,target,targets:words,end,tape,history,trace});
  }
  // The old fractional-tail stopwatch survives completion. A new run can
  // share its deadline; the later registered stopwatch wins that tie.
  const target='abcd',first=0.7,last=2.6,end=2.6,mode='words';words=[target];
  clock=0;timers.clear();sounds=[];playIcon.className='fas fa-play';bindings['config/store'].Config.mode=mode;
  eventContext={mode,mode2:'1',bailedOut:false,koreanStatus:false,targetWords:words};
  const tape=[...target].map((text,i)=>({time:[first,0.8,2.5,last][i],index:0,value:target.slice(0,i+1),text,correct:true}));
  events=tape.map(e=>({type:'input',testMs:e.time*1000,data:{wordIndex:e.index,inputValue:e.value,data:e.text,inputType:'insertText',correct:true}}));
  events.push({type:'timer',testMs:end*1000,data:{event:'end'}});
  const history=modules.get('test/events/stats').namespace.getWpmHistory({events,context:eventContext}),trace=[];
  const capture=(kind,extra={})=>trace.push({kind,now:clock/1000,label:stats.textContent,...extra});
  probe.opening();let index=probe.resumeIndex();capture('load',{offset:probe.actions()[index].time/1000});
  function play(){playButton.dispatch('click',playButton);const index=probe.resumeIndex();capture('play',{offset:probe.actions()[index].time/1000,end:last});}
  function advance(time){runThrough(time*1000);capture('advance');}
  play();advance(2);play();advance(2.3);
  playButton.dispatch('click',playButton);capture('pause');assert.equal(timers.size,0);
  advance(2.4);play();advance(2.5);advance(3);
  main.namespace.pauseReplay();
  fixtures.push({mode,target,end,tape,history,trace});
  console.log(JSON.stringify({fixtures}));
} else if(process.argv.includes('--terminal')) {
  const input=(index,value,text,time,extra={})=>({index,value,text,time,correct:true,...extra});
  const fixtures=[];
  const scenarios=[
    {targets:['ab'],tape:[input(0,'a','a',0),input(0,'ab','b',50),input(0,'ab','x',1000,{stopped:true})]},
    {targets:['a ','b'],tape:[input(0,'a','a',0),input(1,'','x',1000,{stopped:true})]},
    {targets:['ab'],tape:[input(0,'','x',1000,{stopped:true})]},
    {targets:['ab'],tape:[input(0,'a','a',0),input(0,'ab','b',0),input(0,'ab','x',1000,{stopped:true})]},
    {targets:['ab'],tape:[input(0,'a','a',0),input(0,'ab','b',20),input(0,'a','',50,{deletion:true}),input(0,'a','x',1000,{stopped:true})]},
    {targets:['a ','b'],tape:[input(0,'a','a',0),input(0,'a ',' ',20),input(1,'b','b',50),input(0,'a','x',1000,{stopped:true})]},
  ];
  for(const {targets,tape} of scenarios) {
    words=targets;clock=0;timers.clear();sounds=[];playIcon.className='fas fa-play';
    events=tape.map(e=>({type:'input',testMs:e.time,data:{wordIndex:e.index,inputValue:e.value,data:e.text,
      inputType:e.deletion?'deleteContentBackward':'insertText',correct:e.correct,inputStopped:e.stopped}}));
    probe.opening();const actions=probe.actions();let error=null;
    try {playButton.dispatch('click',playButton);}catch(caught){error=caught.message;}
    const lastOffset=actions.at(-1)?.time??0;
    if(actions.length) {
      assert.equal(error,null);runThrough(lastOffset-actions[0].time);
      assert.equal(playButton.getAttribute('aria-label'),'Start replay');assert.equal(timers.size,0);
    } else {assert.equal(error,'Failed to load old replay: datatime is undefined');}
    fixtures.push({targets,tape,lastOffset,actionCount:actions.length,error,frame:probe.frame(),sounds:sounds.slice()});
    main.namespace.pauseReplay();assert.equal(timers.size,0);
  }
  console.log(JSON.stringify({fixtures}));
} else if(process.argv.includes('--lifecycle')) {
  const fixtures=[];
  for(const leadingTime of [0,700])for(const target of ['ab ','e\u0301 ']) {
    words=[target,'cd'];clock=0;timers.clear();sounds=[];playIcon.className='fas fa-play';
    const characters=[...target],prefix=characters[0];
    const tape=[{index:0,value:prefix,text:prefix,correct:true},
      {index:0,value:prefix+'x',text:'x',correct:false},
      {index:0,value:prefix,text:'',deletion:true}];
    let value=prefix;
    for(const text of characters.slice(1)){value+=text;tape.push({index:0,value,text,correct:true});}
    tape.push({index:1,value:'c',text:'c',correct:true},{index:1,value:'cd',text:'d',correct:true});
    events=tape.map((e,index)=>({type:'input',testMs:leadingTime+index*1000,data:{wordIndex:e.index,
      inputValue:e.value,data:e.text,inputType:e.deletion?'deleteContentBackward':'insertText',correct:e.correct}}));
    probe.opening();playButton.dispatch('click',playButton);const opening=probe.frame();
    const firstOffset=probe.actions()[0].time;runThrough(2500);const paused=probe.frame();
    playButton.dispatch('click',playButton);assert.equal(timers.size,0);
    sounds=[];playButton.dispatch('click',playButton);const resumed=probe.frame();
    const resumedOffset=probe.actions()[probe.resumeIndex()].time;
    runThrough(clock);const immediate=probe.frame(),immediateSounds=sounds.slice();
    assert.deepEqual(immediateSounds,['error']);
    playButton.dispatch('click',playButton);assert.equal(timers.size,0);
    sounds=[];playButton.dispatch('click',playButton);const secondResume=probe.frame();
    const secondOffset=probe.actions()[probe.resumeIndex()].time;
    runThrough(clock+20000);const completed=probe.frame(),completionSounds=sounds.slice();
    assert.equal(playButton.getAttribute('aria-label'),'Start replay');
    sounds=[];playButton.dispatch('click',playButton);const restarted=probe.frame();
    runThrough(clock);const restartImmediate=probe.frame(),restartSounds=sounds.slice();
    main.namespace.pauseReplay();assert.equal(timers.size,0);
    fixtures.push({targets:words,tape,leadingTime,firstOffset,opening,paused,resumed,resumedOffset,
      immediate,immediateSounds,secondResume,secondOffset,completed,completionSounds,restarted,restartImmediate,restartSounds});
  }
  console.log(JSON.stringify({fixtures}));
} else {
const fixtures=[];
for(const target of ['ab','e\u0301','🙂','ab ']) {
  words=[target,'cd'];
  const tape=[];let value='';
  for(const text of target) {value+=text;tape.push({index:0,value,text,correct:true});}
  const extraTime=tape.length;
  tape.push({index:0,value:target+' ',text:' ',correct:false});
  const deleteTime=tape.length;
  tape.push({index:0,value:target,text:'',deletion:true});
  tape.push({index:1,value:'c',text:'c',correct:true},{index:1,value:'cd',text:'d',correct:true});
  events=tape.map((e,time)=>({type:'input',testMs:time,data:{wordIndex:e.index,inputValue:e.value,data:e.text,
    inputType:e.deletion?'deleteContentBackward':'insertText',correct:e.correct}}));
  const prepare=()=>{sounds=[];probe.prepare();};
  prepare();const initial=probe.frame();
  holder.dispatch('click',holder.children[0]);const marginClick=probe.frame();
  assert.deepEqual(marginClick,initial);assert.equal(sounds.length,0);
  holder.dispatch('click',holder.children[1].children[0]);const letterClick=probe.frame();
  assert.equal(letterClick.word,1);assert.equal(letterClick.position,0);assert.equal(sounds.length,0);
  prepare();probe.applyThrough(extraTime);const extra=probe.frame();sounds=[];
  holder.dispatch('click',holder.children[0].children.at(-1));const extraClick=probe.frame();
  assert.equal(extraClick.position,[...target].length);assert.equal(sounds.length,0);
  prepare();probe.applyThrough(deleteTime);const deleted=probe.frame();
  fixtures.push({targets:words,tape,initial,marginClick,letterClick,extra,extraClick,deleted,extraTime,deleteTime});
}
console.log(JSON.stringify({fixtures}));
}
