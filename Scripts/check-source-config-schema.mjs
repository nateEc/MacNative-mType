// QA only: actual pinned schema, Zod, sanitizer, defaults and migration modules.
// No original default colors/catalog assets are emitted into the application.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {createRequire, stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';
const root = path.resolve(process.argv[2] ?? '');
const zodRoot = process.env.TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT;
const runtimeMode = process.argv[3] === '--runtime-projection';
const keyboardMode = process.argv[3] === '--keyboard-confirmations';
const importMode = process.argv[3] === '--import-preparation';
const funboxMode = process.argv[3] === '--funbox-admission';
const defaultsMode = process.argv[3] === '--default-profile';
assert.ok(!process.argv[3] || runtimeMode || funboxMode || keyboardMode || importMode || defaultsMode);
assert.ok(process.argv[2] && zodRoot, 'Pinned reference and TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT required');
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
assert.equal(JSON.parse(fs.readFileSync(path.join(zodRoot, 'package.json'))).version, '3.23.8');
const zod = createRequire(import.meta.url)(path.join(zodRoot, 'lib/index.js'));
const simulation = {Config: {}, events: [], saves: [], stores: [], gates: [], flags: {}};
const noop = () => {};
const context = vm.createContext({structuredClone, URL,
  document: {get readyState() { return simulation.flags.documentComplete ? 'complete' : 'loading'; }},
  console: {warn: noop, error: noop, log: noop}});
const modules = new Map();
const schemas = path.join(root, 'packages/schemas/src');
const frontend = path.join(root, 'frontend/src/ts');
const adapters = new Map([
  [path.join(frontend, 'states/notifications.ts'), {showNoticeNotification: noop, showErrorNotification: noop}],
  [path.join(frontend, 'states/core.ts'), {isAuthenticated: () => !!simulation.flags.authenticated}],
  [path.join(frontend, 'states/test.ts'), {isTestActive: () => true}],
  [path.join(frontend, 'collections/custom-themes.ts'), {__nonReactive: {getCustomThemes: () => Array(simulation.flags.customThemeCount ?? 0).fill({})}}],
  [path.join(frontend, 'utils/env.ts'), {isDevEnvironment: () => !!simulation.flags.development}],
  [path.join(frontend, 'utils/misc.ts'), {reloadAfter: noop, triggerResize: noop, escapeHTML: value => value}],
  [path.join(frontend, 'utils/strings.ts'), {capitalizeFirstLetter: value => value, camelCaseToWords: value => value}],
  [path.join(frontend, 'utils/zod.ts'), {getOptions: () => []}],
  [path.join(frontend, 'types/font-awesome.ts'), {FaObject: undefined}],
  [path.join(frontend, 'sentry.ts'), {captureException: noop}],
  [path.join(frontend, 'config/persistence.ts'), {saveToLocalStorage: key => simulation.saves.push(key)}],
  ['solid-js', {onCleanup: noop, JSXElement: undefined}],
]);
function getModule(id) {
  if (modules.has(id)) return modules.get(id);
  let module;
  if (id === 'zod' || id === 'store-adapter' || adapters.has(id)) {
    const values = id === 'zod' ? {...zod, ZodErrorMap: undefined, ZodTypeAny: undefined, ZodIssue: undefined}
      : id === 'store-adapter' ? {Config: simulation.Config,
        setConfigStore: noop, setFullConfigStore: value => simulation.stores.push(structuredClone(value))}
      : adapters.get(id);
    module = new vm.SyntheticModule(Object.keys(values), function() {
      for (const [key, value] of Object.entries(values)) this.setExport(key, value);
    }, {context});
  } else {
    let source = fs.readFileSync(id, 'utf8');
    if (id === path.join(schemas, 'configs.ts')) source += '\nexport const Config = undefined; export const CustomThemeColors = undefined; export const ConfigValue = undefined; export const FunboxName = undefined;';
    if (id === path.join(root, 'packages/funbox/src/types.ts')) source += '\nexport const FunboxMetadata = undefined; export const FunboxProperty = undefined; export const FunboxForcedConfig = undefined;';
    module = new vm.SourceTextModule(stripTypeScriptTypes(source, {mode: 'transform'}), {context, identifier: id});
  }
  modules.set(id, module);
  return module;
}
function resolve(id, importer) {
  if (id === 'zod' || id === 'solid-js') return id;
  if (id.endsWith('/store') && importer.startsWith(path.join(frontend, 'config/'))) return 'store-adapter';
  if (id === '@monkeytype/schemas/configs') return path.join(schemas, 'configs.ts');
  if (id === '@monkeytype/util/objects') return path.join(root, 'packages/util/src/objects.ts');
  if (id === '@monkeytype/util/numbers') return path.join(root, 'packages/util/src/numbers.ts');
  if (id === '@monkeytype/util/arrays') return path.join(root, 'packages/util/src/arrays.ts');
  if (id === '@monkeytype/util/json') return path.join(root, 'packages/util/src/json.ts');
  if (id === '@monkeytype/funbox') return path.join(root, 'packages/funbox/src/index.ts');
  if (id === '../events/config') return 'config-event-adapter';
  assert.ok(id.startsWith('.'), 'Unexpected import: ' + id);
  const candidate = path.resolve(path.dirname(importer), id + '.ts');
  return adapters.has(candidate) || fs.existsSync(candidate) ? candidate : candidate + 'x';
}
async function load(id) {
  const module = getModule(id);
  if (module.status === 'unlinked') await module.link((id, importer) => getModule(resolve(id, importer.identifier)));
  if (module.status === 'linked') await module.evaluate();
  return module.namespace;
}
const migration = await load(path.join(frontend, 'config/utils.ts'));
const configSchemas = await load(path.join(schemas, 'configs.ts'));
const schema = configSchemas.PartialConfigSchema.strip();
const sanitize = (await load(path.join(frontend, 'utils/sanitize.ts'))).sanitize;
const defaults = (await load(path.join(frontend, 'constants/default-config.ts'))).getDefaultConfig();
const catalogs = {
  languages: (await load(path.join(schemas, 'languages.ts'))).LanguageSchema.options,
  themes: (await load(path.join(schemas, 'themes.ts'))).ThemeNameSchema.options,
  layouts: (await load(path.join(schemas, 'layouts.ts'))).LayoutNameSchema.options,
  fonts: (await load(path.join(schemas, 'fonts.ts'))).KnownFontNameSchema.options,
  funboxes: (await load(path.join(schemas, 'configs.ts'))).FunboxNameSchema.options,
};
function transport(value) {
  if (importMode && typeof value === 'string' && !value.isWellFormed()) {
    return {$probeUTF16: Array.from({length: value.length}, (_, i) => value.charCodeAt(i))};
  }
  if (typeof value === 'number' && !Number.isFinite(value)) return {$probeNumber: String(value)};
  if (Array.isArray(value)) return value.map(transport);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, transport(v)]));
  return value;
}
if (defaultsMode) {
  function alternatives(rule) {
    if (rule instanceof zod.ZodBoolean) return [false, true];
    if (rule instanceof zod.ZodEnum) return rule.options;
    if (rule instanceof zod.ZodLiteral) return [rule.value];
    if (rule instanceof zod.ZodUnion) return rule.options.flatMap(alternatives);
    return [];
  }
  const choices = Object.fromEntries(Object.entries(configSchemas.ConfigSchema.shape).map(([key, rule]) => [key, alternatives(rule)]));
  verify();
  console.log(JSON.stringify({defaults, catalogs, choices, orderedKeys: Object.keys(defaults)}));
} else if (funboxMode) {
  const funbox = await load(path.join(root, 'packages/funbox/src/index.ts'));
  const metadata = (await load(path.join(frontend, 'config/metadata.tsx'))).configMetadata;
  const compatibility = [];
  function add(names) { compatibility.push({names, accepted: funbox.checkCompatibility(names)}); }
  add([]);
  for (const a of catalogs.funboxes) { add([a]); for (const b of catalogs.funboxes) add([a, b]); }
  for (let a = 0; a < catalogs.funboxes.length; a++) for (let b = a; b < catalogs.funboxes.length; b++)
    for (let c = b; c < catalogs.funboxes.length; c++) add([catalogs.funboxes[a], catalogs.funboxes[b], catalogs.funboxes[c]]);
  for (const names of [['unknown'], ['mirror', 'unknown'], ['MIRROR']]) add(names);
  add(Array(16).fill('no_quit')); add(Array(16).fill('rot13'));
  const profiles = [];
  for (const mode of ['time', 'words', 'quote', 'custom', 'zen']) for (const words of [0, 1])
    for (const time of [0, 30]) for (const highlightMode of ['off', 'letter', 'word', 'next_word', 'next_two_words', 'next_three_words'])
      for (const numbers of [false, true]) for (const punctuation of [false, true]) {
        profiles.push({mode, words, time, highlightMode, numbers, punctuation, funbox: []});
      }
  for (const previous of ['no_quit', 'memory', 'read_ahead', 'layoutfluid', 'binary', 'arrows', 'mirror', 'tts'])
    for (const mode of ['time', 'words', 'quote', 'custom', 'zen'])
      for (const highlightMode of ['off', 'letter', 'word', 'next_word', 'next_two_words', 'next_three_words']) {
        profiles.push({mode, words: 50, time: 30, highlightMode, numbers: false, punctuation: false, funbox: [previous]});
      }
  const admissions = catalogs.funboxes.map(name => ({names: [name], results: profiles.map(currentConfig =>
    !metadata.funbox.isBlocked({value: [name], currentConfig}))}));
  const combined = [];
  for (const a of catalogs.funboxes) for (const b of catalogs.funboxes) {
    for (const profile of [0, 143, 287, 479, profiles.length - 1]) {
      combined.push({names: [a, b], profile,
        accepted: !metadata.funbox.isBlocked({value: [a, b], currentConfig: profiles[profile]})});
    }
  }
  verify();
  console.log(JSON.stringify({names: catalogs.funboxes, compatibility, profiles, admissions, combined}));
} else if (runtimeMode || keyboardMode || importMode) {
  const bus = (await load(path.join(frontend, 'hooks/createEvent.ts'))).createEvent();
  adapters.set('config-event-adapter', {configEvent: bus});
  bus.subscribe(event => simulation.events.push(structuredClone(event)));
  const metadata = (await load(path.join(frontend, 'config/metadata.tsx'))).configMetadata;
  const originalGate = metadata.funbox.isBlocked;
  metadata.funbox.isBlocked = options => {
    const blocked = originalGate(options);
    simulation.gates.push({value: structuredClone(options.value), current: structuredClone(options.currentConfig), accepted: !blocked});
    return blocked;
  };
  const setters = await load(path.join(frontend, 'config/setters.ts'));
  if (keyboardMode) {
    const fixtures = [];
    const options = {
      keymapMode: ['off', 'static', 'react', 'next'],
      keymapStyle: configSchemas.ConfigSchema.shape.keymapStyle.options,
      keymapLegendStyle: configSchemas.ConfigSchema.shape.keymapLegendStyle.options,
      keymapKeys: configSchemas.ConfigSchema.shape.keymapKeys.options,
      keymapSize: [0.5, 1.4, 3.5], keymapLayout: ['qwerty', 'dvorak', 'overrideSync'],
    };
    for (const mode of ['off', 'static', 'react', 'next']) for (const noQuit of [false, true])
      for (const [key, values] of Object.entries(options)) for (const value of values) {
        Object.assign(simulation.Config, structuredClone(defaults), {keymapMode: mode, funbox: noQuit ? ['no_quit'] : []});
        simulation.events = []; simulation.saves = [];
        const accepted = setters.setConfig(key, value);
        fixtures.push({mode, noQuit, key, value, accepted, resultMode: simulation.Config.keymapMode,
          resultValue: simulation.Config[key], events: simulation.events.map(event => event.key), saves: simulation.saves});
      }
    verify();
    console.log(JSON.stringify(fixtures));
  } else {
  Object.assign(context, {Config: simulation.Config, configEvent: bus,
    getDefaultConfig: () => structuredClone(defaults), migrateConfig: migration.migrateConfig,
    typedKeys: Object.keys, setConfig: setters.setConfig,
    saveToLocalStorage: key => simulation.saves.push(key),
    setFullConfigStore: value => simulation.stores.push(structuredClone(value))});
  const lifecycle = fs.readFileSync(path.join(frontend, 'config/lifecycle.ts'), 'utf8');
  const from = lifecycle.indexOf('const lastConfigsToApply:'), to = lifecycle.indexOf('\nexport async function resetConfig(', from);
  assert.ok(from >= 0 && to > from);
  new vm.Script(stripTypeScriptTypes(lifecycle.slice(from, to).replace('export async function ', 'async function '), {mode: 'transform'})).runInContext(context);
  if (importMode) {
    const parser = await load(path.join(root, 'packages/util/src/json.ts'));
    const apply = context.applyConfig;
    let parsed, completeSaves = 0, success = 0, errors = 0;
    Object.assign(context, {ConfigSchemas: configSchemas, parseJsonWithSchema: parser.parseWithSchema,
      applyConfig: async value => { parsed = structuredClone(value); await apply(value); },
      saveFullConfigToLocalStorage: () => completeSaves++,
      showSuccessNotification: () => success++, showErrorNotification: () => errors++});
    const start = lifecycle.indexOf('export async function applyConfigFromJson(');
    const end = lifecycle.indexOf('\nexport async function loadFromLocalStorage(', start);
    assert.ok(start >= 0 && end > start);
    new vm.Script(stripTypeScriptTypes(lifecycle.slice(start, end).replace('export async function ', 'async function '), {mode: 'transform'})).runInContext(context);
    const fixtures = [];
    async function add(json, flags = {}) {
      Object.assign(simulation.Config, structuredClone(defaults));
      simulation.flags = {authenticated: false, documentComplete: true, customThemeCount: 0, development: false, ...flags};
      simulation.events = []; simulation.saves = []; simulation.stores = []; simulation.gates = [];
      parsed = undefined; completeSaves = 0; success = 0; errors = 0;
      await context.applyConfigFromJson(json);
      const accepted = success === 1;
      assert.equal(success + errors, 1);
      assert.equal(completeSaves, accepted ? 1 : 0);
      assert.equal(simulation.stores.length, accepted ? 1 : 0);
      fixtures.push({json, flags: simulation.flags, accepted, parsed,
        requested: simulation.stores[0], runtime: structuredClone(simulation.Config),
        rejectedKeys: simulation.saves, events: simulation.events});
    }
    for (const json of ['', ' ', 'null', 'true', 'false', '1', '"text"', '[]', '[{}]', '{', '{"numbers":true,}', '{}{}', '/*x*/{}']) await add(json);
    await add('{}');
    // Execute the complete entry with raw JS strings; Foundation cannot decode lone surrogates.
    for (const json of ['{"future":"\\ud800"}', '{"\\ud800":1}', '{"é":1,"e\\u0301":2}',
      '{"fontSize":"1\\ud800"}', '{"fontSize":"125\\ud800"}', '{"soundVolume":"0.5\\ud800"}',
      '{"funbox":"no_quit#\\ud800"}', '{"customLayoutfluid":"qwerty#\\ud800#dvorak"}',
      '{"customBackground":"https://example.com/\\ud800.png"}',
      '{"customBackground":" \\ufeffhttps://example.com/\\udfff.png\\n "}',
      '{"show\\u212AeyTips":false}', '{"fontFamily":"\\u212Aanit"}',
      '{"keymapShowTopRow":"always","keymap\\u212Aeys":"full","numbers":"invalid"}']) await add(json);
    for (const json of ['{"numbers":false,"numbers":true}', '{"quickTab":false,"quickTab":true}',
      '{"quickTab":true,"numbers":"invalid"}', '{"quickTab":true,"numbers":true}',
      '{"ownedUnknown":{"constructor":1,"__proto__":{"x":true}}}', '{"words":-0}',
      '{"fontSize":1e400}', '{"fontSize":-1e400}', '{"words":1e400}', '{"minAccCustom":1e400}',
      '{"paceCaretCustomSpeed":1e400}', '{"customBackgroundFilter":[1,1e400,1,1]}']) await add(json);
    const legacy = [
      {quickTab: true}, {swapEscAndTab: true}, {alwaysShowCPM: true}, {showTimerProgress: false},
      {showLiveWpm: true, timerStyle: 'text'}, {showAverage: 'wpm'}, {keymapShowTopRow: 'always'},
      {smoothCaret: true}, {playSoundOnError: true}, {indicateTypos: true}, {fontSize: '125'},
      {soundVolume: '0.5suffix'}, {quoteLength: -1}, {funbox: 'none'},
      {customLayoutfluid: 'qwerty#dvorak'}, {accountChart: ['on']},
      {customThemeColors: Array(9).fill('#123456')}, {customBackgroundFilter: [1, 2, 3, 4, 5]},
    ];
    for (const input of legacy) for (const trigger of [{}, {numbers: 'invalid'}, {mode: 'invalid'}, {language: 'owned-invalid-language'}]) {
      await add(JSON.stringify({...input, ...trigger}));
    }
    for (const [key, value] of Object.entries(defaults)) {
      await add(JSON.stringify({[key]: value, quickTab: true, ownedUnknown: {kept: false}}));
      await add(JSON.stringify({[key]: null, quickTab: true}));
    }
    for (const name of catalogs.funboxes) {
      await add(JSON.stringify({funbox: [name], quickTab: true}));
      await add(JSON.stringify({funbox: [name], quickTab: true, numbers: 'invalid'}));
    }
    for (const authenticated of [false, true]) for (const documentComplete of [false, true]) {
      await add(JSON.stringify({paceCaret: 'pb', quickTab: true}), {authenticated, documentComplete});
      await add(JSON.stringify({randomTheme: 'custom', numbers: 'invalid'}), {authenticated, documentComplete, customThemeCount: 2});
    }
    verify();
    console.log(JSON.stringify(transport({defaults, catalogs, orderedKeys: Object.keys(defaults), fixtures})));
  } else {
  const fixtures = [];
  async function add(input, flags = {}) {
    simulation.flags = {authenticated: false, documentComplete: true, customThemeCount: 0, development: false, ...flags};
    simulation.events = []; simulation.saves = []; simulation.stores = []; simulation.gates = [];
    const normalized = migration.migrateConfig(structuredClone(input));
    await context.applyConfig(structuredClone(input));
    assert.equal(simulation.gates.length, 1); assert.equal(simulation.stores.length, 1);
    fixtures.push({normalized, flags: simulation.flags, runtime: structuredClone(simulation.Config),
      requested: simulation.stores[0], rejectedKeys: simulation.saves,
      events: simulation.events, gate: simulation.gates[0]});
  }
  await add({});
  for (const mode of ['time', 'words', 'quote', 'custom', 'zen']) for (let bits = 0; bits < 4; bits++) {
    await add({mode, numbers: !!(bits & 1), punctuation: !!(bits & 2)});
  }
  for (const freedomMode of [false, true]) for (const confidenceMode of ['off', 'on', 'max'])
    for (const stopOnError of ['off', 'letter', 'word']) for (const deleteOnError of ['off', 'letter', 'letter_hard', 'word', 'word_hard']) {
      await add({freedomMode, confidenceMode, stopOnError, deleteOnError});
    }
  for (const authenticated of [false, true]) for (const documentComplete of [false, true])
    for (const paceCaret of ['off', 'pb', 'tagPb', 'custom', 'daily']) await add({paceCaret}, {authenticated, documentComplete});
  for (const authenticated of [false, true]) for (const customThemeCount of [0, 2])
    await add({randomTheme: 'custom'}, {authenticated, customThemeCount});
  for (const monkey of [false, true]) for (const liveSpeedStyle of ['off', 'mini', 'text'])
    for (const liveAccStyle of ['off', 'mini', 'text']) await add({monkey, liveSpeedStyle, liveAccStyle});
  for (let bits = 0; bits < 16; bits++) await add({accountChart: [0, 1, 2, 3].map(i => bits & (1 << i) ? 'on' : 'off')});
  for (const tapeMode of ['off', 'word', 'letter']) for (const showAllLines of [false, true]) await add({tapeMode, showAllLines});
  for (const development of [false, true]) await add({ads: 'sellout'}, {development});
  for (const key of ['customLayoutfluid', 'customPolyglot']) {
    const first = defaults[key][0], second = defaults[key][1];
    await add({[key]: [first, first]}); await add({[key]: [first, second, first]});
  }
  await add({customTheme: true, customThemeColors: Array(10).fill('#abcdef')});
  for (const suffix of ['\n', '\u0085', '\ufeff']) await add({customBackground: 'http://example.com/p.png' + suffix});
  for (const keymapSize of [1.0999999999999999, 1.4000000000000001, 1.5999999999999999]) await add({keymapSize});
  for (const funbox of catalogs.funboxes) for (const mode of ['time', 'words', 'quote', 'custom', 'zen'])
    for (const highlightMode of ['letter', 'word']) await add({funbox: [funbox], mode, highlightMode});
  for (const funbox of [['read_ahead', 'read_ahead_hard'], ['mirror', 'round_round_baby'], ['tts', 'simon_says']]) await add({funbox});
  verify();
  console.log(JSON.stringify(transport({defaults, catalogs, orderedKeys: Object.keys(defaults), fixtures})));
  }
  }
} else {
const fixtures = [];
function add(input) {
  fixtures.push({input: structuredClone(input), sanitized: sanitize(schema, input),
    merged: migration.migrateConfig(structuredClone(input))});
}
const values = [null, true, false, -Infinity, Infinity, NaN, -1, 0, .1, .5, 1, 1.1,
  1.1000000000000003, 3.5, 3.5000000000000004, 15, 50, 100, 1000, 1e20,
  '', 'off', 'word', 'english', 'not-a-known-value', [], ['bad'], {}, [true], ['off', 'bad']];
for (const key of Object.keys(defaults)) {
  add({[key]: defaults[key], ownedUnknown: {keep: true}});
  for (const value of values) add({[key]: value});
}
for (const [key, valid] of [['funbox', 'read_ahead'], ['quoteLength', 1], ['customPolyglot', 'english'],
  ['customLayoutfluid', 'qwerty'], ['favThemes', 'serika']]) {
  add({[key]: [valid, 'bad']}); add({[key]: [valid, valid, 'bad']});
  add({[key]: Array(16).fill(valid)});
}
for (const url of ['http://example.com/p.png', 'https://example.com/p.PNG?q=1', 'HTTP://example.com/p.png',
  'http://example.com:99999/p.png', 'http:///example.com/p.png', 'http://%zz/p.png',
  'https://example.com/p.png\n', 'https://example.com/p.png\"', 'ftp://example.com/p.png']) add({customBackground: url});
add({accountChart: ['on', 'bad', 'off', 'on']});
add({customThemeColors: defaults.customThemeColors.map((v, i) => i === 3 ? 'bad' : v)});
add({customBackgroundFilter: [1, NaN, 1, 1]});
add({customBackgroundFilter: [1, Infinity, 1, 1]});
// Public schema accessors enumerate every enum/literal alternative, not just defaults.
function alternatives(rule) {
  if (rule instanceof zod.ZodEnum) return rule.options;
  if (rule instanceof zod.ZodLiteral) return [rule.value];
  if (rule instanceof zod.ZodUnion) return rule.options.flatMap(alternatives);
  return [];
}
for (const key of Object.keys(defaults)) {
  const rule = configSchemas.ConfigSchema.shape[key];
  if (rule instanceof zod.ZodArray) {
    const count = Math.max(1, rule._def.minLength?.value ?? 0);
    for (const value of alternatives(rule.element)) add({[key]: Array(count).fill(value)});
  } else if (rule instanceof zod.ZodTuple) {
    rule.items.forEach((item, index) => {
      for (const value of alternatives(item)) {
        const values = structuredClone(defaults[key]); values[index] = value; add({[key]: values});
      }
    });
  } else for (const value of alternatives(rule)) add({[key]: value});
}
for (let tenth = 5; tenth <= 35; tenth++) {
  const value = tenth / 10;
  for (const delta of [0, Number.EPSILON, -Number.EPSILON]) add({keymapSize: value + delta});
}
for (const value of ['a'.repeat(50), 'a'.repeat(51), 'a\n', 'a\r\n', 'a\u0085', 'a\u2028', '字']) add({fontFamily: value});
for (const value of ['#fff', '#ABCDEF', '#fff\n', '#fff\r\n', '#fff\u0085', '#fff\u2028', '#ffff']) {
  const colors = structuredClone(defaults.customThemeColors); colors[0] = value; add({customThemeColors: colors});
}
verify();
console.log(JSON.stringify(transport({defaults, catalogs, fixtures})));
}
