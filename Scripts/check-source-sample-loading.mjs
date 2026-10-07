// QA only: exact Howler core; owned delayed HTML5 readiness and controlled timers.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
const [referenceArgument,archiveArgument,option]=process.argv.slice(2);
assert.ok(referenceArgument&&archiveArgument&&(!option||option==='--emit-fixtures'));
const reference=path.resolve(referenceArgument),archive=path.resolve(archiveArgument);
function verify(){
  assert.equal(execFileSync('git',['-C',reference,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',reference,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const integrity='sha512-QM0FFkw0LRX1PR8pNzJVAY25JhIWvbKMBFM4gqk+QdV+kPXOhleWGCB6AiAF/goGjIHK2e/nIElplvjQwhr0jg==';
assert.ok(fs.readFileSync(path.join(reference,'pnpm-lock.yaml'),'utf8').includes('howler@2.2.3:\n    resolution: {integrity: '+integrity+'}'));
assert.ok(fs.statSync(archive).size<2_000_000);
assert.equal('sha512-'+createHash('sha512').update(fs.readFileSync(archive)).digest('base64'),integrity);
const core=execFileSync('tar',['-xzOf',archive,'package/src/howler.core.js'],{encoding:'utf8',maxBuffer:2_000_000});
const fixtures=[];
for(const requests of [1,2,8,32,128]){
  const nodes=[],starts=[],timers=new Map();let timerID=0;
  class OwnedAudio {
    muted=false;paused=true;currentTime=0;duration=1;readyState=0;ended=false;oncanplaythrough=null;
    listeners=new Map();
    constructor(){nodes.push(this);}
    canPlayType(){return 'probably';}
    addEventListener(name,callback){if(!this.listeners.has(name))this.listeners.set(name,new Set());this.listeners.get(name).add(callback);}
    removeEventListener(name,callback){this.listeners.get(name)?.delete(callback);}
    load(){}
    play(){this.paused=false;this.ended=false;if(this.src?.startsWith('owned-'))starts.push({seek:this.currentTime,volume:this.volume});}
    pause(){this.paused=true;}
    ready(){for(const callback of [...(this.listeners.get('canplaythrough')??[])])callback();}
  }
  const context=vm.createContext({Audio:OwnedAudio,window:{location:{protocol:'file:'}},exports:{},
    setTimeout:(callback,delay)=>{const id=++timerID;timers.set(id,{callback,delay});return id;},clearTimeout:id=>timers.delete(id)});
  new vm.Script(core).runInContext(context,{timeout:1000});
  const howl=new context.exports.Howl({src:['owned-loading.wav'],preload:false,html5:true});
  howl.load();assert.equal(howl.state(),'loading');
  const ids=[];
  for(let index=0;index<requests;index++){howl.seek(0);ids.push(howl.play());}
  assert.equal(starts.length,0);assert.equal(howl._queue.length,requests*2);
  // Owned media readiness drives the real listener and queue; no state patch.
  for(const node of nodes)node.readyState=4;
  for(const node of [...nodes])node.ready();
  for(let turns=0;turns<1000;turns++){
    const immediate=[...timers].filter(([,timer])=>timer.delay===0);
    if(!immediate.length)break;
    for(const [id,timer]of immediate){timers.delete(id);timer.callback();}
  }
  assert.equal(howl.state(),'loaded');assert.equal(howl._queue.length,0);
  assert.ok(starts.length>=requests);assert.ok(starts.every(start=>start.seek===0));
  fixtures.push({requests,queued:requests*2,starts:starts.length,distinctRequestedIDs:new Set(ids).size,seeks:starts.map(start=>start.seek)});
}
verify();
if(option)console.log(JSON.stringify(fixtures));
else console.log(`Sample loading source passed (${fixtures.length} bursts, ${fixtures.reduce((n,f)=>n+f.requests,0)} requests; actual load/readiness/seek/play/queue, full verified Howler 2.2.3; owned synchronous Audio and zero-delay timers; no browser/device/WebAudio/Promise-playLock; starts ${fixtures.map(f=>f.starts).join(',')}; IDs ${fixtures.map(f=>f.distinctRequestedIDs).join(',')})`);
