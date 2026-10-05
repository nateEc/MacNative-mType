// Execute complete pinned DAL functions and their generated JS $function body.
// Mongo transport is observed, not a real Mongo database or BSON transaction.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
const verify = () => {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
};
verify();
const dal = fs.readFileSync(path.join(root,'backend/src/dal/user.ts'),'utf8');
let document;
const context = vm.createContext({MonkeyError:Error,getUsersCollection:() => ({
  updateOne:async (filter,pipeline) => {
    assert.equal(filter.uid,'owned');
    if (document === null) return {matchedCount:0};
    assert.equal(pipeline.length,3);
    assert.equal(pipeline[0].$addFields.tmp.$function.lang,'js');
    const operation = pipeline[0].$addFields.tmp.$function;
    assert.deepEqual(Array.from(operation.args.slice(0,3)),['$inbox','$xp','$inventory']);
    const originalFunction = new vm.Script('('+operation.body+')').runInContext(context);
    const result = originalFunction(document.inbox,document.xp,document.inventory,operation.args[3],operation.args[4]);
    document = JSON.parse(JSON.stringify(result));
    assert.equal(pipeline[1].$set.xp,'$tmp.xp');
    assert.equal(pipeline[1].$set.inbox,'$tmp.inbox');
    assert.equal(pipeline[1].$set.inventory,'$tmp.inventory');
    assert.equal(pipeline[2].$unset,'tmp');
    return {matchedCount:1};
  },
})});
const start = dal.indexOf('export async function updateInbox('), end = dal.indexOf('\nexport async function ',start+1);
assert.ok(start >= 0 && end > start);
new vm.Script(stripTypeScriptTypes(dal.slice(start,end).replace('export async','async'),{mode:'transform'})).runInContext(context);
const id = last => '00000000-0000-4000-8000-00000000000'+last;
const badge = (id,selected) => ({id,selected});
// Bridge numeric badge identities into Typebar-owned presentation metadata.
// This is not source schema or asset import compatibility evidence.
const ownBadge = badge => ({id:'source-identity-'+badge.id,
  title:badge.selected ? 'Selected fixture' : 'Fixture',systemImage:'star'});
const ownMail = mail => ({...mail,rewards:mail.rewards.map(reward => reward.type === 'badge'
  ? {type:'badge',item:ownBadge(reward.item)} : reward)});
const inbox = [
  {id:id('A'),subject:'QA',body:'',timestamp:20,read:false,rewards:[{type:'xp',item:7},{type:'badge',item:badge(1,false)}]},
  {id:id('B'),subject:'QA',body:'',timestamp:10,read:true,rewards:[]},
  {id:id('C'),subject:'QA',body:'',timestamp:20,read:false,rewards:[{type:'xp',item:-3},{type:'xp',item:5},
    {type:'badge',item:badge(1,true)},{type:'badge',item:badge(2,false)}]},
];
const selections = [[],[id('A')],[id('B')],[id('C')],[id('A'),id('A'),id('C')],[id('F')]];
const inventories = [null,{badges:null},{badges:[badge(1,true),badge(1,false)]}];
const fixtures = [];
for (const inventory of inventories) for (const read of selections) for (const deleted of selections) {
  document = JSON.parse(JSON.stringify({inbox,xp:100,inventory}));
  await context.updateInbox('owned',read,deleted);
  const expected = JSON.parse(JSON.stringify(document));
  await context.updateInbox('owned',read,deleted);
  assert.equal(document.xp,expected.xp,'Repeated claim must not add XP again');
  assert.deepEqual(document.inbox,expected.inbox);
  assert.deepEqual(document.inventory,expected.inventory);
  fixtures.push({read,deleted,existingBadges:(inventory?.badges ?? []).map(ownBadge),expected:{xp:expected.xp,
    inbox:expected.inbox.map(ownMail),inventory:{badges:expected.inventory.badges.map(ownBadge)}}});
}
document = null;
await assert.rejects(() => context.updateInbox('owned',[],[]));
verify();
process.stdout.write(emit ? JSON.stringify({referenceCommit:pin,inbox:inbox.map(ownMail),fixtures})
  : `Inbox claim source passed (${fixtures.length} selections and ${fixtures.length} retries; complete DAL/generated JS; Mongo transport only; no GUI)\n`);
