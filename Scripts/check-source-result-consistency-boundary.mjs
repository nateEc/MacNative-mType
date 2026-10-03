// Owned fixtures execute the full pinned DB projection, read-only.
// ObjectId and erased type imports are adapters; no MongoDB/server runs.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??'');
assert.ok(process.argv[2],'Reference checkout required');
assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),
  '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
const source=fs.readFileSync(path.join(root,'backend/src/utils/result.ts'),'utf8');
const mod=new vm.SourceTextModule(stripTypeScriptTypes(source,{mode:'transform'}));
class OwnedObjectIdAdapter {}
const bindings={
  mongodb:{ObjectId:OwnedObjectIdAdapter},
  '@monkeytype/schemas/results':{ChartData:null,CompletedEvent:null,OldChartData:null,Result:null},
  '@monkeytype/schemas/shared':{Mode:null},
  './misc':{WithObjectId:null},
  '@monkeytype/schemas/configs':{FunboxName:null},
};
await mod.link(id=>{
  const values=bindings[id];assert.ok(values,'Unknown source dependency '+id);
  return new vm.SyntheticModule(Object.keys(values),function(){
    for(const[key,value]of Object.entries(values))this.setExport(key,value);
  });
});
await mod.evaluate();
for(const [consistency,keyConsistency,wpmConsistency] of [[100,66.67,8.9],[0,0,100],[81,100,0],[8.9,33.3,66.67]]){
  const ce={uid:'owned-user',wpm:80,rawWpm:80,charStats:[100,0,0,0],acc:100,mode:'time',mode2:'15',
    timestamp:39000,testDuration:15,consistency,keyConsistency,wpmConsistency,
    chartData:{wpm:[80,80],burst:[100,100],err:[0,0]},restartCount:0,incompleteTestSeconds:0,
    afkDuration:0,tags:[],language:'english',lazyMode:false,difficulty:'normal',funbox:[],numbers:false,
    punctuation:false,bailedOut:false,blindMode:false};
  const result=mod.namespace.buildDbResult(ce,'Owned',false);
  assert.equal(result.consistency,consistency);assert.equal(result.keyConsistency,keyConsistency);
  assert.ok(!Object.hasOwn(result,'wpmConsistency'));
  assert.equal(result.wpm,80);assert.equal(result.acc,100);
  assert.ok(!Object.hasOwn(result,'keySpacing'));
  assert.ok(!Object.hasOwn(result,'restartCount'));
  assert.equal(ce.wpmConsistency,wpmConsistency,'Projection must not mutate the completed event');
}
console.log('4 consistency submission-to-history fixtures passed (one complete actual buildDbResult module; ObjectId/type adapters, no DB/controller/schema runtime or anticheat claim).');
