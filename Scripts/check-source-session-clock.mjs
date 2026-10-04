// Read-only execution of the complete pinned timer module. Scheduling,
// caches, metrics and UI effects below are owned adapters, not a browser.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

assert.ok(process.argv[2], 'Pinned read-only reference required');
const root = path.resolve(process.argv[2]);
assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
  '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
const file = path.join(root, 'frontend/src/ts/test/test-timer.ts');
const code = stripTypeScriptTypes(fs.readFileSync(file, 'utf8'), {mode: 'transform'});
let fixtures = 0;

async function fixture(options = {}) {
  const config = {mode: 'time', time: 15, words: 100, funbox: [], playTimeWarning: 'off',
    minWpm: 'off', minAcc: 'off', ...options};
  const state = {now: 8_000, wall: 913_000_000_875, start: null, events: [], live: [],
    signals: [], warnings: 0, builds: 0, slow: false, lowFPS: false, active: true,
    restarts: 0, resets: 0};
  let callback, driver, api;
  const blocked = name => () => { throw Error('Outside timer probe: ' + name); };
  const effects = new Map([
    ['../config/store', {Config: config}],
    ['../config/setters', {setConfig: blocked('layout configuration')}],
    ['./custom-text', {getLimitMode: () => 'time', getLimitValue: () => config.time}],
    ['./test-words', {words: {getCurrent: blocked('word layout')}}],
    ['../states/notifications', {showNoticeNotification() {}, showErrorNotification: () => 1,
      removeNotification() {}}],
    ['./caret', {hide() {}}],
    ['../legacy-states/slow-timer', {get: () => state.slow, set: () => { state.slow = true; },
      clear: () => { state.slow = false; }}],
    ['../events/timer', {timerEvent: {dispatch: event => {
      state.signals.push(event); state.active = false; api.clear(true, state.now);
    }}}],
    ['../events/keymap', {highlight: blocked('keymap')}],
    ['../test/funbox/layoutfluid-funbox-timer', {show: blocked('layoutfluid'),
      hide: blocked('layoutfluid'), updateTime: blocked('layoutfluid')}],
    ['@monkeytype/schemas/configs', {KeymapLayout: undefined, Layout: undefined}],
    ['../controllers/sound-controller', {playTimeWarning: () => { state.warnings++; }}],
    ['../anim', {clearLowFpsMode: () => { state.lowFPS = false; },
      setLowFpsMode: () => { state.lowFPS = true; }}],
    ['animejs', {createTimer: settings => {
      callback = settings.onComplete;
      driver = {duration: settings.duration, play() {}, restart() { state.restarts++; },
        reset() { state.resets++; }};
      return driver;
    }}],
    ['./events/data', {buildEventLog: () => { state.builds++; return {}; },
      getCurrentInput: blocked('input layout'), logTestEvent: (type, ms, data) => {
        state.events.push({type, ms, data});
        if (data.event === 'start') state.start = ms;
      }}],
    ['@monkeytype/util/numbers', {roundTo2: n => Math.round(n * 100) / 100}],
    ['./events/live-cache', {getLiveCachedAccuracy: () => 100,
      getLiveCachedTestDurationMs: now => now - state.start,
      getLiveCachedTestSeconds: now => Math.floor((now - state.start) / 1_000),
      getLiveCachedTimerStartMs: () => state.start}],
    ['./events/stats', {getChars: () => ({correctWord: 5, allCorrect: 5, extra: 0, incorrect: 0})}],
    ['../utils/numbers', {calculateWpm: (chars, seconds) => chars * 12 / seconds}],
    ['../states/test', {getActiveWordIndex: () => 0, isTestActive: () => state.active,
      setCurrentLiveStats: value => { state.live.push(value); }}],
  ]);
  class CalendarDate extends Date {
    constructor(...args) { super(...(args.length ? args : [state.wall])); }
    static now() { return state.wall; }
  }
  const context = vm.createContext({Date: CalendarDate, performance: {now: () => state.now},
    console: {debug() {}, time() {}, timeEnd() {}},
    clearTimeout: blocked('legacy timeout'), setTimeout: blocked('legacy scheduling')});
  const module = new vm.SourceTextModule(code, {identifier: file, context});
  await module.link(id => {
    assert.ok(effects.has(id), 'Unapproved dependency: ' + id);
    const bindings = effects.get(id);
    return new vm.SyntheticModule(Object.keys(bindings), function () {
      for (const [name, value] of Object.entries(bindings)) this.setExport(name, value);
    }, {identifier: id, context});
  });
  await module.evaluate(); api = module.namespace;
  await api.start(state.now);
  return {state, api, driver, fire(elapsed, wall = state.wall) {
    state.now = state.start + elapsed; state.wall = wall; callback();
  }, steps: () => state.events.filter(x => x.data.event === 'step')};
}

for (const jump of [-3_600_000, 3_600_000]) {
  const f = await fixture(); const startDate = f.state.wall;
  f.fire(1_000, startDate + jump); f.fire(2_000, startDate - jump);
  assert.deepEqual(f.state.live.map(x => x.seconds), [1, 2]);
  assert.equal(f.state.live[1].wpm, 30); assert.equal(f.state.signals.length, 0);
  assert.deepEqual(f.steps().map(x => x.data.timer), [1, 2]);
  f.state.now = f.state.start + 2_125; f.api.clear(true);
  assert.equal(f.state.events[0].data.date, startDate);
  assert.equal(f.state.events.at(-1).data.date, startDate - jump);
  assert.equal(f.state.events.at(-1).ms - f.state.events[0].ms, 2_125);
  fixtures++;
}

{
  const f = await fixture(); f.fire(999.98);
  assert.equal(f.steps().length, 0); assert.equal(f.state.builds, 0);
  assert.ok(Math.abs(f.driver.duration - 0.02) < 0.000001);
  f.fire(1_000); assert.equal(f.steps().length, 1);
  f.fire(2_010); assert.equal(f.driver.duration, 990);
  assert.deepEqual(f.steps().map(x => x.data.timer), [1, 2]); fixtures++;
}

{
  const f = await fixture({mode: 'custom', time: 6, playTimeWarning: '4'});
  f.fire(3_450);
  assert.deepEqual(f.steps().map(x => [x.data.timer, x.data.catchup ?? false]),
    [[1, true], [2, true], [3, false]]);
  assert.equal(f.state.builds, 1); assert.equal(f.state.warnings, 1);
  assert.equal(f.state.live[0].seconds, 3); assert.equal(f.driver.duration, 550);
  fixtures++;
}

{
  const f = await fixture({mode: 'custom', time: 3}); f.fire(4_250);
  assert.deepEqual(f.steps().map(x => x.data.timer), [1, 2, 3]);
  assert.equal(f.state.signals[0].key, 'finish'); assert.equal(f.state.builds, 0);
  const events = f.state.events.length; f.fire(5_000);
  assert.equal(f.state.events.length, events, 'Stopped async finish cannot emit again');
  fixtures++;
}

for (const [drift, slow, failed] of [[125, false, false], [125.01, true, false],
  [250, true, false], [250.01, true, false], [500, true, false], [500.01, true, true]]) {
  const f = await fixture(); f.fire(1_000 + drift);
  assert.equal(f.state.slow, slow); assert.equal(f.state.signals.length > 0, failed);
  if (failed) assert.equal(f.state.signals[0].value, 'slow timer');
  fixtures++;
}

{
  const f = await fixture();
  for (let second = 1; second <= 5; second++) f.fire(second * 1_000 + 260);
  assert.equal(f.state.signals.length, 0);
  f.fire(6_260); assert.equal(f.state.signals[0].value, 'slow timer'); fixtures++;
}
for (const options of [{mode: 'time', time: 130}, {mode: 'words', words: 250},
  {mode: 'time', time: 0}, {mode: 'words', words: 0}]) {
  const f = await fixture(options); f.fire(1_501);
  assert.equal(f.state.signals.length, 0); assert.equal(f.state.slow, false); fixtures++;
}

console.log(`session clock source probe passed: ${fixtures} owned fixtures, 1 complete pinned module; scheduling/cache/metrics/UI are synthetic, no browser/sleep claim`);
