// QA only: full pinned Howler WebAudio core with owned clock, nodes and decoder.
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
const play=(source='click',preview=false)=>({kind:'play',source,preview}),advance=amount=>({kind:'advance',amount});
const finish=slot=>({kind:'finish',source:'click',slot});
const sequences=[
  [play(),advance(.2),play(),advance(.2),play()],
  [play(),play('error'),advance(.2),play('error'),advance(.2),play('click',true)],
  [play(),play(),finish(0),advance(.2),play()],
  [play(),play(),play(),finish(1),finish(2),advance(.2),play()],
  [...Array.from({length:8},()=>play()),...Array.from({length:8},(_,i)=>finish(7-i)),...Array.from({length:6},()=>play())],
  [play(),play(),play(),finish(0),finish(2),play(),advance(.2),play('click',true)],
  [...Array.from({length:32},()=>play()),...Array.from({length:32},(_,i)=>finish(i)),...Array.from({length:6},()=>play())],
];
const fixtures=[];
for(const operations of sequences){
  const timers=new Map();let timerID=0,clock=0;
  class OwnedAudio { muted=false;canPlayType(){return 'probably';} }
  class OwnedContext {
    state='running';sampleRate=44100;destination={};get currentTime(){return clock;}
    createGain(){return {gain:{setValueAtTime(){}},connect(){},disconnect(){}};}
    createBuffer(){return {duration:0};}
    createBufferSource(){return {playbackRate:{setValueAtTime(){}},connect(){},disconnect(){},start(){},stop(){}};}
    decodeAudioData(_data,success){success({duration:1});}
  }
  const context=vm.createContext({Audio:OwnedAudio,AudioContext:OwnedContext,window:{location:{protocol:'file:'}},
    document:{addEventListener(){},removeEventListener(){}},exports:{},atob:value=>Buffer.from(value,'base64').toString('binary'),
    setTimeout:(callback,delay)=>{const id=++timerID;timers.set(id,{callback,delay});return id;},clearTimeout:id=>timers.delete(id)});
  new vm.Script(core).runInContext(context,{timeout:1000});
  const groups=new Map(),snapshots=[];
  function flush(){
    for(let turn=0;turn<1000;turn++){
      const immediate=[...timers].filter(([,timer])=>timer.delay===0);if(!immediate.length)return;
      for(const [id,timer]of immediate){timers.delete(id);timer.callback();}
    }
    assert.fail('zero-delay event queue did not settle');
  }
  function group(source){
    if(!groups.has(source)){
      const howl=new context.exports.Howl({src:['data:audio/wav;base64,'+Buffer.from('owned-'+source).toString('base64')],preload:false});
      howl.load();flush();assert.equal(howl._webAudio,true);assert.equal(howl.state(),'loaded');
      groups.set(source,{howl,slots:new Map()});
    }
    return groups.get(source);
  }
  function snapshot(){
    const active=[];
    for(const [source,{howl,slots}]of groups){
      for(const sound of howl._sounds){
        if(!slots.has(sound._node))slots.set(sound._node,slots.size);
        if(howl.playing(sound._id))active.push({source,slot:slots.get(sound._node),position:Number(howl.seek(sound._id).toFixed(6))});
      }
    }
    return active;
  }
  for(const operation of operations){
    if(operation.kind==='play'){
      const {howl}=group(operation.source);howl.seek(0);howl.play();
    }else if(operation.kind==='advance'){clock+=operation.amount;}
    else{
      const {howl,slots}=group(operation.source);
      const sound=howl._sounds.find(value=>slots.get(value._node)===operation.slot);
      assert.ok(sound&&howl.playing(sound._id));howl._ended(sound);
    }
    flush();snapshots.push(snapshot());
  }
  fixtures.push({operations,snapshots,allocations:Object.fromEntries([...groups].map(([source,{slots}])=>[source,slots.size]))});
}
assert.deepEqual(fixtures[0].snapshots.at(-1).map(value=>value.position),[0,.2,0]);
assert.deepEqual(fixtures[3].snapshots.at(-1).map(value=>value.slot),[0,1]);
assert.deepEqual(fixtures[4].snapshots.at(-1).map(value=>value.slot),[0,1,2,3,4,5]);
verify();
if(option)console.log(JSON.stringify(fixtures));
else console.log(`Sample seek source passed (${fixtures.length} sequences, ${fixtures.reduce((n,f)=>n+f.operations.length,0)} transitions; complete verified Howler 2.2.3 WebAudio load/seek/play/end/pool, owned clock/nodes/decoder/zero-delay timers; no browser/device/DSP/Promise-playLock)`);
