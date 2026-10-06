// QA only. Execute complete bounded source functions, not copied application
// code. Owned numeric/UI/HTTP adapters isolate completion and failed retries;
// this is not evidence for browser UI, successful PB storage or official API.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? '');
assert.ok(process.argv[2] && !process.argv[3]);
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git', ['-C',root,'rev-parse','HEAD'], {encoding:'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C',root,'status','--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/test/test-logic.ts'), 'utf8');
function bounded(text, start, end) {
  assert.equal(text.split(start).length, 2, 'unique function start');
  const from = text.indexOf(start), to = text.indexOf(end, from + start.length);
  assert.ok(to > from, 'complete function boundary');
  return text.slice(from, to).replace(/^export /, '');
}
const bodies = [
  bounded(source, 'function buildCompletedEvent(', 'export async function finish('),
  bounded(source, 'async function saveResult(', 'export function fail('),
  bounded(source, 'export async function retrySavingResult(', 'function buildCompletedEvent('),
  bounded(fs.readFileSync(path.join(root, 'frontend/src/ts/components/modals/LastSignedOutResultModal.tsx'), 'utf8'),
    'export function updateUidAndHash(', 'authEvent.subscribe('),
].join('\n');
let selected = ['owned-before-completion'], reads = 0;
const posts = [];
const retrySaving = {completedEvent:null, canRetry:false};
const noop = () => {};
const context = vm.createContext({
  structuredClone, console:{log:noop}, retrySaving,
  __nonReactive:{getActiveTags:() => { reads++; return selected.map(_id => ({_id})); }},
  Config:{mode:'words', language:'owned', resultSaving:true, punctuation:false, numbers:false,
    lazyMode:false, difficulty:'normal', blindMode:false, stopOnError:'off', funbox:[]},
  getChars:() => ({correctWord:75, allCorrect:75, incorrect:0, extra:0, missed:0}),
  getTestDurationMs:() => 15000, getBurstHistory:() => [60,60], getAfkDuration:() => 0,
  Numbers:{stdDev:() => 0, mean:() => 60, kogasa:() => 100, roundTo2:x => x},
  getKeypressSpacing:() => [100,100], getWpmHistory:() => [60,60], getErrorCountHistory:() => [0,0],
  getCurrentQuote:() => undefined, calculateWpm:() => 60, getAccuracy:() => ({percentage:100}),
  getBailedOut:() => false, Misc:{getMode2:() => 25}, getRestartCount:() => 0,
  getIncompleteTests:() => 0, getIncompleteSeconds:() => 0,
  getLastKeypressToEndMs:() => 0, getStartToFirstKeypressMs:() => 100,
  getKeypressDurations:() => [50], getKeypressOverlap:() => 0,
  objectHash:() => 'owned-hash-adapter', setAccountButtonSpinner:noop,
  qs:() => ({show:noop, hide:noop}), showNoticeNotification:noop, showErrorNotification:noop,
  Ape:{results:{add:async ({body}) => {
    posts.push(structuredClone(body.result));
    return {status:503, body:{message:'owned transient failure'}};
  }}},
});
new vm.Script(stripTypeScriptTypes(bodies, {mode:'transform'})).runInContext(context);
async function check(ids) {
  selected = ['owned-at-start'];
  selected = ids; // Selection can change while the test is running.
  const event = context.buildCompletedEvent({});
  event.uid = 'owned-user';
  assert.deepEqual(Array.from(event.tags), ids);
  const capturedReads = reads;
  await context.saveResult(event, false);
  // Mutating a caller-owned event or current selection cannot rewrite retry.
  event.tags = ['owned-mutated-event']; selected = ['owned-after-completion'];
  await context.retrySavingResult();
  selected = []; await context.retrySavingResult();
  for (const posted of posts.splice(0)) assert.deepEqual(Array.from(posted.tags), ids);
  assert.deepEqual(Array.from(retrySaving.completedEvent.tags), ids);
  assert.equal(reads, capturedReads, 'network saving must not read active tags');
}
await check(['owned-at-completion-a','owned-at-completion-b']);
await check([]);
selected = [];
const signedOut = context.buildCompletedEvent({});
selected = ['owned-login-selection'];
const claimed = context.updateUidAndHash('owned-login-user', signedOut);
assert.equal(claimed.uid, 'owned-login-user');
assert.deepEqual(Array.from(claimed.tags), []);
verify();
console.log('Account tag capture source passed (completion selection; 6 failed POSTs; immutable retry; signed-out claim; 4 complete bounded functions; owned adapters; no GUI)');
