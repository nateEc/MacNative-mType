// QA only: full actual hasConnection, button predicates and flag controller.
// Explicit owned collection/auth/props, not TanStack DB, Solid, browser or HTTP.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??''), emit=process.argv[3]==='--emit-fixtures';
assert.ok(process.argv[2]&&(!process.argv[3]||emit));
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
let authenticated=true, rows=[];
const owner='00000000-0000-0000-0000-000000000001', other='00000000-0000-0000-0000-000000000002';
const context=vm.createContext({props:{profile:{}},getUserId:()=>authenticated?owner:undefined,
  isAuthenticated:()=>authenticated,connectionsQuery:()=>authenticated?rows:[]});
const read=file=>fs.readFileSync(path.join(root,file),'utf8');
const run=source=>new vm.Script(stripTypeScriptTypes(source,{mode:'transform'})).runInContext(context);
const collection=read('frontend/src/ts/collections/connections.ts');
const marker='export function hasConnection(';assert.equal(collection.split(marker).length,2);
const start=collection.indexOf(marker),end=collection.indexOf('\nexport function findConnectionToUser',start);assert.ok(end>start);
run(collection.slice(start,end).replace('export ','')+'\nglobalThis.hasConnection=hasConnection;');
const details=read('frontend/src/ts/components/pages/profile/UserDetails.tsx');
const action=details.indexOf('function ActionButtons('),buttonStart=details.indexOf('  const isUsersProfile = () =>',action);
const buttonEnd=details.indexOf('  const handleAddFriend = () =>',buttonStart);assert.ok(action>=0&&buttonStart>action&&buttonEnd>buttonStart);
run(details.slice(buttonStart,buttonEnd)+'\nglobalThis.showFriendsButton=showFriendsButton;');
run(read('frontend/src/ts/controllers/user-flag-controller.ts').replace(/^import .*;\r?\n/gm,'').replaceAll('export ','')+
  '\nglobalThis.getMatchingFlags=getMatchingFlags;');
const fixtures=[];
for(authenticated of [false,true])for(const isSelf of [false,true])for(const relation of ['none','outgoing','incoming','accepted','blocked']) {
  const uid=isSelf?owner:other;context.props={profile:{uid}};
  rows=relation==='none'?[]:[{initiatorUid:relation==='incoming'?uid:owner,
    receiverUid:relation==='incoming'?owner:uid,status:['outgoing','incoming'].includes(relation)?'pending':relation}];
  const showAdd=context.showFriendsButton(),isFriend=context.getMatchingFlags({isFriend:context.hasConnection(uid,'accepted')}).some(it=>it.name==='Friend');
  assert.equal(showAdd,authenticated&&!isSelf&&relation==='none');
  assert.equal(isFriend,authenticated&&!isSelf&&relation==='accepted');
  fixtures.push({authenticated,isSelf,relation,showAdd,isFriend});
}
assert.equal(context.hasConnection(undefined),false);verify();
if(emit)process.stdout.write(JSON.stringify(fixtures));
else console.log('Profile relationship source passed (20 full actual predicates/hasConnection/flag projections; owned collection/auth/props; no TanStack/Solid/browser/HTTP)');
