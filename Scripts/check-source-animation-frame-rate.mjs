// QA only: full pinned animation module and complete timer health/clear functions.
// Storage validation, Solid signals, timer scheduling and UI remain owned adapters.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
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
const archive = process.env.TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE;
assert.ok(archive, 'Pinned Anime.js archive required');
const integrity = 'sha512-' + createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
assert.equal(integrity, 'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
assert.ok(fs.readFileSync(path.join(root, 'pnpm-lock.yaml'), 'utf8').includes(integrity));
const bundle = execFileSync('tar', ['-xOf', archive, 'package/dist/bundles/anime.esm.js'],
  {encoding: 'utf8', maxBuffer: 2**21});
const {engine} = await import('data:text/javascript;base64,' + Buffer.from(bundle).toString('base64'));
const animFile = path.join(root, 'frontend/src/ts/anim.ts');
const animationCode = stripTypeScriptTypes(fs.readFileSync(animFile, 'utf8'), {mode: 'transform'});
const timerSource = fs.readFileSync(path.join(root, 'frontend/src/ts/test/test-timer.ts'), 'utf8');
function completeFunction(startText, endText) {
  const start = timerSource.indexOf(startText), end = timerSource.indexOf(endText, start);
  assert.ok(start >= 0 && end > start);
  return stripTypeScriptTypes(timerSource.slice(start, end), {mode: 'transform'})
    .replace(/^export function /, 'function ');
}
const timerCode = completeFunction('function checkIfTimerIsSlow(', '\nexport async function start(')
  + completeFunction('export function clear(', '\nfunction layoutfluid(');
const fixtures = [];
for (const initial of [15, 24, 30, 120, 1_000]) {
  const configs = [{mode: 'time', limit: 15}, {mode: 'time', limit: 129},
    {mode: 'time', limit: 130}, {mode: 'time', limit: 0}, {mode: 'words', limit: 249},
    {mode: 'words', limit: 250}, {mode: 'words', limit: 0},
    {mode: 'custom', limit: 15}, {mode: 'quote', limit: 0}, {mode: 'zen', limit: 0}];
  for (const config of configs) {
    let requested = initial, signal, failed = false;
    const schema = {int: () => schema, min: () => schema, max: () => schema};
    const context = vm.createContext({Config: {mode: config.mode, time: config.limit, words: config.limit},
      slowTimerFailEnabled: true, slowTimerCount: 0, slowTimerNotifIds: [], stopped: false,
      newTimer: {reset() {}}, timer: null, clearTimeout() {}, performance: {now: () => 0},
      console: {error() {}},
      showNoticeNotification() {}, showErrorNotification: () => 1,
      timerEvent: {dispatch: event => { assert.equal(event.value, 'slow timer'); failed = true; }}});
    const adapters = new Map([
      ['animejs', {engine}],
      ['./utils/local-storage-with-schema', {LocalStorageWithSchema: class {
        get() { return requested; }
        set(value) { assert.ok(Number.isInteger(value) && value >= 15 && value <= 1_000);
          requested = value; return true; }
      }}],
      ['zod', {z: {number: () => schema}}],
      ['solid-js', {createSignal(value) { signal = value; return [() => signal, value => { signal = value; }]; }}],
    ]);
    const module = new vm.SourceTextModule(animationCode, {identifier: animFile, context});
    await module.link(id => {
      assert.ok(adapters.has(id), 'Unexpected dependency: ' + id);
      const bindings = adapters.get(id);
      return new vm.SyntheticModule(Object.keys(bindings), function() {
        for (const [name, value] of Object.entries(bindings)) this.setExport(name, value);
      }, {identifier: id, context});
    });
    await module.evaluate();
    const slowFile = path.join(root, 'frontend/src/ts/legacy-states/slow-timer.ts');
    const slowModule = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(slowFile, 'utf8'),
      {mode: 'transform'}), {identifier: slowFile, context});
    await slowModule.link(() => { throw new Error('Unexpected SlowTimer dependency'); });
    await slowModule.evaluate();
    const api = module.namespace;
    Object.assign(context, {setLowFpsMode: api.setLowFpsMode, clearLowFpsMode: api.clearLowFpsMode,
      SlowTimer: slowModule.namespace});
    new vm.Script(timerCode).runInContext(context, {timeout: 1_000});
    api.applyEngineSettings();
    const actions = [{kind: 'observe', value: 125}, {kind: 'observe', value: 125.01},
      {kind: 'observe', value: 0}, {kind: 'set', value: 60}, {kind: 'observe', value: 0},
      {kind: 'observe', value: 250.01}, {kind: 'set', value: 1_000},
      {kind: 'observe', value: 250.01}, {kind: 'set', value: 1_000},
      {kind: 'observe', value: 500.01}, {kind: 'clear', value: 0}];
    const steps = [];
    for (const action of actions) {
      if (action.kind === 'set') assert.equal(api.setfpsLimit(action.value), true);
      else if (action.kind === 'clear') new vm.Script('clear()').runInContext(context, {timeout: 1_000});
      else { context.drift = action.value;
        new vm.Script('checkIfTimerIsSlow(drift)').runInContext(context, {timeout: 1_000}); }
      assert.equal(engine.fps, engine.defaults.frameRate);
      assert.equal(api.getfpsLimit(), requested);
      steps.push({action, frameRate: engine.fps, requested, severeDrifts: context.slowTimerCount,
        failed, slowTimer: slowModule.namespace.get()});
    }
    assert.equal(steps[0].frameRate, initial);
    if ((config.mode === 'time' && config.limit > 0 && config.limit < 130)
      || (config.mode === 'words' && config.limit > 0 && config.limit < 250)) {
      assert.equal(steps[1].frameRate, 30);
      assert.equal(steps[2].frameRate, 30);
      assert.equal(steps[9].failed, true);
      assert.equal(slowModule.namespace.get(), true);
    } else { assert.equal(steps[1].frameRate, initial); assert.equal(slowModule.namespace.get(), false); }
    assert.equal(steps[3].frameRate, 60);
    assert.equal(steps[8].frameRate, 1_000, 'Repeated native selection reapplies the setting');
    assert.equal(steps.at(-1).frameRate, requested);
    fixtures.push({initial, ...config, steps});
  }
}
verify();
assert.equal(fixtures.length, 50);
if (option) console.log(JSON.stringify(fixtures));
else console.log('Animation FPS source passed: 50 sequences / 550 transitions; full pinned anim module + complete timer health/clear functions + actual Anime.js 4.2.2 engine; owned storage/schema/signals/scheduling/UI boundaries, no browser or physical FPS claim');
