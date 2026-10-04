// Execute two complete pinned source modules, without copying their behavior.
// Restart stops at an explicitly pending fade-out boundary: no init/generator,
// browser events, real notifications, storage, timers or device evidence.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const root = path.resolve(process.argv[2] ?? '');
assert.ok(process.argv[2], 'Read-only reference checkout required');
assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
  '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
const tsRoot = path.join(root, 'frontend/src/ts');
const key = (id, file) => id.startsWith('.') ? path.resolve(path.dirname(file), id) : id;
const local = id => path.join(tsRoot, id);
let state, notices, mutations, fades;
const config = {mode: 'zen', repeatedPace: true, resultSaving: false, repeatQuotes: 'off', language: 'english'};
const handlers = new Map();
const unexpected = label => () => { throw Error('Outside bounded repeat probe: ' + label); };
const record = label => (...args) => mutations.push([label, ...args]);
const set = property => value => { state[property] = value; mutations.push([property, value]); };
const subscribe = () => {}; // Register only; no lifecycle event is emitted.
const bindings = new Map([
  [local('config/store'), {Config: config}],
  [local('utils/dom'), {qs: selector => {
    assert.equal(selector, '.pageTest');
    return {onChild: (event, target, callback) => {
      assert.equal(event, 'click');
      handlers.set(target, callback);
    }};
  }}],
  [local('states/notifications'), {showNoticeNotification: text => notices.push(text)}],
  [local('states/test'), {
    isTestActive: () => state.active, isTestRestarting: () => state.restarting,
    isResultCalculating: () => state.calculating, getResultVisible: () => state.visible,
    getCurrentQuote: () => null,
    setIsTestInvalid: record('invalid'), setTestActive: set('active'),
    setBailedOut: record('bailedOut'), setKoreanStatus: record('korean'),
    setIsRepeated: set('repeated'), setIsPaceRepeat: set('pace'), setIsTestRestarting: set('restarting'),
  }],
  [local('test/practise-words'), {before: {mode: null}}],
  [local('test/funbox/list'), {isFunboxActive: () => false}],
  [local('test/events/data'), {resetTestEvents: record('eventsReset')}],
  [local('test/test-timer'), {clear: record('timerClear')}],
  [local('states/modifiers'), {resetModifierState: record('modifiersReset')}],
  [local('test/replay-ui'), {pauseReplay: record('replayPause')}],
  [local('test/pace-caret'), {reset: record('paceReset')}],
  [local('states/quote-rate'), {clearQuoteStats: record('quoteStatsReset')}],
  [local('legacy-states/composition'), {setComposing: record('composing'), setData: record('compositionData')}],
  [local('utils/strings'), {clearWordDirectionCache: record('directionCacheReset')}],
  [local('test/test-ui'), {fadeOutForRestart: (source, noAnim) => {
    fades.push([source, noAnim]);
    return new Promise(() => {}); // Intentionally never enter init() or animation.
  }}],
  [local('events/test'), {restartTestEvent: {subscribe}}],
  [local('events/config'), {configEvent: {subscribe}}],
  [local('events/timer'), {timerEvent: {subscribe}}],
  ['throttle-debounce', {debounce: (_delay, callback) => callback}],
]);

// Only these dormant dependencies are permitted. Their unused named/default
// exports throw if called; namespaces without adapters have no runtime exports.
const dormant = new Set([
  'ape', 'utils/misc', 'utils/json-data', 'test/custom-text', 'test/funbox/funbox', 'db',
  'collections/tags', 'test/today-tracker', 'controllers/challenge-controller', 'test/result',
  'states/core', 'test/test-words', 'test/words-generator', 'legacy-states/page-transition',
  'controllers/analytics-controller', 'firebase', 'events/keymap', 'legacy-states/remember-lazy-mode',
  'singletons/format', 'constants/default-snapshot', 'utils/word-gen-error', 'sentry',
  'states/loader-bar', 'elements/test-init-failed', 'utils/quick-restart', 'input/input-element',
  'states/header', 'config/setters', 'test/events/stats', 'test/events/live-cache', 'utils/numbers',
  'utils/env', 'test/events/types', 'utils/arrays', 'modals/practise-words', 'commandline/types',
  'test/test-screenshot',
].map(local).concat([
  '@monkeytype/util/numbers', 'object-hash', '@monkeytype/schemas/shared',
  '@monkeytype/schemas/results', '@monkeytype/funbox', '@monkeytype/util/trycatch', 'animejs',
]));
const context = vm.createContext({
  console,
  window: {addEventListener: () => {}}, document: {addEventListener: () => {}},
  setTimeout: unexpected('setTimeout'), navigator: {},
});
const sources = new Map();
function sourceModule(relative) {
  const file = path.join(tsRoot, relative);
  const code = stripTypeScriptTypes(fs.readFileSync(file, 'utf8'), {mode: 'transform'});
  sources.set(file, code);
  return new vm.SourceTextModule(code, {identifier: file, context});
}
const logic = sourceModule('test/test-logic.ts');
const commands = sourceModule('commandline/lists/result-screen.ts');
async function link(id, importer) {
  const dependency = key(id, importer.identifier);
  if (dependency === local('test/test-logic')) return logic;
  assert.ok(bindings.has(dependency) || dormant.has(dependency), 'Unapproved dependency: ' + id);
  const values = {...(bindings.get(dependency) ?? {})};
  const code = sources.get(importer.identifier);
  // Parse export names for linker adapters only, never select/extract behavior.
  const imported = [...code.matchAll(/import\s+([\s\S]*?)\s+from\s+["']([^"']+)["'];/g)]
    .find(match => match[2] === id)?.[1];
  assert.ok(imported, 'Import clause missing: ' + id);
  if (imported.startsWith('{')) {
    for (const entry of imported.slice(1, imported.lastIndexOf('}')).split(',').map(x => x.trim()).filter(Boolean)) {
      const name = entry.split(/\s+as\s+/)[0];
      values[name] ??= unexpected(id + '.' + name);
    }
  } else if (!imported.startsWith('*')) {
    values.default ??= unexpected(id + '.default');
  }
  return new vm.SyntheticModule(Object.keys(values), function () {
    for (const [name, value] of Object.entries(values)) this.setExport(name, value);
  }, {context});
}
await logic.link(link);
await logic.evaluate();
await commands.link(link);
await commands.evaluate();
const repeatCommand = commands.namespace.default.find(command => command.id === 'repeatTest');
const nextCommand = commands.namespace.default.find(command => command.id === 'nextTest');
assert.ok(repeatCommand && nextCommand);
const repeatButton = handlers.get('#restartTestButtonWithSameWordset');
assert.ok(repeatButton);
function reset(mode, repeatedPace = true) {
  config.mode = mode; config.repeatedPace = repeatedPace;
  state = {active: false, restarting: false, calculating: false, visible: true, repeated: false, pace: false};
  notices = []; mutations = []; fades = [];
}
function assertRestart(repeated, pace) {
  assert.equal(state.repeated, repeated);
  assert.equal(state.pace, pace);
  assert.equal(state.restarting, true);
  assert.equal(state.visible, true, 'Probe stops before source hides result');
  assert.deepEqual(fades, [['resultPage', false]]);
  assert.ok(mutations.length > 0);
  assert.deepEqual(notices, []);
}
let count = 0;
for (const mode of ['time', 'words', 'quote', 'zen', 'custom']) {
  for (const pace of [false, true]) {
    for (const origin of ['button', 'command']) {
      reset(mode, pace);
      assert.equal(repeatCommand.available(), true);
      const before = {...state};
      (origin === 'button' ? repeatButton : repeatCommand.exec)();
      if (mode === 'zen' && origin === 'button') {
        assert.deepEqual(state, before); assert.deepEqual(mutations, []); assert.deepEqual(fades, []);
        assert.equal(notices.length, 1); assert.ok(notices[0].includes('zen'));
      } else {
        assertRestart(true, pace);
      }
      count++;
    }
  }
  reset(mode); state.visible = false;
  assert.equal(repeatCommand.available(), false); // Do not invoke a hidden command.
  assert.deepEqual(mutations, []); count++;
  for (const guard of ['restarting', 'calculating']) {
    for (const origin of ['button', 'command']) {
      reset(mode); state[guard] = true;
      const before = {...state};
      (origin === 'button' ? repeatButton : repeatCommand.exec)();
      assert.deepEqual(state, before); assert.deepEqual(mutations, []); assert.deepEqual(fades, []);
      assert.equal(notices.length, mode === 'zen' && origin === 'button' ? 1 : 0);
      count++;
    }
  }
  reset(mode); nextCommand.exec(); assertRestart(false, false); count++;
}
for (const pace of [false, true]) {
  reset('zen', pace); repeatButton();
  assert.equal(notices.length, 1);
  notices = []; assert.equal(repeatCommand.available(), true);
  repeatCommand.exec(); assertRestart(true, pace); count++;
}
reset('zen'); void logic.namespace.restart({withSameWordset: true}); assertRestart(true, true); count++;
console.log(`${count} owned repeat-entry fixtures passed (two complete actual modules; DOM registration and restart prefix through pending fade-out only, no init/animation/storage/browser/device parity claim).`);
