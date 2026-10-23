// QA only: actual pinned handler bodies, active-list ordering and word dispatch.
// No word lists, translations or reference visual assets are loaded.
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
assert.equal(process.versions.unicode, '17.0', 'Prepare the Unicode 17 QA runtime');
const frontend = path.join(root, 'frontend/src/ts');
const state = {upper: false};
const math = Object.create(Math);
math.random = () => state.upper ? 0.25 : 0.75;
const context = vm.createContext({Config: {funbox: []}, Math: math});
const source = fs.readFileSync(path.join(frontend, 'test/funbox/funbox-functions.ts'), 'utf8');
const start = source.indexOf('const list: Partial<Record<FunboxName, FunboxFunctions>> = {');
assert.ok(start >= 0);
vm.runInContext(stripTypeScriptTypes(source.slice(start).replace(/^export /gm, ''), {mode: 'transform'}), context);

const modules = new Map();
const files = {
  metadata: 'packages/funbox/src/list.ts', validation: 'packages/funbox/src/validation.ts',
  arrays: 'packages/util/src/arrays.ts', numbers: 'packages/util/src/numbers.ts',
  active: 'frontend/src/ts/test/funbox/active.ts', list: 'frontend/src/ts/test/funbox/list.ts',
  strings: 'frontend/src/ts/utils/strings.ts', generate: 'frontend/src/ts/utils/generate.ts',
  frontendArrays: 'frontend/src/ts/utils/arrays.ts',
};
const adapters = {
  types: {FunboxMetadata: undefined, FunboxProperty: undefined, FunboxForcedConfig: undefined},
  configs: {ConfigValue: undefined, FunboxName: undefined}, language: {Language: undefined},
  store: {Config: context.Config},
  functions: {FunboxFunctions: undefined, getFunboxFunctions: context.getFunboxFunctions},
};
function getModule(id) {
  if (modules.has(id)) return modules.get(id);
  let module;
  if (files[id]) {
    module = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(path.join(root, files[id]), 'utf8'),
      {mode: 'transform'}), {context, identifier: id});
  } else {
    const values = adapters[id];
    assert.ok(values, `Unexpected pinned dependency: ${id}`);
    module = new vm.SyntheticModule(Object.keys(values), function() {
      for (const [key, value] of Object.entries(values)) this.setExport(key, value);
    }, {context, identifier: id});
  }
  modules.set(id, module);
  return module;
}
function resolve(id, from) {
  if (id === '@monkeytype/schemas/configs') return 'configs';
  if (id === '@monkeytype/schemas/languages') return 'language';
  if (id === '@monkeytype/util/arrays') return 'arrays';
  if (id === '@monkeytype/util/numbers') return 'numbers';
  if (id === '@monkeytype/funbox') return 'funbox';
  if (id === './types') return 'types';
  if (id === './list') return 'metadata';
  if (id === './active') return 'active';
  if (id === './funbox-functions') return 'functions';
  if (id === '../../config/store') return 'store';
  if (id === './strings') return 'strings';
  if (id === './arrays' && from === 'generate') return 'frontendArrays';
  throw new Error(`Unexpected pinned import ${from}: ${id}`);
}
async function load(id) {
  const module = getModule(id);
  if (module.status === 'unlinked') await module.link((id, from) => getModule(resolve(id, from.identifier)));
  if (module.status === 'linked') await module.evaluate();
  return module.namespace;
}
const metadata = await load('metadata');
adapters.funbox = {...adapters.types, getFunboxObject: metadata.getObject};
const validation = await load('validation');
context.Strings = await load('strings');
context.GetText = await load('generate');
context.getActiveFunboxesWithFunction = (await load('list')).getActiveFunboxesWithFunction;
const generator = fs.readFileSync(path.join(frontend, 'test/words-generator.ts'), 'utf8');
const first = generator.indexOf('function applyFunboxesToWord('), last = generator.indexOf('\n}\n', first);
assert.ok(first >= 0 && last > first);
vm.runInContext(stripTypeScriptTypes(generator.slice(first, last + 2), {mode: 'transform'}), context);

const names = ['ALL_CAPS', 'capitals', 'backwards', 'ddoouubblleedd', 'instant_messaging',
  'morse', 'rAnDoMcAsE', 'rot13', 'sPoNgEcAsE', 'underscore_spaces'];
const chains = [[], ...names.map(name => [name]), ['rot13', 'rot13'], Array(15).fill('rot13'),
  Array(3).fill('ddoouubblleedd'), ['backwards', 'ddoouubblleedd'], ['ddoouubblleedd', 'backwards'],
  ['rot13', 'backwards'], ['backwards', 'rot13'], ['underscore_spaces', 'rot13'],
  ['rot13', 'underscore_spaces'], ['no_quit', 'rot13', 'rot13']].filter(chain => validation.checkCompatibility(chain));
assert.equal(chains.length, 21);
const words = ['Amber!', '  alpha   beta ', 'ΟΣ ΟΣΑ', 'İ I ı i', 'Kſß ﬃ', '😀𐐀𐐨é',
  'a\r\nb\u2028c\u2029', 'a\ud800b', 'a\udc00b', '\udbff\udfff', 'A\0z', '', 'A.!?\n',
  '\ua7ceΣ', 'AΣ\ua7cf', 'AΣ\u0345', '\u0345Σ', 'aΣ\u0301a'].map(units);
for (let value = 0; value < 128; value++) words.push([value]);
for (let block = 0; block < 256; block++) words.push(Array.from({length: 256}, (_, i) => block * 256 + i));
for (let point = 0x10000; point <= 0x10FFFF; point++) {
  const text = String.fromCodePoint(point);
  if (text.toUpperCase() !== text || text.toLowerCase() !== text) words.push(units(text));
}
function units(text) { return Array.from({length: text.length}, (_, i) => text.charCodeAt(i)); }
const fixtures = [];
for (const chain of chains) for (let word = 0; word < words.length; word++) {
  const variants = [{index: 0, bound: 2, upper: false}];
  if (chain.includes('rAnDoMcAsE')) variants.push({index: 0, bound: 2, upper: true});
  if (chain.includes('underscore_spaces')) variants.push({index: 1, bound: 2, upper: false}, {index: 3, bound: 0, upper: false});
  for (const variant of variants) {
    context.Config.funbox = chain;
    state.upper = variant.upper;
    const output = context.applyFunboxesToWord(String.fromCharCode(...words[word]), variant.index, variant.bound);
    fixtures.push({chain, word, ...variant, output: units(output)});
  }
}
verify();
assert.equal(fixtures.length, words.length * 28);
console.log(JSON.stringify({names, chains: chains.length, words, fixtures}));
