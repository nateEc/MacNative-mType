// QA only. Execute pinned activation, handler, metadata and validation bodies.
// DOM/CSS and language loading are owned adapters; no reference assets load.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';

const root = path.resolve(process.argv[2] ?? '');
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
let events = [], notices = [], errors = [], joining = false;
const element = {show() {}, hide() {}, setAttribute() {}, getAttribute: () => ''};
const context = vm.createContext({Config:{}, MemoryTimer:{reset() {}},
  qs: () => element, qsa: () => ({remove() {}}),
  setFunboxBodyClasses: async () => {}, applyFunboxCSS: async () => {},
  JSONData:{getCurrentLanguage: async () => ({joiningScript:joining})},
  tryCatch: async promise => ({data:await promise}),
  showNoticeNotification: (_message, options) => notices.push({important:options?.important ?? false}),
  showErrorNotification: message => errors.push(message),
});
function load(relative, start, names, end) {
  const source = fs.readFileSync(path.join(root, relative), 'utf8');
  const first = source.indexOf(start), last = end ? source.indexOf(end, first) : source.length;
  assert.ok(first >= 0 && last > first, `Missing pinned section ${relative}: ${start}`);
  const body = stripTypeScriptTypes(source.slice(first,last).replace(/^export /gm,''), {mode:'transform'});
  vm.runInContext(`(() => {${body}\nObject.assign(globalThis, {${names.join(',')}});})()`, context);
}
load('packages/util/src/arrays.ts','export function intersect', ['intersect']);
load('packages/util/src/numbers.ts','export function isSafeNumber', ['safeNumber']);
load('packages/funbox/src/list.ts','const list: Record', ['getObject','getFunbox']);
context.getFunboxObject = context.getObject;
load('packages/funbox/src/validation.ts','export function checkForcedConfig', ['checkCompatibility','checkForcedConfig']);
load('frontend/src/ts/test/funbox/funbox-functions.ts','const list: Partial', ['getFunboxFunctions']);
load('frontend/src/ts/test/funbox/active.ts','const metadata =', ['getActiveFunboxNames','isFunboxActiveWithProperty']);
load('frontend/src/ts/test/funbox/list.ts','type FunboxMetadataWithFunctions', ['getActiveFunboxes','getActiveFunboxesWithFunction']);
load('frontend/src/ts/test/funbox/funbox.ts','export async function clear(', ['clear'], 'export async function activate(');
load('frontend/src/ts/test/funbox/funbox.ts','export async function activate(', ['activate'], 'export async function rememberSettings(');

// Controlled generic setter endpoint. Its dependent keymap setter and tape
// refusal are separately covered by the full setter/projection source probe.
context.setConfig = (key, value, options = {}) => {
  if (key === 'showAllLines' && value && context.Config.tapeMode !== 'off') return false;
  if (key === 'keymapLayout' && context.Config.keymapMode === 'off') {
    context.setConfig('keymapMode','static',options);
  }
  const previousValue = structuredClone(context.Config[key]);
  context.Config[key] = structuredClone(value);
  events.push({key, previousValue, newValue:structuredClone(value), nosave:options.nosave ?? false});
  return true;
};
const handlers = ['simon_says','tts','layout_mirror','layoutfluid','memory'];
const metadata = context.getObject();
assert.deepEqual(Object.values(metadata).filter(fb => fb.frontendFunctions?.includes('applyConfig')).map(fb => fb.name).sort(),
  [...handlers].sort());
const guards = Object.values(metadata).filter(fb => fb.properties?.includes('noJoiningScript')).map(fb => fb.name);
assert.equal(guards.length,5);
const chains = [[], ...handlers.map(name => [name]),
  ...handlers.flatMap(a => handlers.filter(b => a !== b).map(b => [a,b])),
  ...guards.flatMap(name => [[name],['rot13',name],[name,'memory'],[name,'polyglot']]),
].filter(names => context.checkCompatibility(names));
const fixtures = [];
for (const funbox of chains) for (const language of ['english','arabic']) {
  for (const keymapMode of ['off','static','next','react']) for (const layout of ['default','dvorak']) {
    for (const tapeMode of ['off','letter']) for (const customLayoutfluid of [['qwerty','colemak'],['dvorak','qwerty']]) {
      const current = {mode:'words', words:4, time:15, numbers:false, punctuation:false, highlightMode:'letter',
        funbox, language, keymapMode, layout, keymapLayout:'qwerty', showAllLines:false, tapeMode,
        customLayoutfluid, customPolyglot:['arabic','english']};
      context.Config = structuredClone(current); joining = language === 'arabic';
      events = []; notices = []; errors = [];
      await context.activate();
      assert.deepEqual(errors,[]);
      const after = structuredClone(context.Config), firstEvents = structuredClone(events), firstNotices = structuredClone(notices);
      events = []; notices = [];
      await context.activate();
      assert.deepEqual(errors,[]);
      assert.deepEqual(context.Config,after);
      assert.ok([...firstEvents,...events].every(event => event.nosave === true));
      assert.ok(firstNotices.every(notice => notice.important === false));
      fixtures.push({current, after, events:firstEvents, notices:firstNotices, repeatedEvents:structuredClone(events),
        repeatedNotices:structuredClone(notices)});
    }
  }
}
assert.ok(fixtures.length > 1000);
// A dev-tools-corrupted array bypasses the schema. Keep its raw source
// fallback separate from the admitted native configuration matrix.
context.Config = {...structuredClone(fixtures.find(f => f.current.funbox.join() === 'layoutfluid').current), customLayoutfluid:[]};
joining = false; events = []; notices = []; errors = [];
await context.activate();
assert.deepEqual(errors,[]);
assert.equal(context.Config.layout,'qwerty'); assert.equal(context.Config.keymapLayout,'qwerty');
const rawEmptyLayoutFallback = context.Config.layout;
// Memory and selection are real pinned bodies. The generic setter endpoint
// remains an owned adapter, including the separately source-tested constraints.
load('frontend/src/ts/config/funbox-validation.ts','export function canSetConfigWithCurrentFunboxes',
  ['canSetConfigWithCurrentFunboxes','canSetFunboxWithConfig']);
load('frontend/src/ts/test/funbox/funbox-memory.ts','let settingsMemory', ['save','load']);
context.FunboxMemory = {load:context.load};
load('frontend/src/ts/test/funbox/funbox.ts','export function setFunbox(', ['setFunbox'], 'export async function clear(');
load('frontend/src/ts/test/funbox/funbox.ts','export async function rememberSettings(', ['rememberSettings'], 'async function setFunboxBodyClasses(');
const activationSetter = context.setConfig;
context.setConfig = (key,value,options = {}) => {
  if (key === 'funbox' && (!context.checkCompatibility(value) ||
    value.some(name => !context.canSetFunboxWithConfig(name,context.Config).ok))) return false;
  if (!context.canSetConfigWithCurrentFunboxes(key,value,context.Config.funbox)) return false;
  return activationSetter(key,value,options);
};
const memoryNames = Object.values(metadata).filter(fb => fb.frontendFunctions?.includes('rememberSettings')).map(fb => fb.name);
assert.equal(memoryNames.length,14);
const memoryFixtures = [];
for (const name of memoryNames) for (const keymapMode of ['off','static','next','react']) {
  for (const layout of ['default','dvorak']) for (const selection of [[],['rot13']]) {
    context.load();
    const current = {mode:'words', words:4, time:15, numbers:false, punctuation:false, highlightMode:'letter',
      funbox:[name], language:'english', keymapMode, layout, keymapLayout:'qwerty', showAllLines:false, tapeMode:'off',
      customLayoutfluid:['qwerty','colemak'], customPolyglot:['english','german']};
    context.Config = structuredClone(current); joining = false; events = []; notices = []; errors = [];
    await context.rememberSettings();
    await context.activate();
    // Another restart must not replace the values remembered before activation.
    await context.rememberSettings();
    await context.activate();
    const activated = structuredClone(context.Config);
    events = []; context.setFunbox(selection);
    assert.deepEqual(errors,[]);
    memoryFixtures.push({current,activated,selection,after:structuredClone(context.Config),events:structuredClone(events)});
  }
}
context.load();
{
  const current = {...structuredClone(memoryFixtures.find(f => f.current.funbox[0] === 'simon_says').current), mode:'quote'};
  context.Config = structuredClone(current); events = []; notices = []; errors = [];
  await context.rememberSettings(); await context.activate();
  const activated = structuredClone(context.Config), selection = ['binary'];
  events = []; context.setFunbox(selection);
  assert.deepEqual(context.Config.funbox,['simon_says']);
  assert.equal(context.Config.keymapMode,'off');
  memoryFixtures.push({current,activated,selection,after:structuredClone(context.Config),events:structuredClone(events)});
  context.load();
}
verify();
process.stdout.write(JSON.stringify({fixtures, rawEmptyLayoutFallback, memoryFixtures}));
