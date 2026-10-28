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
if(process.argv.includes('--lifecycle')) {
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
const bindings={
  animejs:{animate:()=>{throw Error('Animation outside probe');},AnimationParams:{},JSAnimation:{}},
  'states/banners':{addBanner:()=>{throw Error('Banner outside probe');}},
  'controllers/sound-controller':{playClick:()=>sounds.push('click'),playError:()=>sounds.push('error')},
  'utils/arrays':{lastElementFromArray:items=>items.at(-1)},
  'config/store':{Config:{mode:'words',funbox:[],playSoundOnError:'error'}},
  'test/test-words':{words:{get:index=>index===undefined?words.map(textWithCommit=>({textWithCommit})):
    words[index]===undefined?undefined:{textWithCommit:words[index]}}},
  'test/events/data':{buildEventLog:()=>({events}),getAllTestEvents:()=>events,
    getInputForWord:index=>events.filter(e=>e.data.wordIndex===index).at(-1)?.data.inputValue??''},
  'test/events/stats':{getInputHistory:()=>{throw Error('Zen outside probe');},getWpmHistory:()=>[]},
};
const bridge=`export const ownedProbe={
  opening(){refreshReplayFromEvents();wordPos=0;curPos=0;initializeReplayPrompt();},
  resumeIndex(){return loadOldReplay();},actions(){return replayData;},
  prepare(){wordsList=getWordsList();replayData=deriveReplayActions();wordPos=0;curPos=0;initializeReplayPrompt();},
  applyThrough(time){for(const action of replayData){if(action.time<=time)handleDisplayLogic(action);}},
  frame(){return {word:wordPos,position:curPos,fields:[...document.getElementById('replayWords').children].map(word=>({error:word.classList.contains('error'),letters:[...word.children].map(letter=>({text:letter.text,extra:letter.classList.contains('extra'),correct:letter.classList.contains('correct'),incorrect:letter.classList.contains('incorrect')}))}))};}
};`;
const modules=new Map();
function moduleFor(id) {
  if(modules.has(id)) return modules.get(id);
  let mod;
  if(id==='test/replay-ui'||id==='utils/dom') {
    const source=fs.readFileSync(path.join(reference,'frontend/src/ts',id+'.ts'),'utf8');
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
if(process.argv.includes('--lifecycle')) {
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
