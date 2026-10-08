// QA only: actual modal declaration, complete name lookup and remote validator.
// Owned modal/schema/collection/API adapters, not Zod/TanStack/Solid/HTTP.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(), '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
}
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function between(source, start, end) {
  assert.equal(source.split(start).length, 2);
  const offset = source.indexOf(start), finish = source.indexOf(end, offset);
  assert.ok(finish > offset); return source.slice(offset, finish);
}
verify();
let rows = [], remoteCalls = 0, response, sent;
const context = vm.createContext({getSnapshot: () => ({name:'Owner'}), connectionsQuery: () => rows,
  z:{object: value => value}, UserNameSchema:{}, showSimpleModal: options => { context.options = options; },
  Ape:{users:{getNameAvailability: async () => { remoteCalls++; if (response instanceof Error) throw response; return response; }}},
  addConnection: async value => { sent = value; }});
function run(code) {
  new vm.Script(stripTypeScriptTypes(code.replace(/^export /gm, ''), {mode:'transform'}))
    .runInContext(context, {timeout:1000});
}
run(between(read('frontend/src/ts/collections/connections.ts'), 'export function findConnectionToUser(', '\nexport async function invalidateConnections(') + '\nglobalThis.findConnectionToUser = findConnectionToUser;');
run(between(read('frontend/src/ts/utils/remote-validation.ts').replace(/^import .*;\r?\n/gm, ''), 'type IsValidResponseOrFunction', '\nexport function remoteValidationForm<') + '\nglobalThis.remoteValidation = remoteValidation;');
const source = between(read('frontend/src/ts/components/pages/connections/FriendsList.tsx'), 'export function FriendsList()', '\nfunction getColumns(');
const start = source.indexOf('showSimpleModal({'), close = '\n            })', end = source.indexOf(close, start);
assert.equal(source.split('showSimpleModal({').length, 2); assert.ok(start >= 0 && end > start);
run(source.slice(start, end + close.length));
assert.equal(context.options.inputs.receiverName.validation.debounceDelay, 1000);
const validate = context.options.inputs.receiverName.validation.isValid, fixtures = [];
for (const isSelf of [false, true]) for (const relation of ['none','outgoing','incoming','friend','blocked']) {
  for (const lookup of ['exists','unknown','notFound','unavailable','networkError']) {
    const name = isSelf ? 'Owner' : 'Target'; remoteCalls = 0;
    rows = relation === 'none' ? [] : [{initiatorName: relation === 'incoming' || relation === 'blocked' ? 'Target' : 'Owner',
      receiverName: relation === 'incoming' || relation === 'blocked' ? 'Owner' : 'Target',
      status: relation === 'friend' ? 'accepted' : relation === 'blocked' ? 'blocked' : 'pending'}];
    response = lookup === 'networkError' ? new Error('Owned transport error') : {
      status: lookup === 'notFound' ? 404 : lookup === 'unavailable' ? 503 : 200,
      body:{data:{available:lookup !== 'exists'},message:'Owned response'}};
    let valid = false, threw = false;
    try { valid = await validate(name) === true; } catch { threw = true; }
    assert.equal(valid, !isSelf && relation === 'none' && lookup === 'exists');
    assert.equal(remoteCalls, !isSelf && relation === 'none' ? 1 : 0);
    assert.equal(threw, !isSelf && relation === 'none' && lookup === 'networkError');
    fixtures.push({isSelf,relation,lookup,valid,remoteCalls});
  }
}
const outcome = await context.options.execFn({receiverName:'Target'});
assert.equal(sent.receiverName, 'Target'); assert.equal(outcome.status, 'success'); assert.equal(outcome.showNotification, false);
verify();
if (emit) process.stdout.write(JSON.stringify(fixtures));
else console.log('Add friend source passed (50 actual modal/whole collection lookup/whole remote validation cases, captured 1000ms delay and send callback; owned adapters, no schema/TanStack/Solid/HTTP claim)');
