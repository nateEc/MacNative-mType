// QA only: execute complete pinned public edit and local PB functions.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
function bounded(text,start,end) {
  assert.equal(text.split(start).length,2);
  const from = text.indexOf(start), to = text.indexOf(end,from + start.length);
  assert.ok(to > from);
  return text.slice(from,to).replace(/^export /gm,'');
}
verify();
const results = fs.readFileSync(path.join(root,'frontend/src/ts/collections/results.ts'),'utf8');
const sourceTags = fs.readFileSync(path.join(root,'frontend/src/ts/collections/tags.ts'),'utf8');
const code = bounded(results,'export async function updateTags(','export async function insertLocalResult(')
  + bounded(sourceTags,'export function saveLocalTagPB<','export function reconcileLocalTagPB<');
const ids = ['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222'];
const resultID = '33333333-3333-4333-8333-333333333333', clock = 1800000000875;
let last, tags, awards, status, calls, callbacks, body;
const context = vm.createContext({structuredClone,Date:{now:()=>clock},
  resultsCollection:{isReady:()=>false},getLastResult:()=>last,
  Ape:{results:{updateTags:async request=>{calls++;body=request.body;return {status,body:{message:'owned error',data:{tagPbs:awards}}};}}},
  tagsCollection:{get:id=>tags.get(id),utils:{writeUpdate:tag=>tags.set(tag._id,tag)}}});
new vm.Script(stripTypeScriptTypes(code,{mode:'transform'})).runInContext(context);
const fixtures = [];
for (const mode of ['time','words','custom','zen','quote']) for (const difficulty of ['normal','expert','master'])
 for (const language of ['english','spanish']) for (let bits=0;bits<8;bits++) for (const mask of [0,1,2,3]) {
  const mode2 = mode === 'time' ? '15' : mode === 'words' ? '25' : mode === 'quote' ? 'typebar:owned' : mode;
  const options = {difficulty,language,punctuation:!!(bits&1),numbers:!!(bits&2),lazyMode:!!(bits&4)};
  last = {_id:resultID,mode,mode2,...options,tags:[ids[0]],wpm:80.49,rawWpm:95.75,acc:98.25,consistency:80.75};
  tags = new Map(ids.map(id=>[id,{_id:id,name:'desk',personalBests:{[mode]:{[mode2]:[
    {...options,wpm:100,raw:110,acc:99,consistency:90,timestamp:123}]}}}]));
  awards = ids.filter((_,i)=>mask&(1<<i)); status=200; calls=0; callbacks=[];
  context.params = {resultId:resultID,currentTagIds:[ids[0]],newTagIds:ids,
    afterUpdate:value=>callbacks.push(value.tagPbs)};
  await new vm.Script('updateTags(params)').runInContext(context);
  assert.equal(calls,1); assert.deepEqual(JSON.parse(JSON.stringify(body)),{resultId:resultID,tagIds:ids});
  assert.deepEqual(JSON.parse(JSON.stringify(callbacks)),[awards]);
  const expected = ids.map(tagID=>{
    const pb = tags.get(tagID).personalBests[mode][mode2][0];
    return {tagID,wpm:pb.wpm,rawWpm:pb.raw,accuracy:pb.acc,consistency:pb.consistency,at:pb.timestamp};
  });
  // Removing associations without awards does not rebuild or lower this book.
  awards=[]; context.params.newTagIds=[];
  await new vm.Script('updateTags(params)').runInContext(context);
  assert.equal(calls,2);
  for (const value of expected) assert.equal(tags.get(value.tagID).personalBests[mode][mode2][0].wpm,value.wpm);
  const row = {id:resultID,mode,mode2,language,wpm:80,rawWpm:96,accuracy:98,preciseAccuracy:98.25,
    consistency:80.75,errorCount:1,eventCount:75,tags:['owned text'],accountTagIDs:[ids[0]],
    startedAt:100,finishedAt:115,startedAtReferenceTime:100,finishedAtReferenceTime:115,
    speedPrecision:{version:1,wpm:80.49,rawWpm:95.75},personalBestConfiguration:{version:1,
      difficulty,punctuation:options.punctuation,numbers:options.numbers,lazyMode:options.lazyMode}};
  if (mode==='time') row.durationSeconds=15;
  if (mode==='words') row.wordLimit=25;
  fixtures.push({result:row,tagIDs:ids,awardIDs:ids.filter((_,i)=>mask&(1<<i)),at:clock,expected});
 }
assert.equal(fixtures.length,960);
// The original checks last-result identity AFTER the successful request.
for (const kind of ['missing','mismatch','rejected']) {
  last=kind==='missing'?undefined:{_id:'different'}; status=kind==='rejected'?403:200;
  awards=ids; calls=0; callbacks=[];
  const before=JSON.stringify([...tags]);
  await assert.rejects(new vm.Script('updateTags(params)').runInContext(context));
  assert.equal(calls,1); assert.equal(callbacks.length,0); assert.equal(JSON.stringify([...tags]),before);
}
verify();
console.log(emit ? JSON.stringify({referenceCommit:pin,fixtures})
  : 'Last result tag source passed (960 full-book/callback cases, removal retention, 3 failure boundaries; 2 complete functions; owned transport/collection, no HTTP/DOM/GUI)');
