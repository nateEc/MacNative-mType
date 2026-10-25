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
const coldMode = process.argv[3] === '--cold-storage';
const editMode = process.argv[3] === '--single-edit';
const failureOrderMode = process.argv[3] === '--import-failure-order';
const thresholdCommandMode = process.argv[3] === '--threshold-commands';
assert.ok(!process.argv[3] || runtimeMode || funboxMode || keyboardMode || importMode || defaultsMode || coldMode || editMode || failureOrderMode || thresholdCommandMode);
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
  console: {warn: noop, error: noop, log: noop, debug: noop}});
const modules = new Map();
const schemas = path.join(root, 'packages/schemas/src');
const frontend = path.join(root, 'frontend/src/ts');
const adapters = new Map([
  [path.join(frontend, 'states/notifications.ts'), {showNoticeNotification: (_message, options) => {
    if (thresholdCommandMode) simulation.notices.push(options?.important ?? false);
  }, showErrorNotification: noop}],
  [path.join(frontend, 'states/core.ts'), {isAuthenticated: () => !!simulation.flags.authenticated}],
  [path.join(frontend, 'states/test.ts'), {isTestActive: () => simulation.flags.testActive ?? true}],
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
    if (id === path.join(schemas, 'configs.ts')) source += '\nexport const Config = undefined; export const CustomThemeColors = undefined; export const ConfigValue = undefined; export const FunboxName = undefined; export const TypingSpeedUnit = undefined;';
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
  if (id === '@monkeytype/util/trycatch') return path.join(root, 'packages/util/src/trycatch.ts');
  if (id === '@monkeytype/util/zod') return path.join(root, 'packages/util/src/zod.ts');
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
  if (coldMode && typeof value === 'number' && Object.is(value, -0)) return {$probeNumber:'-0'};
  if ((importMode || coldMode) && typeof value === 'string' && !value.isWellFormed()) {
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
} else if (runtimeMode || keyboardMode || importMode || coldMode || editMode || failureOrderMode || thresholdCommandMode) {
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
  if (thresholdCommandMode) {
    function extract(file, from, until, wrap = text => text) {
      const source = fs.readFileSync(path.join(frontend, file), 'utf8');
      const start = source.indexOf(from), end = source.indexOf(until, start);
      assert.ok(start >= 0 && end > start);
      return stripTypeScriptTypes(wrap(source.slice(start, end).replace(/^export /gm, '')), {mode:'transform'});
    }
    const unitModule = await load(path.join(frontend, 'utils/typing-speed-units.ts'));
    Object.assign(context, {Config:simulation.Config, configEvent:bus,
      getTypingSpeedUnit:unitModule.get, capitalizeFirstLetter:value => value[0].toUpperCase()+value.slice(1),
      getActivePage:() => 'test', restart:() => { simulation.restarts++; }});
    vm.runInContext(extract('commandline/commandline-metadata.ts', '  minWpm: {', '  minAcc: {',
      text => `globalThis.speedInput=({${text}}).minWpm.input;`), context);
    vm.runInContext(extract('commandline/commandline-metadata.ts', '  minAcc: {', '  // minBurst:',
      text => `globalThis.accuracyInput=({${text}}).minAcc.input;`), context);
    vm.runInContext(extract('commandline/util.ts', 'function buildInputCommand<', 'export const __testing'), context);
    const burst = fs.readFileSync(path.join(frontend, 'commandline/lists/min-burst.ts'), 'utf8');
    vm.runInContext(stripTypeScriptTypes(burst.replace(/^import .*;\r?\n/gm, '')
      .replace('export default commands;', 'globalThis.burstCommands=commands[0].subgroup.list;'), {mode:'transform'}), context);
    vm.runInContext(extract('test/test-logic.ts', 'configEvent.subscribe(', 'timerEvent.subscribe('), context);
    let attempts = [];
    context.setConfig = (key, value, options) => {
      const accepted = setters.setConfig(key, value, options);
      attempts.push({key, value, accepted}); return accepted;
    };
    const speed = context.buildInputCommand({key:'minWpmCustomSpeed', isPartOfSubgroup:true,
      inputProps:context.speedInput, configMeta:metadata.minWpm, schema:configSchemas.ConfigSchema.shape.minWpmCustomSpeed});
    const accuracy = context.buildInputCommand({key:'minAccCustom', isPartOfSubgroup:true,
      inputProps:context.accuracyInput, configMeta:metadata.minAcc, schema:configSchemas.ConfigSchema.shape.minAccCustom});
    const commands = {speed, accuracy, fixed:context.burstCommands.find(c => c.id === 'setMinBurstFixed'),
      flex:context.burstCommands.find(c => c.id === 'setMinBurstFlex')};
    const rawInputs = ['', ' ', '\ufeff \n', '0', '-0', '+0', '-1', '1.7', '73.5tail', '1e3', '1e-3',
      '0x10', '0b10', '0o10', '-0x10', '0x1g', '0x', 'Infinity', '-Infinity', 'inf', 'NaN', '.5',
      '1.', '+.5', '1e309', '1e-9999', '9007199254740993', '0xffffffffffffffff',
      '0b'+'1'.repeat(65), '0o'+'7'.repeat(25), '1\u0085', '\u180e12', '\u200b12',
      '\ufeff12\u00a0', '1_000', '12\rfoo', '+', '-', '.', '0XfZ'];
    const fields = ['minWpm','minWpmCustomSpeed','minAcc','minAccCustom','minBurst','minBurstCustomSpeed'];
    const fixtures = [];
    for (const unit of ['wpm','cpm','wps','cps','wph']) for (const active of [false,true])
      for (const noQuit of [false,true]) for (const [kind, command] of Object.entries(commands)) for (const raw of rawInputs) {
        Object.assign(simulation.Config, structuredClone(defaults), {typingSpeedUnit:unit,
          minWpm:'off', minWpmCustomSpeed:73.5, minAcc:'off', minAccCustom:91.5,
          minBurst:'off', minBurstCustomSpeed:83.5, funbox:noQuit ? ['no_quit'] : []});
        simulation.flags = {testActive:active, authenticated:false, documentComplete:true};
        simulation.events = []; simulation.saves = []; simulation.notices = []; simulation.restarts = 0; attempts = [];
        const prefill = command.defaultValue?.() ?? '';
        const converted = command.inputValueConvert ? command.inputValueConvert(raw) : raw;
        const canSubmit = command.validation?.schema ? command.validation.schema.safeParse(converted).success : true;
        if (canSubmit) command.exec({input:converted});
        assert.equal(simulation.restarts, 0);
        fixtures.push(transport({kind, raw, unit, active, noQuit, prefill, converted, canSubmit, attempts,
          runtime:Object.fromEntries(fields.map(key => [key, simulation.Config[key]])),
          events:simulation.events, saves:simulation.saves, notices:simulation.notices}));
      }
    verify(); console.log(JSON.stringify({fixtures}));
  } else if (editMode) {
    const fixtures = [];
    function add(key, value, patch = {}, flags = {}, nosave = false) {
      Object.assign(simulation.Config, structuredClone(defaults), structuredClone(patch));
      simulation.flags = {authenticated:false, documentComplete:true, customThemeCount:0,
        development:false, testActive:false, ...flags};
      simulation.events = []; simulation.saves = [];
      const current = structuredClone(simulation.Config);
      const accepted = setters.setConfig(key, structuredClone(value), {nosave});
      fixtures.push({key, value, current, flags:simulation.flags, nosave, accepted,
        runtime:structuredClone(simulation.Config), events:simulation.events, saves:simulation.saves});
    }
    // Every field, including same-value writes and active No Quit metadata.
    for (const [key, value] of Object.entries(defaults)) {
      add(key, value);
      add(key, value, {funbox:['no_quit']}, {testActive:true});
      add(key, value, {funbox:['no_quit']}, {testActive:false}, true);
    }
    const choices = {mode:['time','words','quote','custom','zen'], words:[0,1,120], time:[0,1,120],
      numbers:[false,true], punctuation:[false,true], highlightMode:['off','letter','word'],
      funbox:[[],['no_quit'],['memory'],['binary'],['mirror']],
      confidenceMode:['off','on','max'], stopOnError:['off','word'], deleteOnError:['off','letter'],
      freedomMode:[false,true], showAllLines:[false,true], tapeMode:['off','word'],
      keymapSize:[-1,0.55,9], customBackground:['  owned  '], paceCaret:['pb','tagPb','custom'],
      randomTheme:['custom'], theme:['dracula'], customThemeColors:[Array(10).fill('#123456')],
      accountChart:[['off','off','on','off']]};
    Object.assign(choices, {
      minWpm:['off','custom'], minWpmCustomSpeed:[-1,0,73.5,100],
      minAcc:['off','custom'], minAccCustom:[0,91.5,100,101],
      minBurst:['off','fixed','flex'], minBurstCustomSpeed:[-1,0,83.5,100],
    });
    for (const funbox of [[],['no_quit'],['memory'],['binary'],['arrows'],['tts'],['rot13']])
      for (const testActive of [false,true]) for (const nosave of [false,true])
        for (const [key, values] of Object.entries(choices)) for (const value of values)
          add(key, value, {funbox, customTheme:true}, {testActive}, nosave);
    for (const authenticated of [false,true]) for (const documentComplete of [false,true])
      for (const customThemeCount of [0,2]) {
        add('paceCaret','pb',{}, {authenticated,documentComplete,customThemeCount});
        add('randomTheme','custom',{}, {authenticated,documentComplete,customThemeCount});
      }
    verify();
    console.log(JSON.stringify({defaults,catalogs,fixtures,
      restartKeys:Object.keys(metadata).filter(key => metadata[key].changeRequiresRestart)}));
  } else if (keyboardMode) {
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
  if (failureOrderMode) {
    // Real parser/schema/migration, setter, lifecycle, event bus and persistence
    // functions. Failures are injected at explicit metadata/storage/listener
    // boundaries; no browser, real initialization, disk, account or network.
    const parser = await load(path.join(root, 'packages/util/src/json.ts'));
    const extract = (text, begin, end) => {
      const a = text.indexOf(begin), b = text.indexOf(end, a);
      assert.ok(a >= 0 && b > a);
      return text.slice(a, b).replace(/^export /gm, '');
    };
    const persistence = fs.readFileSync(path.join(frontend, 'config/persistence.ts'), 'utf8');
    vm.runInContext(stripTypeScriptTypes('let configToSend = {};\n' + extract(persistence,
      'export function saveToLocalStorage(', '\nexport function saveFullConfigToLocalStorage'), {mode:'transform'}), context);
    vm.runInContext(stripTypeScriptTypes(extract(persistence,
      'export function saveFullConfigToLocalStorage(', '\nconst saveToDatabase'), {mode:'transform'}), context);
    vm.runInContext(stripTypeScriptTypes(extract(lifecycle,
      'export async function applyConfigFromJson(', '\nexport async function loadFromLocalStorage('), {mode:'transform'}), context);
    vm.runInContext(stripTypeScriptTypes(extract(lifecycle,
      'export async function loadFromLocalStorage(', '\nconst lastConfigsToApply'), {mode:'transform'}), context);
    Object.assign(context, {ConfigSchemas:configSchemas, parseJsonWithSchema:parser.parseWithSchema});
    const fixtures = [];
    const testLogic = fs.readFileSync(path.join(frontend,'test/test-logic.ts'),'utf8');
    const configSubscriber = extract(testLogic,'configEvent.subscribe(','timerEvent.subscribe(').trim().replace(/;$/,'');
    const cases = ['valid','parse','override-first','override-middle','override-last','refused',
      'correction-storage','full-storage','full-storage-after-correction','sync-listener','async-listener','source-init-pending','source-init-failure',
      'cold-init-pending','cold-init-failure'];
    const orderedKeys = [...Object.keys(defaults).filter(key => !vm.runInContext('lastConfigsToApply.has',context).call(
      vm.runInContext('lastConfigsToApply',context),key)), ...vm.runInContext('Array.from(lastConfigsToApply)',context)];
    // Each scenario also checks that a prior runtime/disk value is distinct
    // from source defaults; a failed application must not be mistaken for a
    // rollback merely because only a default-valued profile was observed.
    for (const scenario of cases) {
      const cold = scenario.startsWith('cold-init-');
      const usesTestSubscriber = cold || scenario.startsWith('source-init-');
      const old = {...structuredClone(defaults), fontSize:1.75, words:77};
      Object.assign(simulation.Config,structuredClone(old));
      simulation.flags = {authenticated:false,documentComplete:true,customThemeCount:0,development:false,testActive:false};
      simulation.events = []; simulation.saves = []; simulation.stores = []; simulation.gates = [];
      const trace = [], writes = [];
      let disk = structuredClone(old), success = 0, errors = 0, remote = 0, asyncFailure = false;
      let finishAsync, observedAsync;
      const metadataKey = scenario === 'override-first' ? orderedKeys[0]
        : scenario === 'override-middle' ? orderedKeys[Math.floor(orderedKeys.length/2)]
        : scenario === 'override-last' ? orderedKeys.at(-1) : null;
      const originalOverride = metadataKey ? metadata[metadataKey].overrideValue : null;
      if (metadataKey) metadata[metadataKey].overrideValue = () => { trace.push('override-error'); throw new Error('owned metadata failure'); };
      const unsubscribe = bus.subscribe(event => {
        trace.push('event:'+event.key);
        if (event.key !== 'fullConfigChangeFinished') return;
        if (scenario === 'sync-listener') throw new Error('owned synchronous listener failure');
        if (scenario === 'async-listener') {
          const pending = (async () => { await new Promise(resolve => { finishAsync = resolve; }); throw new Error('owned asynchronous listener failure'); })();
          observedAsync = pending.catch(() => { asyncFailure = true; trace.push('async-error'); });
          return pending;
        }
      });
      Object.assign(context, {
        configLS:{get:() => structuredClone(disk),set:value => {
          trace.push('storage-attempt');
          if (scenario === 'full-storage' || scenario === 'correction-storage'
            || (scenario === 'full-storage-after-correction' && writes.length === 1)) throw new Error('owned storage failure');
          disk = structuredClone(value); writes.push(structuredClone(value)); trace.push('storage-written');
        }}, saveToDatabase:() => { remote++; },
        saveConfig:() => { remote++; return Promise.resolve(); }, setAccountButtonSpinner:() => {},
        showSuccessNotification:() => { success++; trace.push('success'); },
        showErrorNotification:() => { errors++; trace.push('import-error'); },
        loadDone:() => { success++; trace.push('loaded'); },
        setFullConfigStore:value => { simulation.stores.push(structuredClone(value)); trace.push('store'); },
      });
      if (usesTestSubscriber) {
        // Actual test-page subscriber; restart/initialization and its eventual
        // I/O completion are owned boundaries, not the real test engine.
        Object.assign(context,{getActivePage:() => 'test',
          LazyModeState:{getArabicPref:() => false},
          restart:() => {
            trace.push('restart-request');
            const pending = new Promise((resolve,reject) => {
              finishAsync = () => scenario.endsWith('-failure') ? reject(new Error('owned init failure')) : resolve();
            });
            observedAsync = pending.then(() => trace.push('init-complete'),() => { asyncFailure = true; trace.push('async-error'); });
            return pending;
          }});
        vm.runInContext(stripTypeScriptTypes(`globalThis.removeConfigSubscriber=(${configSubscriber});`,{mode:'transform'}),context);
      }
      const partial = {fontSize:2,mode:'words',words:4,numbers:true};
      if (cold) disk = {...structuredClone(defaults),...partial};
      if (['refused','correction-storage','full-storage-after-correction'].includes(scenario)) partial.customPolyglot = ['english','english'];
      try {
        if (cold) await context.loadFromLocalStorage();
        else await context.applyConfigFromJson(scenario === 'parse' ? '{' : JSON.stringify(partial));
      }
      finally { unsubscribe(); if (usesTestSubscriber) context.removeConfigSubscriber(); if (metadataKey) {
        if (originalOverride === undefined) delete metadata[metadataKey].overrideValue;
        else metadata[metadataKey].overrideValue = originalOverride;
      }}
      const beforeAsync = {success,errors,writes:writes.length,asyncFailure};
      if (finishAsync) { finishAsync(); await observedAsync; }
      const expectedFailure = ['parse','override-first','override-middle','override-last','correction-storage','full-storage','full-storage-after-correction'].includes(scenario);
      assert.equal(errors,Number(expectedFailure),scenario); assert.equal(success,Number(!expectedFailure),scenario);
      assert.equal(writes.length,expectedFailure && scenario !== 'full-storage-after-correction' ? 0 : scenario === 'refused' ? 2 : 1,scenario);
      if (expectedFailure && scenario !== 'full-storage-after-correction') assert.deepEqual(disk,old,scenario);
      if (scenario.startsWith('override-')) {
        assert.equal(simulation.stores.length,0); assert.notDeepEqual(simulation.Config,old);
        assert.ok(!simulation.events.some(event => event.key === 'fullConfigChangeFinished'));
      }
      if (scenario === 'full-storage') assert.equal(simulation.stores.length,1);
      if (scenario === 'full-storage-after-correction') {
        assert.equal(simulation.stores.length,1); assert.equal(disk.words,4); assert.notDeepEqual(disk,old);
        assert.ok(trace.indexOf('storage-written') < trace.indexOf('import-error'));
      }
      if (scenario === 'correction-storage') assert.equal(simulation.stores.length,0);
      if (scenario === 'sync-listener') assert.ok(trace.includes('success'));
      if (scenario === 'async-listener') {
        assert.deepEqual(beforeAsync,{success:1,errors:0,writes:1,asyncFailure:false});
        assert.equal(asyncFailure,true); assert.ok(trace.indexOf('success') < trace.indexOf('async-error'));
      }
      if (usesTestSubscriber) {
        assert.deepEqual(beforeAsync,{success:1,errors:0,writes:1,asyncFailure:false});
        assert.equal(trace.filter(value => value === 'restart-request').length,1);
        const complete = cold ? 'loaded' : 'success';
        assert.ok(trace.indexOf('restart-request') < trace.indexOf(complete));
        assert.equal(asyncFailure,scenario.endsWith('-failure'));
        assert.ok(trace.indexOf(complete) < trace.indexOf(asyncFailure ? 'async-error' : 'init-complete'));
        if (cold) { assert.equal(remote,0); assert.ok(!trace.includes('success')); }
      }
      fixtures.push({scenario,completionKind:cold ? 'load' : 'import',metadataKey,success,errors,remote,beforeAsync,asyncFailure,
        writes:writes.length,stores:simulation.stores.length,trace,
        old,runtime:structuredClone(simulation.Config),disk});
    }
    verify();
    console.log(JSON.stringify({fixtures}));
  } else if (coldMode) {
    const Storage = (await load(path.join(frontend, 'utils/local-storage-with-schema.ts'))).LocalStorageWithSchema;
    // Execute actual source storage/read/apply code; browser I/O and remote
    // publication are controlled adapters, never a real browser or account.
    const extract = (text, begin, end) => {
      const a = text.indexOf(begin), b = text.indexOf(end, a);
      assert.ok(a >= 0 && b > a, `Missing pinned method ${begin}`);
      return text.slice(a, b).replace(/^export /gm, '');
    };
    vm.runInContext(stripTypeScriptTypes(extract(fs.readFileSync(path.join(frontend, 'utils/misc.ts'), 'utf8'),
      'export function isObject(', '\nexport function prefersReducedMotion'), {mode:'transform'}), context);
    const persistence = fs.readFileSync(path.join(frontend, 'config/persistence.ts'), 'utf8');
    vm.runInContext(stripTypeScriptTypes('let configToSend = {};\n' + extract(persistence,
      'export function saveToLocalStorage(', '\nexport function saveFullConfigToLocalStorage'), {mode:'transform'}), context);
    const saveKey = context.saveToLocalStorage;
    context.saveToLocalStorage = (...args) => {simulation.saves.push(args[0]); return saveKey(...args);};
    context.saveToDatabase = noop; // Keep pending correction state; no timer/network.
    vm.runInContext(stripTypeScriptTypes(extract(persistence, 'export function saveFullConfigToLocalStorage(', '\nconst saveToDatabase'), {mode:'transform'}), context);
    vm.runInContext(stripTypeScriptTypes(extract(lifecycle, 'export async function loadFromLocalStorage(', '\nconst lastConfigsToApply'), {mode:'transform'}), context);
    const fixtures = [];
    async function add(json, flags = {}) {
      Object.assign(simulation.Config, structuredClone(defaults));
      simulation.flags = {authenticated:false, documentComplete:true, customThemeCount:0, development:false, ...flags};
      simulation.events = []; simulation.saves = []; simulation.stores = []; simulation.gates = [];
      vm.runInContext('configToSend = {};', context);
      let disk = json, loaded, migrated = false, finished = 0;
      const writes = [];
      context.window = {localStorage:{getItem:() => disk, setItem:(key, value) => {assert.equal(key, 'config'); disk = value; writes.push(value);}}};
      const storage = new Storage({key:'config', schema:configSchemas.ConfigSchema, fallback:structuredClone(defaults),
        migrate:value => {migrated = true; return context.isObject(value) ? migration.migrateConfig(value) : structuredClone(defaults);}});
      context.configLS = {get:() => {const value = storage.get(); loaded = structuredClone(value); return value;}, set:value => storage.set(value)};
      context.loadDone = () => finished++;
      context.resetConfig = () => {throw new Error('Unexpected undefined ConfigSchema fallback');};
      context.saveConfig = () => {throw new Error('Remote write attempted');};
      context.setAccountButtonSpinner = () => {throw new Error('Remote spinner attempted');};
      await context.loadFromLocalStorage();
      assert.equal(finished, 1); assert.equal(simulation.stores.length, 1);
      const fixture = {json, flags:simulation.flags, loaded, migrated, writes, disk,
        requested:simulation.stores[0], runtime:structuredClone(simulation.Config), rejectedKeys:simulation.saves, events:simulation.events,
        pendingSync:vm.runInContext('structuredClone(configToSend)', context)};
      fixtures.push(fixture);
      return fixture;
    }
    for (const json of [null, '', ' ', '{', 'null', 'true', '17', '"owned"', '[]', '[{}]', '{}',
      '{"quickTab":true}', '{"quickTab":true,"numbers":true}', '{"soundVolume":"0.5suffix"}',
      '{"customBackground":"https://example.com/\\ud800.png"}', '{"customBackgroundFilter":[-0,1e400,-1e400,1]}']) await add(json);
    for (const [key, value] of Object.entries(defaults)) {
      await add(JSON.stringify({[key]:value}));
      await add(JSON.stringify({...defaults, [key]:null}));
    }
    for (const authenticated of [false, true]) for (const documentComplete of [false, true]) {
      for (const customThemeCount of [0, 2]) await add(JSON.stringify({...defaults, paceCaret:'tagPb',
        randomTheme:'custom', quoteLength:[0,0,1], funbox:['rot13','rot13']}), {authenticated, documentComplete, customThemeCount});
    }
    for (const patch of [{future:123}, {quickTab:true}, {theme:'dracula',customTheme:true,autoSwitchTheme:true},
      {accountChart:['off','off','on','off']}, {mode:'zen',numbers:true,punctuation:true}]) await add(JSON.stringify({...defaults, ...patch}));
    for (const key of ['fontSize','tapeMargin','maxLineWidth']) {
      for (const value of [{toString:0}, [{toString:0}], [[{toString:null}]]]) await add(JSON.stringify({[key]:value}));
    }
    for (const json of ['{"customBackgroundFilter":[-0,1e400,-1e400,1]}', '{']) {
      const first = await add(json); await add(first.disk);
    }
    verify();
    console.log(JSON.stringify(transport({defaults,catalogs,orderedKeys:Object.keys(defaults),schemaOrderedKeys:Object.keys(configSchemas.ConfigSchema.shape),fixtures})));
  } else if (importMode) {
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
