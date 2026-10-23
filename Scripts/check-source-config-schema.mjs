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
assert.ok(process.argv[2] && zodRoot, 'Pinned reference and TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT required');
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
assert.equal(JSON.parse(fs.readFileSync(path.join(zodRoot, 'package.json'))).version, '3.23.8');
const zod = createRequire(import.meta.url)(path.join(zodRoot, 'lib/index.js'));
const context = vm.createContext({structuredClone, URL, console});
const modules = new Map();
const schemas = path.join(root, 'packages/schemas/src');
const frontend = path.join(root, 'frontend/src/ts');
function getModule(id) {
  if (modules.has(id)) return modules.get(id);
  let module;
  if (id === 'zod' || id === 'store-adapter') {
    const values = id === 'zod' ? {...zod, ZodErrorMap: undefined} : {Config: {}};
    module = new vm.SyntheticModule(Object.keys(values), function() {
      for (const [key, value] of Object.entries(values)) this.setExport(key, value);
    }, {context});
  } else {
    let source = fs.readFileSync(id, 'utf8');
    if (id === path.join(schemas, 'configs.ts')) source += '\nexport const Config = undefined; export const CustomThemeColors = undefined;';
    module = new vm.SourceTextModule(stripTypeScriptTypes(source, {mode: 'transform'}), {context, identifier: id});
  }
  modules.set(id, module);
  return module;
}
function resolve(id, importer) {
  if (id === 'zod') return id;
  if (id === './store' && importer === path.join(frontend, 'config/utils.ts')) return 'store-adapter';
  if (id === '@monkeytype/schemas/configs') return path.join(schemas, 'configs.ts');
  if (id === '@monkeytype/util/objects') return path.join(root, 'packages/util/src/objects.ts');
  assert.ok(id.startsWith('.'), 'Unexpected import: ' + id);
  return path.resolve(path.dirname(importer), id + '.ts');
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
  if (typeof value === 'number' && !Number.isFinite(value)) return {$probeNumber: String(value)};
  if (Array.isArray(value)) return value.map(transport);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, transport(v)]));
  return value;
}
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
