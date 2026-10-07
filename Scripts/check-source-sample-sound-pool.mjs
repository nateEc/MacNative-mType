// QA only: complete pinned Howler core, owned synchronous HTML5 audio/timer adapters.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
const [rootArgument,archiveArgument,option]=process.argv.slice(2);
assert.ok(rootArgument&&archiveArgument&&(!option||option==='--emit-fixtures'));
const root=path.resolve(rootArgument),archive=path.resolve(archiveArgument);
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const integrity='sha512-QM0FFkw0LRX1PR8pNzJVAY25JhIWvbKMBFM4gqk+QdV+kPXOhleWGCB6AiAF/goGjIHK2e/nIElplvjQwhr0jg==';
assert.ok(fs.readFileSync(path.join(root,'pnpm-lock.yaml'),'utf8').includes('howler@2.2.3:\n    resolution: {integrity: '+integrity+'}'));
assert.ok(fs.statSync(archive).size<2_000_000);
assert.equal('sha512-'+createHash('sha512').update(fs.readFileSync(archive)).digest('base64'),integrity);
const read=file=>execFileSync('tar',['-xzOf',archive,'package/'+file],{encoding:'utf8',maxBuffer:2_000_000});
assert.equal(JSON.parse(read('package.json')).version,'2.2.3');
class OwnedAudio {
  muted=false;paused=true;currentTime=0;duration=1;readyState=4;ended=false;oncanplaythrough=null;
  canPlayType(){return 'probably';} addEventListener(){} removeEventListener(){} load(){}
  play(){this.paused=false;this.ended=false;} pause(){this.paused=true;}
}
const context=vm.createContext({Audio:OwnedAudio,window:{},exports:{},setTimeout:()=>1,clearTimeout:()=>{}});
new vm.Script(read('src/howler.core.js')).runInContext(context,{timeout:1000});
const play=source=>({kind:'play',source}),end=index=>({kind:'end',index});
const fixtures=[];
const sequences=[
  Array.from({length:10},(_,i)=>[play('click'),end(i)]).flat(),
  [...Array.from({length:32},()=>play('click')),...Array.from({length:32},(_,i)=>end(i)),...Array.from({length:6},()=>play('click'))],
  [...Array.from({length:8},()=>play('error')),...Array.from({length:8},(_,i)=>end(7-i)),...Array.from({length:6},()=>play('error'))],
  [play('click'),play('error'),end(0),play('error'),play('click'),end(1),end(2),end(3),play('error'),play('click')],
  [play('warning'),end(0),play('warning'),end(1),play('finish'),end(2),play('finish')],
];
for(const operations of sequences) {
  const groups=new Map(),played=[],seen=new Set(),steps=[];
  function group(source) {
    if(!groups.has(source)) {
      const howl=new context.exports.Howl({src:['owned-'+source+'.wav'],preload:false,html5:true});
      assert.equal(howl._pool,5);
      // Owned already-loaded metadata bypasses fetching/decoding, not play/end/pool code.
      howl._state='loaded';howl._duration=1;howl._sprite={__default:[0,1000]};groups.set(source,howl);
    }
    return groups.get(source);
  }
  for(const operation of operations) {
    let reused=null,seek=null;
    if(operation.kind==='play') {
      const howl=group(operation.source),id=howl.play(),sound=howl._soundById(id);
      assert.ok(sound&&!sound._ended&&!sound._paused);
      reused=seen.has(sound);seen.add(sound);seek=sound._node.currentTime;
      assert.equal(seek,0);
      played.push({howl,sound,id});sound._node.currentTime=.5;
    } else {
      const {howl,sound,id}=played[operation.index];
      assert.equal(sound._id,id,'fixture must never finish a stale recycled ID');
      sound._node.currentTime=1;sound._node.ended=true;howl._ended(sound);
      assert.equal(sound._ended,true);
    }
    const active=[...groups.values()].flatMap(h=>h._sounds).filter(s=>!s._ended).length;
    steps.push({...operation,reused,seek,active});
  }
  fixtures.push({steps,allocations:seen.size});
}
assert.equal(fixtures[0].allocations,1);assert.equal(fixtures[1].allocations,33);
assert.equal(fixtures[2].allocations,9);assert.equal(fixtures[4].allocations,2);
verify();
if(option) console.log(JSON.stringify(fixtures));
else console.log(`Sample sound pool source passed (${fixtures.length} sequences, ${fixtures.reduce((sum,f)=>sum+f.steps.length,0)} transitions; verified Howler 2.2.3 complete core; actual play/end/stop/reset/drain, owned synchronous HTML5 audio, loaded metadata and timers; no device/browser/WebAudio/loading queue)`);
