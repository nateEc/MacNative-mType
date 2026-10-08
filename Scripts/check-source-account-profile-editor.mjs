// QA only: actual pinned form configuration and complete async submit callback.
// Owned form/transport/snapshot adapters, not a Solid/TSX/schema/browser test.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??''), emit=process.argv[3]==='--emit-fixtures';
assert.ok(process.argv[2]&&(!process.argv[3]||emit));
const pin='91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const source=fs.readFileSync(path.join(root,'frontend/src/ts/components/modals/EditProfileModal.tsx'),'utf8');
const start='export function EditProfile() {', end='\n  return (';
assert.equal(source.split(start).length,2);assert.equal(source.split(end).length,2);
const begin=source.indexOf(start), finish=source.indexOf(end,begin);
assert.ok(finish>begin);
let snapshot, response, calls, closed, errors, success, invalidations, resets;
const clone=value=>JSON.parse(JSON.stringify(value));
const context=vm.createContext({
  getSnapshot:()=>snapshot,
  createForm:factory=>{const form=factory();form.reset=value=>resets.push(clone(value));return form;},
  Ape:{users:{updateProfile:async value=>{calls.push(clone(value));return response;}}},
  hideModal:name=>{assert.equal(name,'EditProfile');closed++;},
  setSnapshot:value=>{snapshot=value;},
  invalidateMyProfile:()=>{invalidations++;},
  showSuccessNotification:value=>success.push(value),showErrorNotification:value=>errors.push(value)
});
new vm.Script(stripTypeScriptTypes(source.slice(begin,finish).replace('export ','')+'\nreturn form;\n}',
  {mode:'transform'})).runInContext(context);
function reset(value,status=200,data=undefined) {
  snapshot=clone(value);response={status,body:{data}};calls=[];closed=0;errors=[];
  success=[];invalidations=0;resets=[];
}
const fixtures=[];
for(const selected of [-1,1,2,3]) for(const wanted of [-1,1,2,3]) for(const showActivity of [false,true]) {
  const inventory={badges:[1,2,3].map(id=>({id,selected:id===selected}))};
  const details={bio:'Owned bio',keyboard:'Owned keys',socialProfiles:{github:'owned',twitter:'owned_x',website:'https://owned.invalid'},
    showActivityOnPublicProfile:!showActivity};
  reset({uid:'owned-source-id',inventory,details,unrelated:'retain'});
  const form=context.EditProfile(), defaults=clone(form.defaultValues);
  assert.equal(defaults.badgeId,selected);
  const value={...defaults,bio:'Changed bio',badgeId:wanted,showActivityOnPublicProfile:showActivity};
  assert.equal(calls.length,0);assert.equal(closed,0);assert.equal(snapshot.details.bio,'Owned bio');
  await form.onSubmit({value});
  assert.equal(calls.length,1);assert.equal(closed,1);assert.equal(invalidations,1);
  assert.equal(success.length,1);assert.equal(errors.length,0);assert.deepEqual(resets,[value]);
  assert.deepEqual(calls[0],{body:{bio:value.bio,keyboard:value.keyboard,
    socialProfiles:{twitter:value.twitter,github:value.github,website:value.website},
    showActivityOnPublicProfile:showActivity,selectedBadgeId:wanted}});
  assert.equal(snapshot.unrelated,'retain');assert.equal(snapshot.details.bio,value.bio);
  assert.deepEqual(snapshot.inventory.badges.filter(it=>it.selected).map(it=>it.id),wanted<0?[]:[wanted]);
  fixtures.push({defaults,value,details:clone(snapshot.details),selectedBadgeId:wanted});
}
for(const status of [401,403,429,500]) {
  const initial={uid:'owned-source-id',details:{bio:'Original'},inventory:{badges:[]}};
  reset(initial,status);const form=context.EditProfile(), value={...form.defaultValues,bio:'Retry draft'};
  await form.onSubmit({value});
  assert.equal(calls.length,1);assert.equal(errors.length,1);assert.equal(closed,0);
  assert.equal(invalidations,0);assert.equal(success.length,0);assert.equal(resets.length,0);
  assert.deepEqual(snapshot,initial);assert.equal(value.bio,'Retry draft');
}
reset({uid:'owned-source-id'});
const missing=context.EditProfile();
assert.deepEqual(clone(missing.defaultValues),{bio:'',keyboard:'',github:'',twitter:'',website:'',
  showActivityOnPublicProfile:true,badgeId:-1});
const canonical={bio:'Canonical',keyboard:'Canonical keys',socialProfiles:{github:'canonical'},showActivityOnPublicProfile:false};
reset({uid:'owned-source-id'},200,canonical);
const form=context.EditProfile();await form.onSubmit({value:{...form.defaultValues,bio:'  Canonical  '}});
assert.deepEqual(snapshot.details,canonical);assert.equal(closed,1);assert.equal(invalidations,1);
snapshot=undefined;assert.throws(()=>context.EditProfile(),/missing snapshot/);
assert.equal(fixtures.length,32);verify();
console.log(emit?JSON.stringify({referenceCommit:pin,fixtures}):
  'Account profile editor source passed (32 draft/save/badge/activity fixtures, 4 HTTP failures, missing defaults/snapshot and canonical response; actual form configuration + complete submit callback; owned adapters, no Solid/TSX/schema/browser/HTTP)');
