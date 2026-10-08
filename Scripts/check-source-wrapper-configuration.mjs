// QA only. Complete pinned setters/event bus, subscriber, wrapper/center/jump
// functions and resize callback; owned validation, DOM metrics and debounce drain.
// This is not CSS, browser timing, font rasterization or joining-script parity.
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
const read = file => fs.readFileSync(path.join(root, 'frontend/src/ts', file), 'utf8');
const transform = source => stripTypeScriptTypes(source, {mode: 'transform'});
function between(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a);
  assert.ok(a >= 0 && b > a, start);
  return source.slice(a, b);
}
const ui = read('test/test-ui.ts');
const wrapperCode = transform(between(ui, 'function updateWordWrapperClasses(', '\nfunction showWords('));
const retirementCode = transform(between(ui, 'function removeTestElements(', '\nexport function setJoiningClass('));
const centerCode = transform(between(ui, 'export async function centerActiveLine(', '\nexport function updateWordsWrapperHeight('))
  .replace(/^export async function /, 'async function ');
const subscriberStart = ui.lastIndexOf('configEvent.subscribe(');
assert.ok(subscriberStart >= 0);
const subscriberCode = transform(ui.slice(subscriberStart)); // Complete EOF subscriber, not a recreated key list.
const resizeCode = transform(between(read('ui.ts'), 'const debouncedEvent =', '\ncreateEffect('));
const triggerCode = transform(between(read('utils/misc.ts'), 'export function triggerResize(', '\n}',) + '\n}')
  .replace(/^export function /, 'function ');
const metadataSource = read('config/metadata.tsx');
const entries = [...metadataSource.matchAll(/\n  (\w+): \{/g)];
const keys = ['highlightMode', 'typedEffect', 'blindMode', 'indicateTypos', 'tapeMode',
  'hideExtraLetters', 'flipTestColors', 'colorfulMode', 'showAllLines', 'fontSize',
  'maxLineWidth', 'tapeMargin', 'fontFamily', 'keymapSize', 'theme', 'smoothLineScroll'];
function metadataExpression(key) {
  const index = entries.findIndex(entry => entry[1] === key);
  assert.ok(index >= 0 && entries[index + 1], key);
  const entry = metadataSource.slice(entries[index].index, entries[index + 1].index);
  const end = entry.lastIndexOf('\n  },');
  assert.ok(end > 0, key);
  return '(' + entry.slice(entry.indexOf('{'), end + 4) + ')';
}
async function moduleIn(context, source, bindings) {
  const module = new vm.SourceTextModule(transform(source), {context});
  await module.link(id => {
    assert.ok(bindings.has(id), 'Unexpected dependency: ' + id);
    const values = bindings.get(id);
    return new vm.SyntheticModule(Object.keys(values), function() {
      for (const [name, value] of Object.entries(values)) this.setExport(name, value);
    }, {context});
  });
  await module.evaluate();
  return module.namespace;
}
async function fixture(showAllLines = false) {
  const Config = {mode: 'words', showAllLines, smoothLineScroll: false, tapeMode: 'off',
    fontFamily: 'Roboto_Mono', fontSize: 2, highlightMode: 'letter', typedEffect: 'off',
    blindMode: false, indicateTypos: 'off', hideExtraLetters: false, flipTestColors: false,
    colorfulMode: false, maxLineWidth: 0, tapeMargin: 50, keymapSize: 1, keymapMode: 'static',
    theme: 'serika_dark', customTheme: false, funbox: []};
  const events = [], pending = [], debounces = new Set(), timeouts = [], listeners = new Map();
  const counts = {wrapper: 0, center: 0, resize: 0, save: 0};
  let admitted = true;
  const words = Array.from({length: 4}, (_, index) => ({index, native: {isConnected: true},
    hasClass: name => name === 'word', getParent: () => wordsEl,
    getOffsetTop: () => (index - connected()[0].index) * 45,
    getOuterHeight: () => 45, getOffsetHeight: () => 33,
    remove() { this.native.isConnected = false; }}));
  const connected = () => words.filter(word => word.native.isConnected);
  const wordsEl = {native: {className: ''}, getChildren: connected, qsa: connected,
    hasClass: () => false, addClass() {}, removeClass() {}, setStyle() {}};
  const noop = () => {};
  const context = vm.createContext({Config, wordsEl, wordsWrapperEl: wordsEl,
    currentTestLine: 0, lineTransition: false, activeWordTop: 0, activeWordHeight: 0,
    centeringActiveLine: Promise.resolve(),
    console: {warn: noop, error: error => { throw error; }},
    Misc: {promiseWithResolvers: () => {
      let resolve; const promise = new Promise(done => { resolve = done; }); return {promise, resolve};
    }},
    Caret: {caret: {handleLineJump: noop}, updatePosition: noop, hide: noop, show: noop},
    PaceCaret: {caret: {handleLineJump: noop}},
    getActiveWordIndex: () => 3, getActiveWordElement: () => words[3],
    getWordElement: index => words[index]?.native.isConnected ? words[index] : null,
    getActivePage: () => 'test', getResultVisible: () => false, getCurrentInput: () => '',
    CompositionState: {getData: () => ({})}, updateWordLetters: noop,
    setTestFocusState: noop, isInputElementFocused: () => true, isLanguageRightToLeft: () => false,
    qsa: () => ({setStyle: noop}), qs: () => null,
    updateWordsWidth: noop, updateWordsWrapperHeight: noop, updateWordsMargin: noop,
    updateWordsInputPosition: noop, updateHintsPositionDebounced: noop,
    roundTo1: value => Math.round(value * 10) / 10, showNoticeNotification: noop,
    Event: class { constructor(type) { this.type = type; } },
    window: {addEventListener: (type, fn) => listeners.set(type, fn), dispatchEvent: event => {
      counts.resize++; listeners.get(event.type)?.();
    }},
    debounce: (delay, fn) => { assert.equal(delay, 250); return () => debounces.add(fn); },
    throttle: (delay, fn) => { assert.equal(delay, 250); return fn; },
    setTimeout: (fn, delay) => { assert.equal(delay, 250); timeouts.push(fn); },
  });
  const bus = await moduleIn(context, read('hooks/createEvent.ts'), new Map([['solid-js', {onCleanup: noop}]]));
  const configEvent = bus.createEvent(); context.configEvent = configEvent;
  configEvent.subscribe(event => events.push(event));
  const Joining = await moduleIn(context, read('test/break-joining.ts'), new Map([
    ['../config/store', {Config}], ['../utils/dom', {ElementWithUtils: class {}}],
  ]));
  context.Joining = Joining;
  new vm.Script(retirementCode + '\n' + centerCode + '\n' + wrapperCode + '\n' + triggerCode)
    .runInContext(context, {timeout: 1_000});
  const originalCenter = context.centerActiveLine, originalWrapper = context.updateWordWrapperClasses;
  context.centerActiveLine = () => { counts.center++; const promise = originalCenter(); pending.push(promise); return promise; };
  context.updateWordWrapperClasses = () => { counts.wrapper++; return originalWrapper(); };
  context.TestUI = {centerActiveLine: context.centerActiveLine, scrollTape: noop,
    updateHintsPositionDebounced: noop, updateWordsInputPosition: noop, focusWords: noop};
  new vm.Script(subscriberCode + '\n' + resizeCode).runInContext(context, {timeout: 1_000});
  const configMetadata = Object.fromEntries(keys.map(key => [key,
    new vm.Script(metadataExpression(key)).runInContext(context, {timeout: 1_000})]));
  const setter = await moduleIn(context, read('config/setters.ts'), new Map([
    ['@monkeytype/schemas/configs', {ConfigSchema: {shape: {}}, FunboxSchema: {}, FunboxName: {}}],
    ['zod', {ZodType: class {}}],
    ['../config/persistence', {saveToLocalStorage: () => counts.save++}],
    ['../events/config', {configEvent}], ['../states/notifications', {showNoticeNotification: noop}],
    ['./funbox-validation', {canSetConfigWithCurrentFunboxes: () => admitted, canSetFunboxWithConfig: () => ({ok: true})}],
    ['../utils/misc', {triggerResize: context.triggerResize, escapeHTML: value => value}],
    ['../utils/strings', {camelCaseToWords: value => value, capitalizeFirstLetter: value => value}],
    ['./metadata', {configMetadata}], ['./store', {Config, setConfigStore: noop}],
    ['./validation', {isConfigValueValid: () => true}],
    ['@monkeytype/util/objects', {typedKeys: Object.keys}], ['../states/test', {isTestActive: () => true}],
  ]));
  return {Config, counts, events, metadata: configMetadata, set: setter.setConfig,
    reject: () => { admitted = false; }, boundary: () => connected()[0].index,
    drain: async () => {
      await Promise.all(pending.splice(0));
      for (const fn of debounces) fn(); debounces.clear();
      await Promise.all(pending.splice(0));
      for (const fn of timeouts.splice(0)) fn();
    }};
}
const values = {highlightMode: 'off', typedEffect: 'hide', blindMode: true, indicateTypos: 'below',
  tapeMode: 'off', hideExtraLetters: true, flipTestColors: true, colorfulMode: true,
  fontSize: 2.5, maxLineWidth: 70, tapeMargin: 40, fontFamily: 'Menlo', keymapSize: 1.5,
  theme: 'nord', smoothLineScroll: false};
const wrapperKeys = new Set(keys.slice(0, 12));
const cases = [];
for (const key of keys) for (const showAllLines of [false, true]) for (const nosave of [false, true]) {
  const f = await fixture(showAllLines);
  assert.equal(f.set(key, key === 'showAllLines' ? showAllLines : values[key], {nosave}), true);
  const immediateCenter = f.counts.center;
  await f.drain();
  const wrapper = wrapperKeys.has(key) ? 1 : 0;
  const resize = f.metadata[key].triggerResize && !nosave ? 1 : 0;
  assert.equal(f.events.length, 1, key);
  assert.equal(f.counts.wrapper, wrapper, key);
  assert.equal(immediateCenter, showAllLines ? 0 : wrapper, key);
  assert.equal(f.counts.resize, resize, key);
  assert.equal(f.counts.center, immediateCenter + resize, key);
  assert.equal(f.counts.save, nosave ? 0 : 1, key);
  const boundary = !showAllLines && (wrapper || resize) ? 2 : 0;
  assert.equal(f.boundary(), boundary, key);
  cases.push({key, showAllLines, nosave, wrapper, resize, boundary});
}
const repeated = await fixture();
for (const value of [false, false, true, false]) { repeated.set('hideExtraLetters', value); await repeated.drain(); }
assert.equal(repeated.events.length, 4); assert.equal(repeated.counts.wrapper, 4);
assert.equal(repeated.boundary(), 2);
const rejected = await fixture(); rejected.reject();
assert.equal(rejected.set('highlightMode', 'word'), false); await rejected.drain();
assert.equal(rejected.events.length, 0); assert.equal(rejected.counts.center, 0);
assert.equal(rejected.boundary(), 0); assert.equal(rejected.counts.save, 0);
verify();
if (option) console.log(JSON.stringify({cases, repeatedEvents: 4, rejectedEvents: 0}));
else console.log('Wrapper configuration source passed: 64 complete setter/event/subscriber/wrapper/center/resize cases; 4 same-value/ABA events; rejected setter has no event or retirement. Owned validation, DOM metrics, debounce drain; no browser, CSS or joining-script parity claim.');
