// Complete pinned live-stats module and actual pinned Solid memos. Config,
// stored word records, navigation and terminal/elapsed signals are owned.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??'');
function verify(){
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const archive=process.env.TYPEBAR_SOLID_QA_ARCHIVE;
assert.ok(archive,'TYPEBAR_SOLID_QA_ARCHIVE required');
const integrity='sha512-6hJeJMOcEX8ktqjpDoJZEmld3ijvcvWBDtiXBm7f4332SiFN66QeAQI1REQshvyUoISsSeJ4PHDauKYbwao9JQ==';
assert.equal('sha512-'+createHash('sha512').update(fs.readFileSync(archive)).digest('base64'),integrity);
assert.ok(fs.readFileSync(path.join(root,'pnpm-lock.yaml'),'utf8').includes(integrity));
const core=new vm.SourceTextModule(execFileSync('tar',['-xOf',archive,'package/dist/solid.js'],{encoding:'utf8'}));
await core.link(()=>{throw Error('Unexpected Solid dependency');});await core.evaluate();
const solid=core.namespace;
const [records,setRecords]=solid.createSignal([]),[index,setIndex]=solid.createSignal(0);
const [limit,setLimit]=solid.createSignal(5),[seconds,setSeconds]=solid.createSignal(undefined);
const [calculating,setCalculating]=solid.createSignal(false),[bailed,setBailed]=solid.createSignal(false);
const config={mode:'custom',blindMode:false,timerStyle:'text'};
const bindings={
  '../config/store':{getConfig:config},
  '../singletons/format':{default:{typingSpeed:value=>String(value)}},
  '../test/custom-text':{getLimitMode:()=> 'section',getLimitValue:limit},
  '../test/test-words':{words:{get:i=>records()[i],get length(){return records().length;}}},
  '../utils/date-and-time':{secondsToString:()=>{throw Error('Time formatting outside section probe');}},
  './test':{currentLiveStats:{get seconds(){return seconds();}},getActiveWordIndex:index,
    getBailedOut:bailed,getCurrentQuote:()=>null,getFocus:()=>true,isResultCalculating:calculating,isTestActive:()=>true},
};
const source=new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(path.join(root,'frontend/src/ts/states/live-stats.ts'),'utf8'),{mode:'transform'}));
await source.link(id=>{
  if(id==='solid-js')return core;
  assert.ok(bindings[id],'Unexpected live stats dependency '+id);
  const values=bindings[id];return new vm.SyntheticModule(Object.keys(values),function(){
    for(const [name,value]of Object.entries(values))this.setExport(name,value);
  });
});
let dispose,evaluated;
solid.createRoot(d=>{dispose=d;evaluated=source.evaluate();});await evaluated;
const fixtures=[];
for(const indices of [[1,2,3,4,4,5],[1,1,2,2,3],Array.from({length:120},(_,i)=>Math.floor(i/3)+1)])
  for(const total of [0,1,3,4.5,5,101,Infinity]){
    solid.batch(()=>{setRecords(indices.map(sectionIndex=>({sectionIndex})));setLimit(total);});
    const snapshots=[];
    for(const active of [...indices.keys(),indices.length,1,0])for(const started of [false,true])
      for(const terminal of [false,true])for(const bailout of [false,true]){
        solid.batch(()=>{setIndex(active);setSeconds(started?0:undefined);setCalculating(terminal);setBailed(bailout);});
        const target=source.namespace.getBarTarget();
        snapshots.push({active,started,terminal,bailout,text:source.namespace.getTimerText(),
          fraction:parseFloat(target.width)/100,duration:target.duration});
      }
    fixtures.push({indices,total:String(total),snapshots});
  }
dispose();verify();
const generation=JSON.parse(execFileSync(process.execPath,['--experimental-vm-modules',
  path.join(path.dirname(path.resolve(process.argv[1])),'check-source-generated-backwards-order.mjs'),root,'--section-indices'],{encoding:'utf8'}));
verify();
await new Promise((resolve,reject)=>process.stdout.write(JSON.stringify({fixtures,generation})+'\n',error=>error?reject(error):resolve()));
