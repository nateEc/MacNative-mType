// Execute complete pinned modules with owned tapes and bounded side effects.
// No browser, native dependency, live account, service or packaged asset.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const root = path.resolve(process.argv[2] ?? '');
assert.ok(process.argv[2], 'Pinned read-only reference required');
assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
  '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
const tsRoot = path.join(root, 'frontend/src/ts');
const local = id => path.join(tsRoot, id);
const resolve = (id, importer) => id.startsWith('.') ? path.resolve(path.dirname(importer), id) : id;
const actualFiles = new Map([
  ...['test/test-logic', 'test/events/data', 'test/events/stats', 'test/events/helpers',
    'test/events/live-cache', 'utils/strings', 'utils/numbers', 'input/handlers/keydown']
    .map(id => [local(id), local(id + '.ts')]),
  ['@monkeytype/util/numbers', path.join(root, 'packages/util/src/numbers.ts')],
  ['owned/backend-validation', path.join(root, 'backend/src/utils/validation.ts')],
]);
let state, now = 0;
const config = {mode: 'zen', language: 'english', funbox: [], oppositeShiftMode: 'off', layout: 'default',
  words: 100, time: 60, punctuation: false, numbers: false, lazyMode: false, difficulty: 'normal',
  blindMode: false, stopOnError: 'off', resultSaving: false};
const unexpected = label => () => { throw Error('Outside terminal timing probe: ' + label); };
const subscribe = () => {};
const set = property => value => { state[property] = value; };
const notice = text => state.notices.push(text);
const dom = {onChild() {}, hide() {}, show() {}};
const bindings = new Map([
  [local('config/store'), {Config: config}],
  [local('states/test'), {
    isTestActive: () => state.active, isResultCalculating: () => state.calculating,
    isRepeated: () => state.repeated, getBailedOut: () => state.bailedOut,
    getKoreanStatus: () => false, getActiveWordIndex: () => 0, getCurrentQuote: () => null,
    getIncompleteSeconds: () => 0, getIncompleteTests: () => [], getRestartCount: () => 0,
    setResultCalculating: set('calculating'), setTestActive: set('active'),
    setResultVisible: set('visible'), setIsTestInvalid: set('invalid'), setBailedOut: set('bailedOut'),
    setLastEventLog: set('eventLog'), setLastResult: set('lastResult'),
    setLastSignedOutResult: set('signedOut'),
    resetIncompleteTests: () => { state.incompleteResets++; },
    __nonReactive: {getKeymapLayout: unexpected('keymap')},
  }],
  [local('test/test-timer'), {clear: (ended, end) => {
    assert.equal(ended, true);
    modules.get(local('test/events/data')).namespace.logTestEvent('timer', end,
      {event: 'end', time: Math.floor(end / 1000), date: end});
  }}],
  [local('test/test-ui'), {onTestFinish() {}}],
  [local('utils/misc'), {promiseAnimate: async () => {}, applyReducedMotion: x => x,
    sleep: async () => {}, getMode2: () => config.mode === 'zen' ? 'zen'
      : config.mode === 'time' ? String(config.time) : String(config.words)}],
  [local('test/test-words'), {words: {get: () => state.targets.map(text => ({textWithCommit: text}))}}],
  [local('test/custom-text'), {getLimit: () => ({mode: 'none', value: 1}),
    getLimitMode: () => 'none', getLimitValue: () => 1,
    getData: () => ({text: 'owned', mode: 'repeat', pipeDelimiter: false, limit: {mode: 'none', value: 1}})}],
  [local('collections/tags'), {__nonReactive: {getActiveTags: () => []}}],
  [local('test/pace-caret'), {setLastTestWpm: set('paceWpm')}],
  [local('utils/dom'), {qs: () => dom}],
  [local('utils/env'), {isDevEnvironment: () => false}],
  [local('db'), {getSnapshot: () => ({lbOptOut: false})}],
  [local('states/core'), {getCustomTextIndicator: () => null}],
  [local('firebase'), {getAuthenticatedUser: () => state.signedIn ? {uid: 'owned-user'} : null}],
  [local('controllers/challenge-controller'), {verify: result => {
    state.challengeCalls.push(result); return null;
  }}],
  [local('ape'), {default: {results: {add: async request => {
    state.requests.push(request);
    return {status: 503, body: {message: 'Owned synthetic refusal; no network'}};
  }}}}],
  ['object-hash', {default: () => 'owned-synthetic-hash'}],
  [local('states/header'), {setAccountButtonSpinner: value => state.spinner.push(value)}],
  [local('test/today-tracker'), {addSeconds: set('todaySeconds')}],
  [local('test/result'), {updateTodayTracker() {}, update: async (...args) => { state.update = args; }}],
  [local('controllers/analytics-controller'), {log: async message => { state.analytics.push(message); }}],
  [local('states/notifications'), {showNoticeNotification: notice, showErrorNotification: notice}],
  [local('events/test'), {restartTestEvent: {subscribe}}],
  [local('events/config'), {configEvent: {subscribe}}],
  [local('events/timer'), {timerEvent: {subscribe}}],
  ['throttle-debounce', {debounce: (_delay, callback) => callback}],
  [local('utils/arrays'), {lastElementFromArray: array => array.at(-1)}],
  [local('constants/keys'), {Keycode: {}}],
  [local('test/events/types'), {EVENT_LOG_VERSION: 1}],
  ['hangul-js', {default: {disassemble: unexpected('Hangul')}}],
  [local('test/funbox/list'), {getActiveFunboxesWithFunction: () => [],
    isFunboxActiveWithProperty: () => false}],
  [local('test/funbox/active'), {isFunboxActiveWithProperty: () => false}],
]);
const dormant = new Set([
  'ape', 'utils/json-data', 'test/practise-words', 'test/funbox/funbox', 'test/replay-ui',
  'controllers/challenge-controller', 'states/quote-rate', 'test/words-generator',
  'legacy-states/page-transition', 'events/keymap', 'legacy-states/remember-lazy-mode',
  'singletons/format', 'legacy-states/composition', 'constants/default-snapshot', 'utils/word-gen-error',
  'sentry', 'states/loader-bar', 'elements/test-init-failed', 'utils/quick-restart', 'input/input-element',
  'states/header', 'config/setters', 'states/modifiers', 'test/layout-emulator', 'input/handlers/insert-text',
  'utils/key-converter', 'test/shift-tracker', 'input/state',
].map(local).concat(['object-hash', '@monkeytype/schemas/shared', '@monkeytype/schemas/results',
  '@monkeytype/schemas/languages', '@monkeytype/funbox', '@monkeytype/util/trycatch', 'animejs']));
const modules = new Map(), importedNames = new Map();
const context = vm.createContext({console: {debug() {}, log() {}, error() {}}, structuredClone,
  performance: {now: () => now}, Date,
  window: {addEventListener() {}}, document: {addEventListener() {}},
  setTimeout: unexpected('timer')});
for (const [id, file] of actualFiles) {
  // Only the erased imported CharCounts type is removed for single-file stripping.
  const code = stripTypeScriptTypes(fs.readFileSync(file, 'utf8')
    .replace('import { CharCounts, countChars, isSpace }', 'import { countChars, isSpace }'), {mode: 'transform'});
  modules.set(id, new vm.SourceTextModule(code, {identifier: id, context}));
  for (const match of code.matchAll(/import\s+([\s\S]*?)\s+from\s+["']([^"']+)["'];/g)) {
    const dependency = resolve(match[2], id), clause = match[1].trim();
    const names = importedNames.get(dependency) ?? new Set();
    if (clause.startsWith('{')) {
      for (const name of clause.slice(1, clause.lastIndexOf('}')).split(',').map(x => x.trim()).filter(Boolean)) {
        names.add(name.split(/\s+as\s+/)[0]);
      }
    } else if (!clause.startsWith('*')) names.add('default');
    importedNames.set(dependency, names);
  }
}
function moduleFor(id) {
  if (modules.has(id)) return modules.get(id);
  assert.ok(bindings.has(id) || dormant.has(id), 'Unapproved adapter: ' + id);
  const values = {...(bindings.get(id) ?? {})};
  for (const name of importedNames.get(id) ?? []) values[name] ??= unexpected(id + '.' + name);
  const module = new vm.SyntheticModule(Object.keys(values), function () {
    for (const [name, value] of Object.entries(values)) this.setExport(name, value);
  }, {identifier: id, context});
  modules.set(id, module); return module;
}
const logic = modules.get(local('test/test-logic'));
await logic.link((id, importer) => moduleFor(resolve(id, importer.identifier))); await logic.evaluate();
for (const id of [local('input/handlers/keydown'), 'owned/backend-validation']) {
  const module = modules.get(id);
  await module.link((name, importer) => moduleFor(resolve(name, importer.identifier))); await module.evaluate();
}
const data = modules.get(local('test/events/data')).namespace;
const stats = modules.get(local('test/events/stats')).namespace;
const keys = modules.get(local('test/events/helpers')).namespace.keysToTrack;
const keydown = modules.get(local('input/handlers/keydown')).namespace;
const backend = modules.get('owned/backend-validation').namespace;
let count = 0;
function reset({mode = 'zen', bailedOut = false, repeated = false, targets = [], signedIn = false} = {}) {
  state = {active: true, calculating: false, repeated, bailedOut, targets, invalid: false,
    signedIn, notices: [], analytics: [], signedOut: null, update: null,
    requests: [], challengeCalls: [], spinner: [], incompleteResets: 0};
  config.mode = mode; config.resultSaving = signedIn; data.resetTestEvents(); now = 0;
  data.logTestEvent('timer', 0, {event: 'start', date: 0});
}
function press(ms, code = 'KeyA') { data.logTestEvent('keydown', ms, {code}); }
function input(ms, value = 'a', text = 'a', extra = {}) {
  data.logTestEvent('input', ms, {inputType: 'insertText', wordIndex: 0, inputValue: value,
    data: text, correct: true, ...extra});
}
async function finish(ms) { now = ms; await logic.namespace.finish(); return state.lastResult; }
function checkPresentation(result) {
  assert.equal(state.visible, true); assert.equal(state.active, false);
  assert.equal(state.update[0].testDuration, result.testDuration);
  assert.equal(state.todaySeconds, result.testDuration - result.afkDuration);
}

// A command finish has no final Enter: the strict 7000ms boundary is physical.
for (const [gap, expected] of [[0, 15], [1, 15], [6999.99, 15], [7000, 22], [7000.01, 22], [8000, 23]]) {
  reset(); press(0); input(0); press(15000, 'KeyB'); input(15000, 'ab', 'b');
  const result = await finish(15000 + gap);
  assert.equal(result.testDuration, expected); assert.equal(result.startToFirstKey, 0);
  assert.equal(result.afkDuration, gap < 7000 ? 13 : expected - 2);
  assert.equal(state.signedOut !== null, gap < 7000);
  if (gap < 7000) {
    assert.equal(result.wpm, 1.6); assert.equal(result.rawWpm, 1.6);
  }
  assert.equal(result.lastKeyToEnd, 0); checkPresentation(result); count++;
}
reset(); press(0); input(0); press(14500, 'KeyB'); input(14500, 'ab', 'b');
let result = await finish(16000);
assert.equal(result.testDuration, 14.5); assert.equal(state.signedOut, null);
assert.equal(state.update[5], true); assert.ok(state.notices.some(x => x.includes('too short'))); count++;

// Execute the real keydown -> real logging -> real finish chain, not a seeded Enter.
reset(); press(0); input(0); press(14500, 'KeyB'); input(14500, 'ab', 'b'); now = 16000;
await keydown.onKeydown({code: 'Enter', key: 'Enter', shiftKey: true, repeat: false,
  ctrlKey: false, altKey: false, metaKey: false, preventDefault() {}});
for (let i = 0; i < 30 && state.update === null; i++) await Promise.resolve();
assert.ok(state.update, 'Real finish must reach result adapter');
result = state.lastResult; assert.equal(result.testDuration, 16);
assert.ok(state.eventLog.events.some(x => x.type === 'keydown' && x.data.code === 'Enter' && x.testMs === 16000));
assert.equal(state.signedOut.testDuration, 16); assert.equal(state.update[5], false); checkPresentation(result); count++;

// Repeat events are ignored; excluded keys cannot silently extend the source clock.
assert.equal(keys.has('ShiftLeft'), false); assert.equal(keys.has('Backspace'), false);
assert.equal(keys.has('NumpadEnter'), false); assert.equal(keys.has('Enter'), true);
for (const code of ['ShiftLeft', 'Backspace', 'NumpadEnter', 'ArrowLeft']) {
  reset(); press(0); input(0); press(15000, 'KeyB'); input(15000, 'ab', 'b'); press(16000, code);
  result = await finish(16000); assert.equal(result.testDuration, 15);
  assert.ok(!state.eventLog.events.some(x => x.type === 'keydown' && x.data.code === code)); count++;
}
reset(); press(0); input(0); press(15000, 'KeyB'); input(15000, 'ab', 'b'); now = 16000;
await keydown.onKeydown({code: 'Enter', key: 'Enter', shiftKey: true, repeat: true});
assert.equal(state.lastResult, undefined); result = await finish(16000);
assert.equal(result.testDuration, 15); count++;

// Physical clock and insertText AFK are separate. Bailout bypasses AFK rejection.
for (const bailedOut of [false, true]) {
  reset({bailedOut}); press(0); input(0); press(23000, 'Enter');
  result = await finish(23000); assert.equal(result.testDuration, 23);
  assert.equal(state.update[3], !bailedOut); assert.equal(state.update[5], false);
  assert.equal(state.signedOut !== null, bailedOut); count++;
}
reset({bailedOut: true}); press(0); input(0); press(15000, 'KeyB'); input(15000, 'ab', 'b');
result = await finish(16000); assert.equal(result.bailedOut, true);
assert.equal(state.signedOut.bailedOut, true); assert.equal(state.invalid, false); count++;

// Source timer grids, stopped insertText, wall clock and rounding are observable.
reset(); press(0); input(0); press(15000, 'KeyB'); input(15000, 'a', 'x', {inputStopped: true});
result = await finish(16000); assert.equal(result.charTotal, 1); assert.equal(result.acc, 100);
assert.equal(result.testDuration, 15); assert.equal(state.update[3], false); count++;
for (const [mode, duration] of [['zen', 15.13], ['custom', 15.125]]) {
  reset({mode, bailedOut: mode === 'custom'}); press(0); input(0); press(15125, 'KeyB'); input(15125, 'ab', 'b');
  result = await finish(16125); assert.equal(result.testDuration, duration); count++;
}
reset(); input(0); input(15000, 'ab', 'b'); result = await finish(16000);
assert.equal(result.testDuration, 16); assert.equal(result.lastKeyToEnd, 0); count++;
reset(); press(-100, 'KeyA'); press(-50, 'KeyB'); input(0); press(15000, 'KeyC'); input(15000, 'ab', 'b');
data.logTestEvent('keydown', 17000, {code: 'KeyD'}); result = await finish(16000);
assert.deepEqual(Array.from(state.eventLog.events.filter(x => x.type === 'keydown'), x => x.testMs), [-50, 15000]);
assert.equal(result.testDuration, 15); count++;

// Backend time/word/custom bailout minima are distinct from frontend qualification.
for (const mode of ['time', 'words', 'custom', 'zen']) {
  for (const duration of [14.99, 15]) {
    const value = {mode, mode2: mode === 'time' ? '60' : mode === 'words' ? '100' : 'zen',
      bailedOut: true, testDuration: duration, customText: {limit: {mode: 'word', value: 100}}};
    assert.equal(backend.isTestTooShort(value), duration < 15); count++;
  }
}

// Frontend may retain a short finite bailout which backend refuses. Keep both
// observable contracts instead of silently merging their eligibility rules.
for (const mode of ['time', 'words', 'custom']) {
  reset({mode, bailedOut: true, targets: ['ab']}); press(0); input(0);
  press(14500, 'KeyB'); input(14500, 'ab', 'b'); result = await finish(16000);
  assert.equal(result.testDuration, 14.5);
  assert.ok(state.signedOut); assert.equal(state.update[5], false);
  assert.equal(backend.isTestTooShort({...result, customText: {limit: {mode: 'none', value: 1}}}), true);
  count++;
}
for (const bailedOut of [false, true]) {
  reset({bailedOut, signedIn: true}); press(0); input(0); press(15000, 'KeyB'); input(15000, 'ab', 'b');
  result = await finish(16000);
  assert.equal(state.requests.length, 1);
  assert.equal(state.requests[0].body.result.bailedOut, bailedOut);
  assert.equal(state.requests[0].body.result.testDuration, 15);
  assert.equal(state.challengeCalls.length, bailedOut ? 0 : 1);
  assert.equal(state.incompleteResets, 1);
  assert.deepEqual(state.spinner, [true, false]);
  assert.equal(state.update[7], false); // Validity at result update, not synthetic request success.
  count++;
}
console.log(`${count} owned terminal timing/finish fixtures passed (${actualFiles.size} complete actual modules; real event storage/cleanup/key handling/stats/finish/backend length check and authenticated save prefix, synthetic 503 transport/hash/identity/UI/timer-end, no success-save/browser/IME/native parity claim).`);
