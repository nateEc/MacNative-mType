// QA only: execute pinned controller, result/user DAL and complete PB modules.
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
verify();
let clock = 1_800_000_000_875;
class Clock extends Date { static now() { return clock; } }
class ID { constructor(value) { this.value=String(value); } toString() {return this.value;} toHexString(){return this.value;} }
const context = vm.createContext({Date:Clock,ObjectId:ID});
let funboxes;
async function load(relative) {
  const module = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(path.join(root,relative),'utf8'),
    {mode:'transform'}),{context,identifier:relative});
  await module.link(id => {
    const names = id === '@monkeytype/schemas/configs' ? ['FunboxName'] : id === './types' ? ['FunboxMetadata']
      : id === '@monkeytype/schemas/shared' ? ['Mode','PersonalBest','PersonalBests']
      : id === '@monkeytype/schemas/results' ? ['Result'] : id === '@monkeytype/funbox' ? ['getFunbox'] : null;
    assert.ok(names,'Unexpected runtime dependency '+id);
    return new vm.SyntheticModule(names,function() {
      for (const name of names) this.setExport(name,name === 'getFunbox' ? funboxes.getFunbox : undefined);
    },{context});
  });
  await module.evaluate(); return module.namespace;
}
funboxes = await load('packages/funbox/src/list.ts');
const pb = await load('backend/src/utils/pb.ts');
function bind(relative,start,end,alias) {
  const text=fs.readFileSync(path.join(root,relative),'utf8');
  assert.equal(text.split(start).length,2);
  const from=text.indexOf(start),to=text.indexOf(end,from+start.length); assert.ok(to>from);
  const code=stripTypeScriptTypes(text.slice(from,to),{mode:'transform'}).replace('export async function','async function');
  new vm.Script(code+`\nglobalThis.${alias}=${start.match(/function (\w+)/)[1]};`).runInContext(context);
}
const a='11111111-1111-4111-8111-111111111111',b='22222222-2222-4222-8222-222222222222';
const resultID='33333333-3333-4333-8333-333333333333';
let tags, row;
Object.assign(context,{canFunboxGetPb:pb.canFunboxGetPb,checkAndUpdatePb:pb.checkAndUpdatePb,
  getTags:async uid => {assert.equal(uid,'owned');return tags;},
  getUsersCollection:() => ({updateOne:async (filter,operation) => {
    assert.equal(filter.uid,'owned');
    const tag=tags.find(value => value._id.toString() === filter['tags._id'].toString()); assert.ok(tag);
    tag.personalBests=structuredClone(operation.$set['tags.$.personalBests']);
  }}),getResultCollection:() => ({findOne:async filter => {
    assert.equal(filter.uid,'owned'); return filter._id.toString() === resultID ? structuredClone(row) : null;
  },updateOne:async (filter,operation) => {assert.equal(filter.uid,'owned');Object.assign(row,structuredClone(operation.$set));}}),
  MonkeyError:class extends Error {},MonkeyResponse:class {constructor(_message,data){this.data=data;}}
});
bind('backend/src/dal/user.ts','export async function checkIfTagPb(','export async function resetPb(','ownedTagPB');
bind('backend/src/dal/result.ts','export async function updateTags(','export async function getResult(','ownedResultTags');
Object.assign(context,{ResultDAL:{updateTags:context.ownedResultTags,getResult:async () => structuredClone(row)},
  UserDAL:{getPartialUser:async () => ({tags}),checkIfTagPb:context.ownedTagPB}});
bind('backend/src/api/controllers/result.ts','export async function updateTags(','export async function addResult(','ownedController');
function reset(overrides) {
  tags=[a,b].map(id => ({_id:new ID(id),name:'desk'}));
  row={_id:resultID,mode:'time',mode2:'15',difficulty:'normal',language:'english',punctuation:false,
    numbers:false,lazyMode:false,funbox:[],wpm:80.49,rawWpm:95.75,acc:98,consistency:80,tags:[a],...overrides};
}
async function edit(ids) {
  const response=await context.ownedController({ctx:{decodedToken:{uid:'owned'}},body:{resultId:resultID,tagIds:ids}});
  assert.deepEqual(row.tags,ids); return Array.from(response.data.tagPbs);
}
const admission=[];
const modifiers=[[],...funboxes.getFunboxNames().map(name => [name]),['mirror','crt']];
for (const mode of ['time','words','quote','custom','zen']) for (const acc of [99.9,100]) {
  for (const stopOnLetter of [false,true]) for (const bailedOut of [false,true]) for (const names of modifiers) {
    reset({mode,mode2:mode==='time'?'15':mode==='words'?'25':mode,acc,stopOnLetter,bailedOut,funbox:names});
    const awarded=await edit([b]);
    admission.push({mode,accuracy:acc,stopOnLetter,bailedOut,modifiers:names,eligible:awarded.includes(b)});
  }
}
const lifecycle=[];
for (const mode of ['time','words','custom','zen']) for (const difficulty of ['normal','expert','master']) {
  for (let bits=0;bits<8;bits++) for (const language of ['english','spanish']) {
    const group={mode,mode2:mode==='time'?'15':mode==='words'?'25':mode,difficulty,language,
      punctuation:!!(bits&1),numbers:!!(bits&2),lazyMode:!!(bits&4)};
    reset(group);
    tags[0].personalBests=pb.checkAndUpdatePb({},undefined,{...row,wpm:100,rawWpm:110}).personalBests;
    const steps=[];
    for (const [index,ids] of [[b],[b],[],[b],[a,b],[]].entries()) {
      clock++;
      const clearID=index===3 ? b : null;
      if (clearID) tags[1].personalBests={};
      const tagPbs=await edit(ids);
      const books=tags.map(tag => ({id:tag._id.toString(),bests:structuredClone(tag.personalBests?.[mode]?.[group.mode2] ?? [])}));
      steps.push({ids,clock,clearID,tagPbs,books});
    }
    lifecycle.push({...group,steps});
  }
}
// Unknown/foreign tags are rejected by the actual result DAL before mutation.
reset({}); const before=structuredClone(row);
await assert.rejects(edit(['44444444-4444-4444-8444-444444444444'])); assert.deepEqual(row,before);
verify();
console.log(emit ? JSON.stringify({referenceCommit:pin,admission,lifecycle})
  : `Account tag edit awards source passed (${admission.length} admission; ${lifecycle.length*6} lifecycle steps; full controller and two DAL functions, complete PB/Funbox modules; owned DB transport, no HTTP/GUI)`);
