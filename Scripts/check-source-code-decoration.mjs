// Execute complete pinned behavior modules in memory; never write reference
// code or assets into the native project. The unit draws and inputs are owned.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
assert.ok(process.argv[2], 'Reference checkout required');
const root = path.resolve(process.argv[2]);
assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
  '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
let units = [], ranks = [], repeated = false, activeNames = [], functions;
const draw = () => { assert.ok(units.length, 'Unexpected unit draw'); return units.shift(); };
const math = Object.create(Math); math.random = draw;
const context = vm.createContext({Math: math, console: {debug() {}}});
const config = {mode: 'words', words: 1, language: 'code_swift', showAllLines: false,
  lazyMode: false, punctuation: true, numbers: true, britishEnglish: false};
const unused = () => { throw Error('Unexpected runtime adapter call'); };
const active = () => activeNames.map(name => ({name, functions: functions[name], properties:
  name === 'backwards' ? ['wordOrder:reverse'] : name === 'nospace' ? ['nospace'] : []}));
const bindings = {
  'config/store': {Config: config},
  'test/custom-text': {getPipeDelimiter: () => false},
  'test/practise-words': {before: {mode: null}},
  'controllers/quotes-controller': {default: {}},
  'states/test': {isRepeated: () => repeated, getCurrentQuote: () => null,
    setCurrentQuote: () => {}, getSelectedQuoteId: () => null},
  'test/funbox/list': {getActiveFunboxes: active,
    getActiveFunboxesWithFunction: name => active().filter(value => typeof value.functions[name] === 'function'),
    findSingleActiveFunboxWithFunction: name => active().find(value => typeof value.functions[name] === 'function'),
    isFunboxActiveWithFunction: name => active().some(value => typeof value.functions[name] === 'function'),
    isFunboxActiveWithProperty: name => active().some(value => value.properties.includes(name))},
  // Candidate ranks do not consume decoration units. Only source operator
  // arrays take a floor-scaled unit; the complete source getNumbers runs below.
  'utils/arrays': {randomElementFromArray: values => values.includes('node') || values.includes('bay')
    ? values[ranks.shift() ?? 0] : values[Math.floor(draw() * values.length)],
    shuffle: values => values, nthElementFromArray: (values, index) => values.at(index)},
  'utils/word-gen-error': {WordGenError: class extends Error {}},
};
const actual = new Set(['test/words-generator', 'test/wordset', 'test/funbox/funbox-functions',
  'test/weak-spot', 'utils/generate', 'utils/strings', '@monkeytype/util/numbers']);
const modules = new Map(), requested = new Map();
const resolve = (id, from) => id.startsWith('.')
  ? path.posix.normalize(path.posix.join(path.posix.dirname(from), id)) : id;
for (const id of actual) {
  const filename = id === '@monkeytype/util/numbers' ? 'packages/util/src/numbers.ts'
    : `frontend/src/ts/${id}.ts`;
  const code = stripTypeScriptTypes(fs.readFileSync(path.join(root, filename), 'utf8'), {mode: 'transform'});
  for (const match of code.matchAll(/import\s+([\s\S]*?)\s+from\s+["']([^"']+)["'];/g)) {
    const target = resolve(match[2], id), names = requested.get(target) ?? new Set();
    const clause = match[1];
    if (!clause.startsWith('*')) {
      if (!clause.startsWith('{')) names.add('default');
      for (const field of (clause.match(/\{([\s\S]*?)\}/)?.[1] ?? '').split(',')) {
        const name = field.trim().split(/\s+as\s+/)[0]; if (name) names.add(name);
      }
    }
    requested.set(target, names);
  }
  const types = id === 'test/wordset' ? '\nexport const FunboxWordsFrequency=undefined;' : '';
  modules.set(id, new vm.SourceTextModule(code + types, {identifier: id, context}));
}
function moduleFor(id) {
  if (modules.has(id)) return modules.get(id);
  const values = {...Object.fromEntries([...(requested.get(id) ?? [])].map(name => [name, unused])),
    ...bindings[id]};
  const module = new vm.SyntheticModule(Object.keys(values), function() {
    for (const [key, value] of Object.entries(values)) this.setExport(key, value);
  }, {identifier: id, context});
  modules.set(id, module); return module;
}
const main = moduleFor('test/words-generator');
await main.link((id, from) => moduleFor(resolve(id, from.identifier))); await main.evaluate();
functions = modules.get('test/funbox/funbox-functions').namespace.getFunboxFunctions();
// Actual punctuation consumes two draws even at a forced finite endpoint.
// Actual numeric replacement follows it and overwrites the entire decoration.
units = [0.5, 0.95, 0.05, 0.99, 0, 0.5, 0.9, 0.2]; ranks = [0];
const opening = await main.namespace.generateWords({name: 'code_swift', words: ['node']});
assert.deepEqual(Array.from(opening.words), ['1592 ']); assert.equal(units.length, 0);
repeated = true; units = [0.777]; ranks = [0];
const replay = await main.namespace.generateWords({name: 'code_swift', words: ['bay']});
assert.deepEqual(Array.from(replay.words), ['1592 ']); assert.deepEqual(units, [0.777]);
assert.deepEqual(ranks, [0]); repeated = false; config.numbers = false;
let count = 2;
async function punctuation(language, previous, index, bound, draws, expected, word = 'node') {
  config.language = language; units = [...draws];
  assert.equal(await main.namespace.punctuateWord(previous, word, index, bound), expected);
  assert.equal(units.length, 0); count++;
}
for (const [choice, mark] of [[0.8, '.'], [0.80001, '?'], [0.9, '!']]) {
  await punctuation('code_swift', undefined, 0, 1, [0.5, choice], `node${mark}`);
}
await punctuation('code_swift', 'bay!', 1, 10, Array(10).fill(0.5), 'node');
await punctuation('code_swift', 'bay.', 1, 10, Array(8).fill(0), 'node,');
await punctuation('code_swift', undefined, 0, 10, [0.5, 0], '"node"');
await punctuation('code_swift', undefined, 0, 10, [0.5, 0.5, 0], "'node'");
for (const [choice, pair] of [[0, '()'], [0.25, '{}'], [0.5, '[]'], [0.75, '<>']]) {
  await punctuation('code_swift', undefined, 0, 10, [0.5, 0.5, 0.5, 0, choice], pair[0] + 'node' + pair[1]);
}
await punctuation('code_javascript_react', undefined, 0, 10, [0.5, 0.5, 0.5, 0, 0.99], '`node`');
await punctuation('code_swift', undefined, 0, 10, [0.5, 0.5, 0.5, 0.5, 0], 'node:');
await punctuation('code_swift', undefined, 0, 10, [0.5, 0.5, 0.5, 0.5, 0.5, 0], '-');
await punctuation('code_swift', undefined, 0, 10, [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0], 'node;');
await punctuation('code_swift', undefined, 0, 10, [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0], 'node,');
for (const [language, choice, expected] of [['code_swift', 0.99, '/'], ['code_css', 0.99, '/'],
  ['code_c', 0.99, '|='], ['code_clojure', 0.99, '|='], ['code_arduino', 0.99, '|='],
  ['code_javascript_1k', 0.99, '`']]) {
  await punctuation(language, undefined, 0, 10, [...Array(8).fill(0.5), 0, choice], expected);
}
await punctuation('code_swift', undefined, 0, 10, [...Array(9).fill(0.5), 0.49], 'are', 'are');
await punctuation('dockerfile', undefined, 0, 1, [], 'Node');
await punctuation('code_swift', undefined, 0, 1, [0.5, 0], 'node.\t\n', 'no\tde\n');
for (const [position, threshold] of [[0, 0.1], [1, 0.01], [2, 0.011], [3, 0.012],
  [4, 0.013], [5, 0.014], [6, 0.015], [7, 0.2], [8, 0.25]]) {
  const draws = Array(10).fill(0.5); draws[position] = threshold;
  await punctuation('code_swift', undefined, 0, 10, draws, 'node');
}
await punctuation('code_swift', undefined, 8, 10, [0.05, ...Array(9).fill(0.5)], 'node');
await punctuation('code_swift', undefined, 100, 100, Array(10).fill(0.5), 'node');
await punctuation('code_swift', 'bay:', 1, 10, [...Array(4).fill(0.5), 0, 0.5, 0], 'node;');
await punctuation('code_swift', '-', 1, 10, [...Array(5).fill(0.5), 0, 0.5, 0], 'node,');
config.language = 'code_swift'; config.punctuation = false; config.numbers = true;
units = [0.1]; ranks = [0];
const boundary = await main.namespace.generateWords({name: 'code_swift', words: ['node']});
assert.deepEqual(Array.from(boundary.words), ['node ']); assert.equal(units.length, 0); count++;
for (const [draws, expected] of [[[0, 0], '1'], [[0.25, 0.999, 0], '90'],
  [[0.5, 0, 0, 0.999], '109'], [[0.999, 0.999, 0.999, 0.999, 0.999], '9999'],
  [[0.24999999999999997, 0, 0], '10'],
  [[0.9999999999999999, 0.9999999999999999, 0, 0, 0, 0], '90000']]) {
  units = [...draws];
  assert.equal(modules.get('utils/generate').namespace.getNumbers(4), expected);
  assert.equal(units.length, 0); count++;
}
config.punctuation = true; activeNames = ['backwards', 'nospace'];
units = [0.5, 0.95, 0.05, 0.99, 0.01, 0.2, 0.3, 0.4]; ranks = [0];
const altered = await main.namespace.generateWords({name: 'code_swift', words: ['node']});
assert.deepEqual(Array.from(altered.words), ['4321']); assert.equal(units.length, 0); count++;
console.log(`${count} code-decoration fixtures passed (7 complete actual modules, including getNumbers; owned words/unit/rank/config/array/runtime adapters, no source RNG distribution, vocabulary or browser/device parity claim).`);
