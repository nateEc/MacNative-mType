// QA only: complete pinned functions with owned collection/network adapters.
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
const controller = fs.readFileSync(path.join(root,'backend/src/api/controllers/result.ts'),'utf8');
const defaults = fs.readFileSync(path.join(root,'backend/src/constants/base-configuration.ts'),'utf8');
function numericDefault(key) {
  const matches = [...defaults.matchAll(new RegExp(`\\b${key}:\\s*(\\d+)`, 'g'))];
  assert.equal(matches.length,1);
  return Number(matches[0][1]);
}
let requestedWindow, premium = false;
const loading = vm.createContext({
  UserDAL:{checkIfUserIsPremium:async () => premium},
  ResultDAL:{getResults:async (_uid, options) => {requestedWindow=options.limit;return [];}},
  addLog:async () => {},replaceObjectIds:value => value,
  MonkeyError:class extends Error {},MonkeyResponse:class {constructor(_message,data){this.data=data;}}
});
new vm.Script(stripTypeScriptTypes(bounded(controller,'export async function getResults(',
  'export async function getResultById('),{mode:'transform'})).runInContext(loading);
const maxBatchSize = numericDefault('maxBatchSize');
for (const isPremium of [false,true]) {
  premium = isPremium;
  await loading.getResults({query:{},ctx:{decodedToken:{uid:'owned'},configuration:{users:{premium:{enabled:true}},
    results:{maxBatchSize,limits:{regularUser:numericDefault('regularUser'),premiumUser:numericDefault('premiumUser')}}}}});
  assert.equal(requestedWindow,Math.min(maxBatchSize,numericDefault(isPremium ? 'premiumUser' : 'regularUser')));
}
const initialResultLimit = requestedWindow;
const source = fs.readFileSync(path.join(root,'frontend/src/ts/collections/tags.ts'),'utf8');
const history = fs.readFileSync(path.join(root,'frontend/src/ts/collections/results.ts'),'utf8');
const action = bounded(history,'  updateTags: createOptimisticAction<ActionType["updateTags"]>({','\n  insertLocalResult:')
  .trim().replace(/^updateTags: /,'').replace(/,$/,'');
const code = bounded(source,'export function getLocalTagPB<','export function saveLocalTagPB<')
  + bounded(source,'export function saveLocalTagPB<','export function getActiveTagsPB<')
  + `\nconst updateTagsAction = ${action};`;
const ids = ['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222'];
const editedID = '33333333-3333-4333-8333-333333333333';
const laterID = '44444444-4444-4444-8444-444444444444';
const tieID = '55555555-5555-4555-8555-555555555555';
const now = 1800000000875;
let tags, results, written;
const context = vm.createContext({structuredClone,Date:{now:() => now},createOptimisticAction:value => value,
  getTag:id => tags.get(id),getResults:() => results,
  Ape:{results:{updateTags:async () => ({status:200,body:{data:{tagPbs:[]}}})}},
  resultsCollection:{update:(id,callback) => callback(results.find(row => row._id === id)),
    utils:{writeUpdate:row => Object.assign(results.find(value => value._id === row._id),row)}},
  tagsCollection:{get:id => tags.get(id),utils:{writeUpdate:tag => {tags.set(tag._id,tag);written.add(tag._id);}}}});
new vm.Script(stripTypeScriptTypes(code,{mode:'transform'})).runInContext(context);
const fixtures = [];
for (const [mode,parameter] of [['time',15],['time',30],['words',25],['words',50],['custom',0],['zen',0]]) {
 for (const difficulty of ['normal','expert','master']) for (let bits=0;bits<8;bits++) for (const language of ['english','spanish']) {
  const mode2 = ['time','words'].includes(mode) ? String(parameter) : mode;
  const group = {mode,mode2,difficulty,language,punctuation:!!(bits&1),numbers:!!(bits&2),lazyMode:!!(bits&4)};
  for (const variant of ['move-high','empty','tie','unchanged','different-group']) {
   const initial = [{_id:editedID,...group,tags:[ids[0]],wpm:80.49,rawWpm:95,acc:98,consistency:80}];
   if (variant !== 'empty') initial.push({_id:laterID,...group,tags:[ids[0]],wpm:60.41,rawWpm:75,acc:90,consistency:50});
   if (variant === 'tie') initial.push({_id:tieID,...group,tags:[ids[0]],wpm:60.41,rawWpm:85,acc:99,consistency:90});
   if (variant === 'different-group') initial.push({_id:tieID,...group,language:'owned_other',tags:[ids[0]],wpm:100,rawWpm:110,acc:99,consistency:90});
   const newIDs = variant === 'unchanged' ? [ids[0]] : [ids[1]];
   tags = new Map(ids.map(id => [id,{_id:id,personalBests:{[mode]:{[mode2]:[{...group,wpm:100,raw:110,acc:99,consistency:90,timestamp:123}]}}}]));
   results = structuredClone(initial); written = new Set();
   context.params = {resultId:editedID,currentTagIds:[ids[0]],newTagIds:newIDs};
   new vm.Script('updateTagsAction.onMutate(params)').runInContext(context);
   await new vm.Script('updateTagsAction.mutationFn(params)').runInContext(context);
   const expected = [...written].map(tagID => {
    const pb = tags.get(tagID).personalBests[mode][mode2][0];
    return {tagID,wpm:pb.wpm,rawWpm:pb.raw,accuracy:pb.acc,consistency:pb.consistency,rebuiltAtMilliseconds:pb.timestamp};
   });
   const nativeRows = initial.map(row => {
    const duration = mode === 'time' && parameter > 0 ? parameter : 15;
    const value = {id:row._id,mode,mode2,language:row.language,wpm:Math.round(row.wpm),rawWpm:row.rawWpm,
      accuracy:row.acc,consistency:row.consistency,errorCount:1,eventCount:75,tags:['owned text'],accountTagIDs:row.tags,
      startedAt:100,finishedAt:100+duration,personalBestConfiguration:{version:1,difficulty,
        punctuation:group.punctuation,numbers:group.numbers,lazyMode:group.lazyMode}};
    if (mode === 'time') value.durationSeconds = parameter;
    if (mode === 'words') value.wordLimit = parameter;
    if (row.wpm !== Math.round(row.wpm)) Object.assign(value,{speedPrecision:{version:1,wpm:row.wpm,rawWpm:row.rawWpm},startedAtReferenceTime:100,finishedAtReferenceTime:100+duration});
    return value;
   });
   const directory = {version:1,tags:ids.map(id => ({id,name:'desk',personalBestLedgerVersion:1,
    personalBests:[{id,mode,mode2,language,wpm:100,rawWpm:110,accuracy:99,consistency:90,finishedAt:100,
      acceptedAtMilliseconds:123,personalBestOrigin:'accepted',personalBestConfiguration:{version:1,difficulty,
        punctuation:group.punctuation,numbers:group.numbers,lazyMode:group.lazyMode},
      ...(mode === 'time' ? {durationSeconds:parameter} : mode === 'words' ? {wordLimit:parameter} : {})}]}))};
   const pace = ids.map(id => context.getLocalTagPB(id,mode,mode2,group.punctuation,group.numbers,language,difficulty,group.lazyMode));
   fixtures.push({mode,parameter,difficulty,language,punctuation:group.punctuation,numbers:group.numbers,lazyMode:group.lazyMode,
    directory,results:nativeRows,editedID,newIDs,at:now,expected,pace});
  }
 }
}
assert.equal(fixtures.length,1440);
verify();
console.log(emit ? JSON.stringify({referenceCommit:pin,initialResultLimit,fixtures})
 : `Account tag history source passed (1440 group/edit/zero/tie/metric cases; 5 complete bounded functions/actions; initial default ${initialResultLimit}; owned adapters; no GUI)`);
