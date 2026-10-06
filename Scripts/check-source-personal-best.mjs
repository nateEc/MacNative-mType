// Read-only execution of the complete pinned PB utility and explicitly bounded
// DAL functions. Owned collection adapters are not MongoDB, queues or GUI QA.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv.length === 3 || process.argv.length === 4 && emit,
  'One read-only reference checkout and optional --emit-fixtures required');
const root = path.resolve(process.argv[2]);
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
let clock = 1_800_000_000_000;
class OwnedDate extends Date { static now() { return clock; } }
const context = vm.createContext({Date: OwnedDate});
let funboxes;
async function load(relative) {
  const module = new vm.SourceTextModule(stripTypeScriptTypes(
    fs.readFileSync(path.join(root, relative), 'utf8'), {mode: 'transform'}), {context, identifier: relative});
  await module.link(id => {
    // Type-only packages vanish during stripping; runtime Funbox lookup uses
    // the complete actual catalogue module, not an owned eligibility substitute.
    const names = id === '@monkeytype/schemas/configs' ? ['FunboxName'] : id === './types' ? ['FunboxMetadata']
      : id === '@monkeytype/schemas/shared' ? ['Mode', 'PersonalBest', 'PersonalBests']
      : id === '@monkeytype/schemas/results' ? ['Result'] : id === '@monkeytype/funbox' ? ['getFunbox'] : null;
    assert.ok(names, 'Unexpected dependency: ' + id);
    return new vm.SyntheticModule(names, function () {
      for (const name of names) this.setExport(name, name === 'getFunbox' ? funboxes.getFunbox : undefined);
    }, {context});
  });
  await module.evaluate();
  return module.namespace;
}
funboxes = await load('packages/funbox/src/list.ts');
const pb = await load('backend/src/utils/pb.ts');
const empty = () => ({time: {}, words: {}, quote: {}, custom: {}, zen: {}});
const result = (overrides = {}) => ({mode: 'time', mode2: '15', difficulty: 'normal', language: 'english',
  punctuation: false, numbers: false, lazyMode: false, funbox: [], wpm: 60.41, rawWpm: 70.25,
  acc: 98, consistency: 91, timestamp: 1, ...overrides});
let replacementFixtures = 0;
for (const mode of ['time', 'words', 'custom', 'zen']) {
  const mode2 = mode === 'time' ? '15' : mode === 'words' ? '25' : mode;
  const book = empty();
  const first = result({mode, mode2});
  assert.equal(pb.checkAndUpdatePb(book, undefined, first).isPb, true);
  const stored = book[mode][mode2][0];
  assert.equal(stored.wpm, 60.41);
  assert.equal(stored.raw, 70.25);
  assert.equal(stored.timestamp, clock);
  replacementFixtures++;
  const snapshot = JSON.stringify(stored);
  for (const wpm of [60.41, 60.40]) {
    clock++;
    assert.equal(pb.checkAndUpdatePb(book, undefined,
      result({mode, mode2, wpm, acc: 100, rawWpm: 99.99, consistency: 100, timestamp: clock + 100})).isPb, false);
    assert.equal(JSON.stringify(stored), snapshot, 'Ties must not replace any PB metric or timestamp');
    replacementFixtures++;
  }
  clock++;
  assert.equal(pb.checkAndUpdatePb(book, undefined, result({mode, mode2, wpm: 60.49, acc: 90})).isPb, true);
  assert.equal(stored.wpm, 60.49);
  assert.equal(stored.acc, 90);
  assert.equal(stored.timestamp, clock);
  replacementFixtures++;
}
let groupingFixtures = 0;
for (const mode of ['time', 'words', 'custom', 'zen']) {
  const mode2 = mode === 'time' ? '15' : mode === 'words' ? '25' : mode;
  const book = empty();
  for (const override of [{}, {difficulty: 'expert'}, {language: 'spanish'}, {punctuation: true},
    {numbers: true}, {lazyMode: true}]) {
    assert.equal(pb.checkAndUpdatePb(book, undefined, result({mode, mode2, ...override})).isPb, true);
    groupingFixtures++;
  }
  assert.equal(book[mode][mode2].length, 6);
  assert.equal(pb.checkAndUpdatePb(book, undefined, result({mode, mode2, funbox: ['mirror']})).isPb, false);
  groupingFixtures++;
}

// Complete bounded function bodies with source-identity guard, no copied source
// files and no production import of the reference checkout.
function bind(relative, beginAnchor, endAnchor, name) {
  const source = fs.readFileSync(path.join(root, relative), 'utf8');
  const begin = source.indexOf(beginAnchor), end = source.indexOf(endAnchor, begin + beginAnchor.length);
  assert.ok(begin >= 0 && end > begin && source.indexOf(beginAnchor, begin + 1) === -1,
    'Pinned function identity changed: ' + name);
  const code = stripTypeScriptTypes(source.slice(begin, end), {mode: 'transform'});
  new vm.Script(code.replace('export async function', 'async function')
    + `\nglobalThis.owned_${name}=${name};`).runInContext(context);
}
let persisted = {personalBests: empty(), lbPersonalBests: {time: {}}};
let writes = 0, history = [{uid: 'owned-user'}];
async function update(filter, operation) {
  assert.equal(filter.uid, 'owned-user');
  persisted = {...persisted, ...structuredClone(operation.$set)};
  writes++;
}
Object.assign(context, {canFunboxGetPb: pb.canFunboxGetPb, checkAndUpdatePb: pb.checkAndUpdatePb,
  getUsersCollection: () => ({updateOne: update}), updateUser: update,
  getResultCollection: () => ({deleteMany: async filter => {
    assert.equal(filter.uid, 'owned-user'); history = []; return {deletedCount: 1};
  }})});
bind('backend/src/dal/user.ts', 'export async function checkIfPb(', 'export async function checkIfTagPb(', 'checkIfPb');
bind('backend/src/dal/user.ts', 'export async function resetPb(', 'export async function updateLastHashes(', 'resetPb');
bind('backend/src/dal/user.ts', 'export async function clearPb(', 'export async function optOutOfLeaderboards(', 'clearPb');
bind('backend/src/dal/result.ts', 'export async function deleteAll(', 'export async function updateTags(', 'deleteAll');
const submit = overrides => context.owned_checkIfPb('owned-user', structuredClone(persisted), result(overrides));
assert.equal(await submit({lazyMode: true, wpm: 90.49}), true);
assert.equal(persisted.lbPersonalBests.time['15'], undefined);
assert.equal(await submit({wpm: 60.49}), true);
assert.equal(persisted.lbPersonalBests.time['15'].english.wpm, 90.49,
  'Nonlazy trigger selects all stored variants, including a faster lazy PB');
const beforeDelete = JSON.stringify(persisted);
await context.owned_deleteAll('owned-user');
assert.equal(history.length, 0);
assert.equal(JSON.stringify(persisted), beforeDelete, 'History deletion leaves both PB books intact');
const count = writes;
assert.equal(await submit({wpm: 60.49, acc: 100}), false);
assert.equal(writes, count, 'DAL does not persist utility mutations when isPb is false');
await context.owned_resetPb('owned-user');
assert.equal(Object.keys(persisted.personalBests.time).length, 0);
assert.equal(persisted.lbPersonalBests.time['15'].english.wpm, 90.49);
assert.equal(await submit({wpm: 45.49}), true);
assert.equal(persisted.personalBests.time['15'][0].wpm, 45.49);
assert.equal(persisted.lbPersonalBests.time['15'].english.wpm, 90.49);
await context.owned_clearPb('owned-user');
assert.equal(Object.keys(persisted.personalBests.time).length, 0);
assert.equal(Object.keys(persisted.lbPersonalBests.time).length, 0);

// A second owned trace captures actual persisted DAL outputs after every
// operation. Swift compares its own ledger to these values, not to an owned
// reimplementation of the source algorithm.
persisted = {personalBests: empty(), lbPersonalBests: {time: {}}};
clock = 1_800_000_000_000;
const trace = [];
function projection() {
  const personal = [], leaderboard = [];
  for (const [mode, buckets] of Object.entries(persisted.personalBests)) {
    for (const [mode2, values] of Object.entries(buckets)) {
      for (const value of values) personal.push({mode, mode2, ...value});
    }
  }
  for (const [mode2, languages] of Object.entries(persisted.lbPersonalBests.time)) {
    for (const value of Object.values(languages)) leaderboard.push({mode: 'time', mode2, ...value});
  }
  return structuredClone({personal, leaderboard});
}
async function step(action, overrides) {
  clock++;
  const input = action === 'submit' ? result(overrides) : null;
  let isPb = null;
  if (action === 'submit') isPb = await submit(overrides);
  else if (action === 'deleteHistory') await context.owned_deleteAll('owned-user');
  else if (action === 'resetPersonal') await context.owned_resetPb('owned-user');
  else if (action === 'clear') await context.owned_clearPb('owned-user');
  else assert.fail('Unknown owned action');
  trace.push({action, input, clock, isPb, ...projection()});
}
for (const mode of ['time', 'words', 'custom', 'zen']) {
  const mode2 = mode === 'time' ? '15' : mode === 'words' ? '25' : mode;
  for (const override of [{}, {acc: 100, rawWpm: 99.99}, {wpm: 60.40}, {wpm: 60.49},
    {difficulty: 'expert', wpm: 50.49}, {language: 'spanish', wpm: 55.49},
    {punctuation: true, wpm: 40.49}, {numbers: true, wpm: 30.49}, {lazyMode: true, wpm: 90.49, rawWpm: 100}]) {
    await step('submit', {mode, mode2, ...override});
  }
}
await step('submit', {wpm: 60.60});
await step('submit', {wpm: 60.60, acc: 100, rawWpm: 100});
await step('deleteHistory');
await step('resetPersonal');
await step('submit', {wpm: 45.49});
await step('clear');
assert.equal(trace.length, 42);
verify();
process.stdout.write(emit ? JSON.stringify({referenceCommit: pin, trace})
  : `PB source probe passed (${replacementFixtures} replacement fixtures, ${groupingFixtures} grouping fixtures, 7 DAL lifecycle steps, 42 comparison steps; owned collection adapters, no MongoDB/controller/queue/GUI)\n`);
