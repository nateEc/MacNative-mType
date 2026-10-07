// QA only: execute one complete pinned PB-table function on owned snapshots.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??''),emit=process.argv[3]==='--emit-fixtures';
assert.ok(process.argv[2]&&(!process.argv[3]||emit));
const pin='91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const source=fs.readFileSync(path.join(root,'frontend/src/ts/components/modals/PbTablesModal.tsx'),'utf8');
const start='function buildRows(',end='function getColumns(';
assert.equal(source.split(start).length,2);assert.equal(source.split(end).length,2);
const code=source.slice(source.indexOf(start),source.indexOf(end));
const context=vm.createContext({DB:{getSnapshot:()=>context.snapshot}});
new vm.Script(stripTypeScriptTypes(code,{mode:'transform'})).runInContext(context);
const fixtures=[];
for(const mode of ['time','words','custom','zen']) for(const size of [0,1,8,25]) for(const legacy of
  (['time','words'].includes(mode)&&size>=8?[0,1,2]:[0])) {
  const rows=Array.from({length:size},(_,i)=>{
    const key=(legacy?['30','15','4294967295','0','4294967294','5000000000']:['30','15','120','5','300','45'])[i%6];
    const mode2=['time','words'].includes(mode)?key:mode,wpm=[60.49,80,80,40.01][i%4];
    return {id:`00000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`,mode,mode2,
      ...(mode==='time'?{durationSeconds:Number(key)}:mode==='words'?{wordLimit:Number(key)}:{}),
      language:`owned_language_${i}`,wpm:Math.round(wpm),rawWpm:120,preciseWpm:wpm,preciseRawWpm:120,
      accuracy:98,preciseAccuracy:98.25,consistency:80.5,finishedAt:100+i,
      acceptedAtMilliseconds:1800000000875+i,personalBestOrigin:'accepted',
      personalBestConfiguration:{version:1,difficulty:['normal','expert','master'][i%3],
        punctuation:!!(i%2),numbers:!!(i%3),lazyMode:!!(i%4)}};
  });
  const grouped={};
  for(const row of rows) (grouped[row.mode2]??=[]).push({...row,_id:row.id,wpm:row.preciseWpm});
  context.snapshot={personalBests:{[mode]:grouped}};
  const expected=context.buildRows(mode).map(row=>({id:row.id,isGroupStart:row.isGroupStart}));
  assert.equal(expected.length,size);
  assert.equal(rows.filter(row=>grouped[row.mode2][0].id===row.id).length,
    expected.filter(row=>row.isGroupStart).length);
  const profile={id:'11111111-1111-4111-8111-111111111111',displayName:'Owned PB fixtures',joinedAt:0,
    completedResultCount:0,bestWPM:0,personalBests:[],personalBestLedgerVersion:1,
    personalBestHistoryComplete:true,personalBestSnapshots:rows};
  if(legacy) {
    profile.personalBests=rows;
    for(const key of ['personalBestLedgerVersion','personalBestHistoryComplete','personalBestSnapshots']) delete profile[key];
    if(legacy===2) for(const row of rows) delete row.mode2;
  }
  fixtures.push({mode,profile,expected});
}
context.snapshot=undefined;assert.equal(context.buildRows('time').length,0);
context.snapshot={personalBests:{words:{}}};assert.equal(context.buildRows('time').length,0);
verify();
if(emit) process.stdout.write(JSON.stringify({referenceCommit:pin,fixtures}));
else console.log(`complete pinned buildRows passed (${fixtures.length} owned mode/size fixtures; no Solid/table/DOM/HTTP)`);
