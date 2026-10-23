// QA only: execute pinned bulk lifecycle, setters, Funbox checks and event bus.
// Owned defaults/migration/schema/persistence adapters; not website JSON parsing,
// complete config metadata, Solid store reactivity or browser timing coverage.
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
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const frontend = file => read('frontend/src/ts/' + file);
function between(source, start, end) {
  assert.equal(source.split(start).length, 2, start);
  const from = source.indexOf(start), to = source.indexOf(end, from + start.length);
  assert.ok(to > from, end);
  return source.slice(from, to);
}
async function moduleIn(context, source, bindings = {}) {
  bindings = {'@monkeytype/schemas/configs': {Config: undefined, ConfigValue: undefined, FunboxName: undefined},
    './types': {FunboxMetadata: undefined, FunboxForcedConfig: undefined}, ...bindings};
  const module = new vm.SourceTextModule(stripTypeScriptTypes(source, {mode: 'transform'}), {context});
  await module.link(id => {
    assert.ok(Object.hasOwn(bindings, id), 'Unexpected import: ' + id);
    const values = bindings[id];
    return new vm.SyntheticModule(Object.keys(values), function() {
      for (const [key, value] of Object.entries(values)) this.setExport(key, value);
    }, {context});
  });
  await module.evaluate();
  return module.namespace;
}
function metadataEntry(source, key) {
  const expression = between(source, '\n  ' + key + ': {', '\n  },');
  return '(' + expression.slice(expression.indexOf('{')) + '\n})';
}
verify();
async function fixture(previous = {}) {
  const defaults = {highlightMode: 'letter', funbox: [], keymapMode: 'static', minWpm: 'off',
    minAcc: 'off', minBurst: 'off', paceCaret: 'off', quoteLength: [1], words: 25,
    time: 30, mode: 'words', numbers: false, punctuation: false};
  const Config = {...structuredClone(defaults), ...previous};
  const events = [], saves = [], store = [], notices = [];
  const noop = () => {};
  const context = vm.createContext({structuredClone, console: {warn: noop}});
  const arrays = await moduleIn(context, read('packages/util/src/arrays.ts'));
  const numbers = await moduleIn(context, read('packages/util/src/numbers.ts'));
  const list = await moduleIn(context, read('packages/funbox/src/list.ts'));
  const validation = await moduleIn(context, read('packages/funbox/src/validation.ts'), {
    '@monkeytype/util/arrays': arrays, '@monkeytype/util/numbers': numbers, './list': list,
  });
  const funboxChecks = await moduleIn(context, frontend('config/funbox-validation.ts'), {
    '@monkeytype/funbox': {...list, ...validation},
  });
  const bus = await moduleIn(context, frontend('hooks/createEvent.ts'), {'solid-js': {onCleanup: noop}});
  const configEvent = bus.createEvent();
  configEvent.subscribe(event => events.push(structuredClone(event)));
  const metadataContext = {checkCompatibility: validation.checkCompatibility,
    canSetFunboxWithConfig: funboxChecks.canSetFunboxWithConfig,
    showNoticeNotification: value => notices.push(value), capitalizeFirstLetter: value => value};
  Object.assign(context, metadataContext);
  // Only the two reviewed keys use real metadata. Other keys are inert adapters.
  const configMetadata = Object.fromEntries(Object.keys(defaults).map(key => [key, {key}]));
  for (const key of ['highlightMode', 'funbox']) {
    configMetadata[key] = new vm.Script(stripTypeScriptTypes(
      metadataEntry(frontend('config/metadata.tsx'), key), {mode: 'transform'})).runInContext(context);
  }
  const setters = await moduleIn(context, frontend('config/setters.ts'), {
    '@monkeytype/schemas/configs': {ConfigSchema: {shape: {}}, FunboxSchema: {}, FunboxName: undefined},
    zod: {ZodType: class {}}, '../config/persistence': {saveToLocalStorage: key => saves.push(key)},
    '../events/config': {configEvent}, '../states/notifications': {showNoticeNotification: noop},
    './funbox-validation': funboxChecks, '../utils/misc': {triggerResize: noop, escapeHTML: value => value},
    '../utils/strings': {camelCaseToWords: value => value, capitalizeFirstLetter: value => value},
    './metadata': {configMetadata}, './store': {Config, setConfigStore: noop},
    './validation': {isConfigValueValid: () => true}, '@monkeytype/util/objects': {typedKeys: Object.keys},
    '../states/test': {isTestActive: () => false},
  });
  Object.assign(context, {Config, configEvent, setConfig: setters.setConfig,
    getDefaultConfig: () => structuredClone(defaults), migrateConfig: value => structuredClone(value),
    typedKeys: Object.keys, saveToLocalStorage: key => saves.push(key),
    setFullConfigStore: value => store.push(structuredClone(value))});
  const lifecycle = between(frontend('config/lifecycle.ts'), 'const lastConfigsToApply:',
    '\nexport async function resetConfig(').replace('export async function ', 'async function ');
  new vm.Script(stripTypeScriptTypes(lifecycle, {mode: 'transform'})).runInContext(context);
  return {Config, defaults, events, saves, store, notices, set: setters.setConfig,
    apply: value => context.applyConfig({...structuredClone(defaults), ...value})};
}

const cases = [];
for (const highlight of ['letter', 'off', 'word', 'next_word']) {
  const f = await fixture({highlightMode: 'off', funbox: ['read_ahead']});
  await f.apply({highlightMode: highlight, funbox: ['read_ahead']});
  const compatible = highlight === 'letter' || highlight === 'off';
  assert.equal(f.Config.highlightMode, highlight);
  assert.deepEqual([...f.Config.funbox], compatible ? ['read_ahead'] : []);
  assert.deepEqual(f.saves, compatible ? [] : ['funbox']);
  assert.equal(f.events[0].key, 'fullConfigChange');
  assert.equal(f.events.at(-1).key, 'fullConfigChangeFinished');
  const highlightEvent = f.events.find(event => event.key === 'highlightMode');
  assert.equal(highlightEvent.previousValue, 'letter', 'Bulk resets defaults before applying fields');
  assert.equal(highlightEvent.nosave, true);
  assert.equal(f.events.some(event => event.key === 'funbox'), compatible);
  assert.deepEqual(f.store[0].funbox, ['read_ahead'], 'Store receives requested full config, not runtime result');
  cases.push({highlight, runtimeFunbox: [...f.Config.funbox], requestedFunbox: f.store[0].funbox,
    rejectedKeys: [...f.saves], previousHighlight: highlightEvent.previousValue});
}
const clear = await fixture({funbox: ['read_ahead']});
await clear.apply({highlightMode: 'word', funbox: []});
assert.equal(clear.Config.highlightMode, 'word'); assert.deepEqual([...clear.Config.funbox], []);
const direct = await fixture({funbox: ['read_ahead']});
assert.equal(direct.set('highlightMode', 'word'), false);
assert.equal(direct.Config.highlightMode, 'letter'); assert.equal(direct.events.length, 0);
assert.deepEqual(direct.saves, []);
verify();
const output = {cases, clearsPreviousFunbox: true, directConflictRejectedBeforeWrite: true};
if (option) console.log(JSON.stringify(output));
else console.log('Bulk highlight source passed: 4 lifecycle cases, prior-funbox clearing and direct-set conflict; requested store and runtime results distinguished. Owned defaults/migration/schema/other-key metadata; not full JSON import parity.');
