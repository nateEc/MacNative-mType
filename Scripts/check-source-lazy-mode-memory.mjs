// QA only: execute the pinned listener and post-activation lazy-mode stage.
// Fixtures contain identifiers/booleans only; no reference word data is used.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';

const root = path.resolve(process.argv[2] ?? '');
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/test/test-logic.ts'), 'utf8');
function section(start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a);
  assert.ok(a >= 0 && b > a, `Pinned lazy stage missing: ${start}`);
  return source.slice(a, b);
}
const noLazy = {english: true, spanish: false, arabic: false, hindi: true, thai: true};
let memory, events, listener, saves, savedConfig;
const context = vm.createContext({
  Config: {}, language: {}, showedLazyModeNotification: false,
  configEvent: {subscribe: callback => { listener = callback; }},
  getActivePage: () => 'test', restart() {}, debouncedZipfCheck() {},
  showNoticeNotification() {}, showErrorNotification() {},
  configLS: {set: value => { saves += 1; savedConfig = structuredClone(value); }},
  configToSend: {}, saveToDatabase() {},
  LazyModeState: {
    getRemember: () => memory.remember, setRemember: value => { memory.remember = value; },
    getArabicPref: () => memory.prefersArabic, setArabicPref: value => { memory.prefersArabic = value; },
  },
  JSONData: {getLanguage: async name => ({name, noLazyMode: noLazy[name]})},
  tryCatch: async promise => { try { return {data: await promise}; } catch (error) { return {error}; } },
});
context.getActiveFunboxNames = () => context.Config.funbox;
// Execute this complete source function with an in-memory LS endpoint. The
// setter/schema and database transport remain controlled stubs, not a browser.
const persistence = fs.readFileSync(path.join(root, 'frontend/src/ts/config/persistence.ts'), 'utf8');
const saveStart = persistence.indexOf('export function saveToLocalStorage(');
const saveEnd = persistence.indexOf('\nexport function saveFullConfigToLocalStorage(', saveStart);
assert.ok(saveStart >= 0 && saveEnd > saveStart);
vm.runInContext(stripTypeScriptTypes(persistence.slice(saveStart, saveEnd)
  .replace('export function', 'function'), {mode: 'transform'}), context);
context.setConfig = (key, value, options = {}) => {
  const event = {key, newValue: value, previousValue: context.Config[key], nosave: options.nosave ?? false};
  context.Config[key] = value;
  context.saveToLocalStorage(key, options.nosave ?? false);
  events.push(structuredClone(event)); listener(event); return true;
};
vm.runInContext(stripTypeScriptTypes(section('configEvent.subscribe(({ key, newValue, nosave }) => {',
  '\ntimerEvent.subscribe('), {mode: 'transform'}), context);
vm.runInContext('globalThis.generate = async () => {\n' + stripTypeScriptTypes(section(
  '  const allowLazyMode =', '  if (Config.mode === "custom") {'), {mode: 'transform'}) + '\n}', context);

const fixtures = [];
const listenerStage = () => structuredClone({lazy: context.Config.lazyMode, memory, events, saves});
const operations = [null, ...['arabic', 'spanish', 'hindi'].map(value => ({key: 'language', value, nosave: false})),
  ...[false, true].flatMap(value => [false, true].map(nosave => ({key: 'lazyMode', value, nosave})))];
for (const language of ['english', 'spanish', 'arabic', 'hindi']) {
  for (const mode of ['words', 'custom']) {
    for (const components of [[], ['hindi', 'thai'], ['spanish', 'hindi']]) {
      // Post-activation fixtures: avoid the earlier RTL base-language repair.
      if (components.length && (mode !== 'words' || language === 'arabic')) continue;
      for (const lazy of [false, true]) for (const remember of [false, true]) for (const prefersArabic of [false, true]) {
        for (const operation of operations) {
          if (components.length && operation?.key === 'language' && operation.value === 'arabic') continue;
          const current = {mode, words: 4, language, lazyMode: lazy, customPolyglot: components,
            funbox: components.length ? ['polyglot'] : []};
          const before = {remember, prefersArabic};
          memory = structuredClone(before); events = []; saves = 0; savedConfig = null; context.configToSend = {};
          context.Config = structuredClone(current); context.showedLazyModeNotification = false;
          if (operation) context.setConfig(operation.key, operation.value, {nosave: operation.nosave});
          const stage = listenerStage();
          context.language = {name: context.Config.language, noLazyMode: noLazy[context.Config.language]};
          await context.generate();
          fixtures.push({current, before, operation, stage, lazy: context.Config.lazyMode, after: memory, events, saves});
        }
      }
    }
  }
}
assert.equal(fixtures.length, 848);
// The audited bulk setter order applies language before lazyMode, both nosave.
// Keep these separate from single edits so Arabic auto-enable cannot wrongly
// override the later imported value.
for (const language of ['english', 'spanish', 'arabic', 'hindi']) {
  for (const lazy of [false, true]) for (const remember of [false, true]) for (const prefersArabic of [false, true]) {
    const current = {mode: 'words', words: 4, language, lazyMode: lazy, funbox: []};
    const before = {remember, prefersArabic};
    memory = structuredClone(before); events = []; saves = 0; savedConfig = null; context.configToSend = {};
    context.Config = {mode: 'words', language: 'english', lazyMode: false, funbox: []};
    context.showedLazyModeNotification = false;
    context.setConfig('language', language, {nosave: true});
    context.setConfig('lazyMode', lazy, {nosave: true});
    const stage = listenerStage();
    context.language = {name: language, noLazyMode: noLazy[language]};
    await context.generate();
    fixtures.push({current, before, operation: null, full: true, stage, lazy: context.Config.lazyMode, after: memory, events, saves});
  }
}
assert.equal(fixtures.length, 880);
// A later saving setter serializes all runtime values, not only its own key.
memory = {remember: false, prefersArabic: true}; events = []; saves = 0;
context.Config = {language: 'spanish', lazyMode: false, mode: 'words', words: 4, funbox: []};
context.setConfig('language', 'arabic');
assert.equal(context.Config.lazyMode, true);
assert.equal(savedConfig.lazyMode, false);
context.language = {name: 'arabic', noLazyMode: false};
await context.generate();
assert.equal(saves, 1);
assert.equal(savedConfig.lazyMode, false);
context.setConfig('words', 6);
assert.equal(savedConfig.lazyMode, true);
assert.equal(savedConfig.language, 'arabic');
assert.equal(savedConfig.words, 6);
assert.equal(saves, 2);
verify();
process.stdout.write(JSON.stringify({fixtures}));
