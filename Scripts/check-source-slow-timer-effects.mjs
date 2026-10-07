// QA only: full SlowTimer module and complete pinned timer/effect functions.
// Clock, events, drawing and scheduling are owned adapters, not a browser.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const [argument, option] = process.argv.slice(2);
assert.ok(argument && (!option || option === '--emit-fixtures'));
const root = path.resolve(argument);
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
function read(file) { return fs.readFileSync(path.join(root, 'frontend/src/ts', file), 'utf8'); }
function complete(source, first, next) {
  const start = source.indexOf(first), end = next ? source.indexOf(next, start) : source.length;
  assert.ok(start >= 0 && end > start);
  return stripTypeScriptTypes(source.slice(start, end), {mode: 'transform'}).replace(/^export /gm, '');
}
const timerSource = read('test/test-timer.ts');
const timerCode = complete(timerSource, 'function checkIfTimerIsSlow(', '\nexport async function start(')
  + complete(timerSource, 'export function clear(', '\nfunction layoutfluid(')
  + complete(timerSource, 'function checkIfFailed(', '\nfunction checkIfTimeIsUp(')
  + complete(timerSource, 'function checkIfTimeIsUp(', '\nfunction playTimeWarning(')
  + complete(timerSource, 'export async function start(', '\nasync function _startOld(');
const effectCode = complete(read('test/result.ts'), 'export function showConfetti(', '\nasync function updateTags(')
  + complete(read('elements/monkey-power.ts'), 'export async function addPower(');
const fixtures = [];
const configurations = [{mode: 'time', limit: 15}, {mode: 'time', limit: 129},
  {mode: 'time', limit: 130}, {mode: 'time', limit: 0}, {mode: 'words', limit: 249},
  {mode: 'words', limit: 250}, {mode: 'words', limit: 0},
  {mode: 'custom', limit: 15}, {mode: 'quote', limit: 0}, {mode: 'zen', limit: 0}];
for (const configuration of configurations) {
  let frameRate = 60, powerScheduled = 0, confettiCalls = 0, clock = 0;
  const Config = {mode: configuration.mode, time: configuration.limit, words: configuration.limit,
    minWpm: 'off', minAcc: 'off', minWpmCustomSpeed: 10, minAccCustom: 90, monkeyPowerLevel: '1'};
  const context = vm.createContext({Config, console: {error() {}},
    slowTimerFailEnabled: true, slowTimerCount: 0, slowTimerNotifIds: [], timerDebug: false,
    newTimer: {reset() {}, play() {}}, timer: null, stopped: false, emittedTicks: 0,
    setLowFpsMode: () => { frameRate = 30; }, clearLowFpsMode: () => { frameRate = 60; },
    showNoticeNotification() {}, showErrorNotification: () => 1, removeNotification() {},
    timerEvent: {dispatch() {}}, clearTimeout() {}, performance: {now: () => 0},
    getActiveWordIndex: () => 4, Caret: {hide() {}},
    CustomText: {getLimitMode: () => 'time', getLimitValue: () => configuration.limit},
    logTestEvent() {}, getLiveCachedTestSeconds: () => 1,
    getComputedStyle: () => ({getPropertyValue: () => '#ffffff'}), document: {body: {}},
    Date: class extends Date { static now() { return ++clock; } getTime() { return 0; } },
    confetti: () => { confettiCalls++; },
    requestAnimationFrame() {}, requestDebouncedAnimationFrame: () => { powerScheduled++; },
  });
  const module = new vm.SourceTextModule(stripTypeScriptTypes(read('legacy-states/slow-timer.ts'),
    {mode: 'transform'}), {identifier: 'slow-timer', context});
  await module.link(() => { throw new Error('Unexpected SlowTimer dependency'); });
  await module.evaluate();
  context.SlowTimer = module.namespace;
  new vm.Script(timerCode + effectCode).runInContext(context, {timeout: 1_000});
  const run = code => new vm.Script(code).runInContext(context, {timeout: 1_000});
  const eligible = (configuration.mode === 'time' && configuration.limit > 0 && configuration.limit < 130)
    || (configuration.mode === 'words' && configuration.limit > 0 && configuration.limit < 250);
  const steps = [];
  for (const action of ['start', 'boundary', 'late', 'normal', 'clear', 'normal', 'restart']) {
    if (action === 'start' || action === 'restart') await run('start(0)');
    else if (action === 'boundary') run('checkIfTimerIsSlow(125)');
    else if (action === 'late') run('checkIfTimerIsSlow(126)');
    else if (action === 'clear') run('clear()');
    else run('checkIfTimerIsSlow(0)');
    const slowTimer = module.namespace.get(), power = [];
    for (const level of ['off', '1', '2', '3', '4']) {
      Config.monkeyPowerLevel = level;
      const before = powerScheduled;
      await run('addPower()');
      assert.equal(powerScheduled - before, !slowTimer && level !== 'off' ? 1 : 0);
      power.push({level, scheduled: powerScheduled > before});
    }
    const before = confettiCalls; run('showConfetti()');
    assert.equal(confettiCalls - before, slowTimer ? 0 : 2);
    steps.push({action, slowTimer, frameRate, power, confetti: confettiCalls > before});
  }
  assert.equal(steps[1].slowTimer, false);
  assert.equal(steps[2].slowTimer, eligible);
  assert.equal(steps[4].slowTimer, eligible, 'Timer clear restores FPS but does not clear SlowTimer');
  assert.equal(steps[4].frameRate, 60);
  assert.equal(steps.at(-1).slowTimer, false);
  const endings = [];
  const endingKinds = ['clear-only', 'minimumWpm', 'minimumAccuracy', 'timerHealth'];
  if (configuration.mode === 'words') endingKinds.push('word-finish');
  if (configuration.limit > 0 && ['time', 'custom'].includes(configuration.mode)) endingKinds.push('expiry');
  for (const ending of endingKinds) {
    await run('start(0)'); run('checkIfTimerIsSlow(126)');
    Config.minWpm = ending === 'minimumWpm' ? 'custom' : 'off';
    Config.minAcc = ending === 'minimumAccuracy' ? 'custom' : 'off';
    if (ending === 'expiry' && configuration.limit > 0
      && ['time', 'custom'].includes(configuration.mode)) {
      context.testTime = configuration.limit; run('checkIfTimeIsUp(testTime)');
    } else if (ending === 'minimumWpm' || ending === 'minimumAccuracy') {
      run('checkIfFailed({wpm:0,raw:0},0)');
    } else {
      if (ending === 'timerHealth') run('checkIfTimerIsSlow(501)');
      run('clear()');
    }
    const slowTimer = module.namespace.get();
    assert.equal(slowTimer, eligible && ending !== 'minimumWpm' && ending !== 'minimumAccuracy'
      && !(ending === 'expiry' && configuration.mode === 'time'));
    endings.push({ending, slowTimer});
  }
  fixtures.push({...configuration, steps, endings});
}
verify();
assert.equal(fixtures.reduce((count, fixture) => count + fixture.endings.length, 0), 47);
if (option) console.log(JSON.stringify(fixtures));
else console.log('SlowTimer effects source passed: 10 configurations / 70 lifecycle steps / 350 power scheduling gates / 70 full confetti invocations / 47 applicable terminal paths; full state module and complete timer/effect functions; owned scheduling/drawing/clock boundaries, no browser, particles or word reflow claim');
