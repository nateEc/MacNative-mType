// QA only: complete pinned DAL/name/configuration functions with owned adapters.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??'');
assert.ok(process.argv[2]&&!process.argv[3]);
const pin='91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
function bounded(file,start,end) {
  const source=fs.readFileSync(path.join(root,file),'utf8');
  assert.equal(source.split(start).length,2,start);
  const from=source.indexOf(start),to=source.indexOf(end,from+start.length);assert.ok(to>from,end);
  return source.slice(from,to).replace(/^export /gm,'');
}
verify();
let nextID=0, rows=new Map([['owner',[]],['other',[]]]);
class OwnedID {
  constructor(value) { this.value=value??(++nextID).toString(16).padStart(24,'0'); }
  toHexString() {return this.value;}
}
class OwnedError extends Error { constructor(status,...message) {super(message.join(':'));this.status=status;} }
const context=vm.createContext({ObjectId:OwnedID,MonkeyError:OwnedError,
  updateUser:async (query,operation,error)=>{
    const current=rows.get(query.uid);
    let matches=!!current;
    for(const key of Object.keys(query).filter(key=>key.startsWith('resultFilterPresets.'))) {
      if(key==='resultFilterPresets._id') matches&&=current.some(row=>row._id.value===query[key].value);
      else matches&&=current[Number(key.split('.')[1])]===undefined;
    }
    if(!matches) throw new OwnedError(error.statusCode,error.message);
    if(operation.$push) current.push(structuredClone(operation.$push.resultFilterPresets));
    if(operation.$pull) rows.set(query.uid,current.filter(row=>row._id.value!==operation.$pull.resultFilterPresets._id.value));
  },
  z:{string:()=>({checks:[],maximum:Infinity,
    regex(pattern){this.checks.push(pattern);return this;},max(value){this.maximum=value;return this;},
    accepts(value){return value.length<=this.maximum&&this.checks.every(pattern=>pattern.test(value));}})},
});
const code=[
  bounded('backend/src/dal/user.ts','export async function addResultFilterPreset(','export async function addTag('),
  bounded('frontend/src/ts/utils/strings.ts','export function normalizeName(','export function splitByAndKeep('),
  bounded('packages/schemas/src/util.ts','export const slug =','export const nameWithSeparators ='),
  fs.readFileSync(path.join(root,'backend/src/middlewares/configuration.ts'),'utf8')
    .replace(/^import\b[\s\S]*?from ["'][^"']+["'];\n/gm,'').replace(/^export /gm,''),
].join('\n')+'\nglobalThis.presetNameSchema=slug().max(16);';
new vm.Script(stripTypeScriptTypes(code,{mode:'transform'})).runInContext(context);
const accepted=['a','Study_set','a..b','a--','_','-','1234567890123456'];
const rejected=['','.start','has space','中文','12345678901234567','bad/slash'];
for(const name of accepted) assert.equal(context.presetNameSchema.accepts(name),true,name);
for(const name of rejected) assert.equal(context.presetNameSchema.accepts(name),false,name);
for(const [input,expected] of [['  Study   set ','Study_set'],[' a\tb\nc ','a_b_c'],['Already_set','Already_set']]) {
  assert.equal(context.normalizeName(input),expected);
}
const owned={name:'Study_set',pb:{yes:true,no:false},tags:{none:true},mode:{time:true}};
await assert.rejects(()=>context.addResultFilterPreset('owner',owned,0),e=>e.status===409);
const first=await context.addResultFilterPreset('owner',owned,2);
const second=await context.addResultFilterPreset('owner',owned,2);
assert.notEqual(first.value,second.value,'duplicate names still have separate identities');
await assert.rejects(()=>context.addResultFilterPreset('owner',owned,2),e=>e.status===409);
await context.addResultFilterPreset('other',{...owned,name:'Other'},2);
await assert.rejects(()=>context.removeResultFilterPreset('other',first.value),e=>e.status===404);
owned.pb.yes=false;assert.equal(rows.get('owner')[0].pb.yes,true,'stored snapshot is not a live caller reference');
await context.removeResultFilterPreset('owner',first.value);
await assert.rejects(()=>context.removeResultFilterPreset('owner',first.value),e=>e.status===404);
assert.equal(rows.get('owner').length,1);assert.equal(rows.get('other').length,1);
await context.addResultFilterPreset('owner',owned,2);assert.equal(rows.get('owner').length,2);
context.getMetadata=req=>req.metadata;
const contracts=fs.readFileSync(path.join(root,'packages/contracts/src/users.ts'),'utf8');
let switchCases=0;
for(const [start,end] of [['    addResultFilterPreset: {','    removeResultFilterPreset: {'],
  ['    removeResultFilterPreset: {','    getTags: {']]) {
  assert.equal(contracts.split(start).length,2);
  const section=contracts.slice(contracts.indexOf(start),contracts.indexOf(end,contracts.indexOf(start)+start.length));
  const fields=[...section.matchAll(/requireConfiguration: \{\s*path: "([^"]+)",\s*invalidMessage:\s*"([^"]+)",\s*\}/g)];
  assert.equal(fields.length,1);assert.equal(fields[0][1],'results.filterPresets.enabled');
  for(const enabled of [false,true]) for(const maxPresetsPerUser of [0,20]) {
    let calls=0,error;
    await context.verifyRequiredConfiguration()({metadata:{requireConfiguration:{path:fields[0][1],invalidMessage:fields[0][2]}},
      ctx:{configuration:{results:{filterPresets:{enabled,maxPresetsPerUser}}}}},{},failure=>{calls++;error=failure;});
    assert.equal(calls,1);assert.equal(error?.status,enabled?undefined:503);switchCases++;
  }
}
assert.equal(switchCases,8);
for(const value of [undefined,null,0,'false']) {
  let error;
  await context.verifyRequiredConfiguration()({metadata:{requireConfiguration:{path:'results.filterPresets.enabled'}},
    ctx:{configuration:{results:{filterPresets:{enabled:value}}}}},{},failure=>{error=failure;});
  assert.equal(error?.status,500);
}
let unguarded=false;
await context.verifyRequiredConfiguration()({metadata:undefined},{},()=>{unguarded=true;});
assert.equal(unguarded,true);
verify();
console.log('Account filter presets source passed (13 slug boundaries, 3 normalizations, duplicate names, bounded owner-scoped DAL add/delete; 8 enabled/capacity mutation gates and 4 invalid configuration cases from both contract paths; 7 complete functions; owned Mongo/Zod/request adapters, no full Express/HTTP/TanStack/GUI)');
