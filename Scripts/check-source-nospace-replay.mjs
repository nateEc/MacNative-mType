// Execute the complete pinned replay UI module, without copying its code.
// Catalog, event storage, statistics, sound and DOM are bounded adapters.
// No browser, layout, timer playback, IME or real audio is exercised.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs'; import path from 'node:path'; import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const reference=path.resolve(process.argv[2]??'');
if(!process.argv[2] || execFileSync('git',['-C',reference,'rev-parse','HEAD'],{encoding:'utf8'}).trim()!=='91bd24bb8513785c7364cbea29296ff7adafac41')throw Error('Pinned reference required');
if(execFileSync('git',['-C',reference,'status','--porcelain'],{encoding:'utf8'}).trim())throw Error('Reference must be clean');
class Element {
 children=[]; parent=null; names=new Set(); text='';
 get className(){return [...this.names].join(' ')}
 set className(value){this.names=new Set(value.split(' ').filter(Boolean))}
 get classList(){return {add:n=>this.names.add(n),remove:n=>this.names.delete(n),contains:n=>this.names.has(n)}}
 set innerHTML(value){this.text=value;this.children=[]}
 appendChild(child){child.parent=this;this.children.push(child)}
 remove(){this.parent.children=this.parent.children.filter(c=>c!==this)}
}
const holder=new Element();let words=[],events=[],sounds=[];
const noop=()=>{};const selector={on:noop,onChild:noop,setText:noop};
globalThis.document={getElementById:id=>id==='replayWords'?holder:null,createElement:()=>new Element()};
const bindings={
 '../controllers/sound-controller':{playClick:()=>sounds.push('click'),playError:()=>sounds.push('error')},
 '../utils/arrays':{lastElementFromArray:items=>items.at(-1)},
 '../utils/dom':{qs:()=>selector,qsr:()=>selector},
 '../config/store':{Config:{mode:'words',funbox:['nospace'],playSoundOnError:'error'}},
 './test-words':{words:{get:index=>index===undefined?words.map(textWithCommit=>({textWithCommit})):words[index]===undefined?undefined:{textWithCommit:words[index]}}},
 './events/data':{buildEventLog:()=>({events}),getAllTestEvents:()=>events,
   getInputForWord:index=>events.filter(e=>e.data.wordIndex===index).at(-1)?.data.inputValue??''},
 './events/stats':{getInputHistory:()=>{throw Error('Zen outside this probe')},getWpmHistory:()=>[]},
};
const source=fs.readFileSync(path.join(reference,'frontend/src/ts/test/replay-ui.ts'),'utf8');
// Test-only access to existing private functions/state; no behavior function changed.
const bridge=`export const ownedProbe={
 prepare(){wordsList=getWordsList();replayData=deriveReplayActions();wordPos=0;curPos=0;initializeReplayPrompt();},
 actions(){return replayData;},applyThrough(time){for(const action of replayData){if(action.time<=time)handleDisplayLogic(action);}},
 seek(word,position){targetWordPos=word;targetCurPos=position;initializeReplayPrompt();return loadOldReplay();},
 frame(){return {word:wordPos,position:curPos,fields:[...document.getElementById('replayWords').children].map(word=>({error:word.classList.contains('error'),letters:[...word.children].map(letter=>({text:letter.text,classes:letter.className}))}))};}
};`;
const main=new vm.SourceTextModule(stripTypeScriptTypes(source,{mode:'transform'})+'\n'+bridge);
await main.link(id=>{const values=bindings[id];if(!values)throw Error('Unknown binding '+id);return new vm.SyntheticModule(Object.keys(values),function(){for(const [key,value]of Object.entries(values))this.setExport(key,value)})});
await main.evaluate();const probe=main.namespace.ownedProbe;
const insert=(wordIndex,inputValue,data,testMs=0,correct=true,inputStopped=false)=>({type:'input',testMs,data:{wordIndex,inputValue,data,correct,inputStopped,inputType:'insertText'}});
const deletion=(wordIndex,inputValue,testMs=1,whole=false)=>({type:'input',testMs,data:{wordIndex,inputValue,data:'',inputType:whole?'deleteWordBackward':'deleteContentBackward'}});
function prepare(targets,tape){words=targets;events=tape;sounds=[];probe.prepare()}
const opening=[insert(0,'a','a'),insert(0,'ab','b'),insert(1,'c','c',1),insert(1,'cd','d',2)];
prepare(['ab','cd'],opening);assert.equal(probe.frame().fields.length,2);
assert.equal(probe.seek(1,0),3);assert.equal(probe.frame().position,0);
assert.deepEqual(probe.frame().fields[0].letters.map(l=>l.classes),['correct','correct']);
prepare(['ab','cd'],opening);probe.applyThrough(2);assert.deepEqual([probe.frame().word,probe.frame().position],[1,2]);
assert.deepEqual(sounds,['click','click','click','click','click']);
prepare(['ab','cd'],[...opening.slice(0,3),deletion(0,'a',3)]);
assert.equal(probe.frame().fields.length,1);probe.applyThrough(3);
assert.deepEqual([probe.frame().word,probe.frame().position],[1,0]);
assert.equal(probe.frame().fields[0].error,true);assert.deepEqual(sounds,['click','click','error']);
prepare(['🙂','a'],[insert(0,'\ud83d','\ud83d'),insert(0,'🙂','\ude42'),insert(1,'a','a',1)]);
assert.equal(probe.frame().fields[0].letters.length,1);assert.equal(probe.seek(1,0),3);
assert.equal(probe.frame().fields[0].letters[0].classes,'correct');
prepare(['a\u0301\n','b'],[insert(0,'a','a'),insert(0,'a\u0301','\u0301'),insert(0,'a\u0301\n','\n',1),insert(1,'b','b',2)]);
probe.applyThrough(2);assert.equal(probe.frame().fields[0].letters.length,3);assert.equal(probe.frame().position,1);
prepare(['ab','cd'],[...opening.slice(0,2),insert(1,'','x',1,false,true)]);
probe.applyThrough(1);assert.deepEqual([probe.frame().word,probe.frame().position],[1,0]);assert.equal(sounds.length,3);
prepare(['a','','b'],[insert(0,'a','a'),insert(2,'b','b',1)]);
probe.applyThrough(1);assert.equal(probe.frame().fields.length,2);assert.deepEqual([probe.frame().word,probe.frame().position],[1,1]);
assert.equal(probe.frame().fields[1].letters.length,0);
prepare(['ab','cd'],[insert(0,'x','x',0,false),insert(0,'xb','b'),insert(1,'c','c',1)]);
probe.applyThrough(1);assert.equal(probe.frame().fields[0].error,true);assert.deepEqual(sounds,['error','click','error','click']);
prepare(['ab','cd'],[insert(0,'a','a'),insert(0,'ab','b'),insert(1,'c','c'),deletion(0,'a',1,true),insert(0,'ab','b',2),insert(1,'c','c',3)]);
probe.applyThrough(3);assert.equal(probe.frame().fields.length,2);assert.deepEqual([probe.frame().word,probe.frame().position],[1,1]);
prepare(['','b'],[insert(1,'b','b')]);
probe.applyThrough(0);assert.equal(probe.frame().fields.length,1);assert.equal(probe.frame().fields[0].letters.length,0);
assert.deepEqual([probe.frame().word,probe.frame().position],[0,1]);
console.log('9 owned no-space replay scenarios passed (complete actual replay-ui module; explicit catalog/data/stats/DOM/sound adapters, no browser/timer/IME/audio parity claim).');
