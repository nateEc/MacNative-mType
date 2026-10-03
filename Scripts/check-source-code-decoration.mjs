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
let units = [], ranks = [], repeated = false, activeNames = [], functions, spacingMs = null;
const candidatePools = new WeakSet();
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
  'test/events/live-cache': {getLiveCachedMsSinceLastInputEvent: () => spacingMs},
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
  'utils/arrays': {randomElementFromArray: values => candidatePools.has(values)
      || values.includes('node') || values.includes('bay')
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

// Sections use owned candidates, not any upstream language content. Register
// the actual pool identity so a phrase cannot be mistaken for an operator array.
let sectionCount = 0;
async function section(words, wordCount, draws, expected, indexes, names = [],
  language = 'code_swift', originalPunctuation = false) {
  config.mode = 'words'; config.words = wordCount; config.language = language;
  config.punctuation = false; config.numbers = false; repeated = false;
  activeNames = names; units = []; ranks = [...draws]; candidatePools.add(words);
  const result = await main.namespace.generateWords({name: config.language, words, originalPunctuation});
  assert.deepEqual(Array.from(result.words), expected);
  assert.deepEqual(Array.from(result.sectionIndexes), indexes);
  assert.equal(ranks.length, 0); assert.equal(units.length, 0); sectionCount++;
  return result;
}
await section(['node bay elm', 'oak'], 4, [0, 1, 1, 1],
  ['node ', 'bay ', 'elm ', 'oak '], [1, 1, 1, 2]);
await section(['node bay elm', 'oak'], 1, [0], ['node '], [1]);
ranks = [1];
const continuation = await main.namespace.getNextWord(1, 100, 'node', '');
assert.equal(continuation.word, 'bay '); assert.equal(continuation.sectionIndex, 1);
assert.equal(ranks.length, 0); sectionCount++;
await section(['node', 'node bay', 'oak'], 2, [0, 1, 2], ['node ', 'oak '], [1, 2]);
await section(['node item2', 'oak bay'], 2, [0, 1, 0], ['oak ', 'bay '], [1, 1]);
await section(['node   bay  ', 'oak'], 2, [0, 1], ['node ', 'bay '], [1, 1]);
// Leading spaces compare as an empty first word before normalization. The
// initial previous word is also empty, so this deliberately hits the retry cap.
await section(['  node   bay  ', 'oak'], 2, [...Array(101).fill(0), 1],
  ['node ', 'bay '], [1, 1]);
await section(['node\tbay elm', 'oak'], 2, [0, 1], ['node\tbay ', 'elm '], [1, 1]);
await section(['node bay', 'oak elm'], 2, [0, 1], ['kao ', 'mle '], [1, 1], ['backwards']);
await section(['node bay elm', 'oak'], 2, [0, 1], ['node', 'bay'], [1, 1], ['nospace']);
repeated = true; units = [0.777]; ranks = [1];
const replayPool = ['node bay elm', 'oak']; candidatePools.add(replayPool);
const restored = await main.namespace.generateWords({name: 'code_swift', words: replayPool});
assert.deepEqual(Array.from(restored.words), ['node', 'bay']); assert.deepEqual(ranks, [1]);
assert.deepEqual(units, [0.777]); config.mode = 'time'; units = [];
// generateWords clears currentSection even on repeat. Once its cache ends,
// the source draws a NEW section, not the formerly pending "elm".
const future = await main.namespace.getNextWord(2, 100, 'bay', 'node');
assert.equal(future.word, 'oak'); assert.deepEqual(ranks, []); sectionCount++;
const weakspot = modules.get('test/weak-spot').namespace;
spacingMs = 1000; weakspot.updateScore('a', true);
spacingMs = 800; weakspot.updateScore('b', true);
await section(['aaax bb', 'bb'], 2, [1, 0, ...Array(19).fill(1), 1],
  ['aaax ', 'bb '], [1, 1], ['weakspot']);
const hundredWords = Array.from({length: 100}, (_, index) => ['node ', 'bay ', 'elm '][index % 3]);
await section(['node bay elm', 'oak'], 101, Array(100).fill(0), hundredWords,
  Array.from({length: 100}, (_, index) => Math.floor(index / 3) + 1));
ranks = [1];
const hundredTail = await main.namespace.getNextWord(100, 100, 'node', 'elm');
assert.equal(hundredTail.word, 'bay '); assert.equal(hundredTail.sectionIndex, 34);
assert.equal(ranks.length, 0); sectionCount++;
config.words = 2; config.numbers = true; activeNames = ['nospace'];
const numericPool = ['node bay elm', 'oak']; candidatePools.add(numericPool);
units = [0.05, 0, 0, 0.5]; ranks = [0, 1];
const numericSection = await main.namespace.generateWords({name: 'code_swift', words: numericPool});
assert.deepEqual(Array.from(numericSection.words), ['1', 'bay']);
assert.deepEqual(Array.from(numericSection.sectionIndexes), [1, 1]);
assert.equal(units.length, 0); assert.equal(ranks.length, 0); sectionCount++;
console.log(`${sectionCount} code-section fixtures passed (actual section order, gates, per-word discarded base draws, finite cut, repeat cache/fresh section, Weakspot boundary; owned adapters, no corpus/RNG/browser parity claim).`);

const previousSectionCount = sectionCount;
await section(['Node Bay Elm', 'Oak'], 2, [0, 1], ['node ', 'bay '], [1, 1], [], 'league_of_legends');
await section(['node-ray', 'foo♀'], 1, [0, 1], ['foo♀ '], [1], [], 'pokemon_1k');
await section(['node item2', 'oak bay'], 2, [0, 1, 0], ['oak ', 'bay '], [1, 1], [], 'pokemon_1k');
await section(['The hallway breathes.', 'Oak bay'], 3, [...Array(101).fill(0), 1, 1],
  ['the ', 'hallway ', 'breathes. '], [1, 1, 1], [], 'typing_of_the_dead', true);
await section(['The hallway breathes!', 'Oak bay'], 3, [0, 1, 1],
  ['the ', 'hallway ', 'breathes! '], [1, 1, 1], [], 'typing_of_the_dead', true);
await section(['aaax bb', 'bb'], 2, [1, 0, ...Array(19).fill(1), 1],
  ['aaax ', 'bb '], [1, 1], ['weakspot'], 'pokemon_1k');
await section(['Node Bay', 'Oak'], 2, [1, 0, ...Array(19).fill(1), 1],
  ['Node ', 'Bay '], [1, 1], ['weakspot'], 'league_of_legends');
await section(['node bay', 'oak elm'], 2, [0, 1], ['kao ', 'mle '], [1, 1], ['backwards'], 'league_of_legends');
await section(['node bay elm', 'oak'], 2, [0, 1], ['node', 'bay'], [1, 1], ['nospace'], 'tamil_old');
repeated = true; ranks = [1];
const ordinaryReplayPool = ['node bay elm', 'oak']; candidatePools.add(ordinaryReplayPool);
const ordinaryRestored = await main.namespace.generateWords({name: 'tamil_old', words: ordinaryReplayPool});
assert.deepEqual(Array.from(ordinaryRestored.words), ['node', 'bay']); assert.deepEqual(ranks, [1]);
config.mode = 'time';
assert.equal((await main.namespace.getNextWord(2, 100, 'bay', 'node')).word, 'oak');
assert.equal(ranks.length, 0); sectionCount++;
repeated = false; activeNames = []; config.mode = 'words'; config.words = 2;
config.language = 'typing_of_the_dead'; config.punctuation = true; config.numbers = false;
units = []; ranks = [0, 1];
const originalPool = ['The hallway breathes!', 'Oak bay']; candidatePools.add(originalPool);
const originalSection = await main.namespace.generateWords({name: config.language,
  words: originalPool, originalPunctuation: true});
assert.deepEqual(Array.from(originalSection.words), ['The ', 'hallway ']);
assert.equal(units.length, 0); assert.equal(ranks.length, 0); sectionCount++;
config.language = 'pokemon_1k'; config.numbers = true;
units = [0.05, 0, 0, 0.5, 0.95, 0.5]; ranks = [0, 1];
const commonPool = ['node bay', 'oak']; candidatePools.add(commonPool);
const commonSection = await main.namespace.generateWords({name: config.language, words: commonPool});
assert.deepEqual(Array.from(commonSection.words), ['1 ', 'bay! ']);
assert.equal(units.length, 0); assert.equal(ranks.length, 0); sectionCount++;
console.log(`${sectionCount - previousSectionCount} ordinary-entry fixtures passed (4 named identity routes, actual gates/case/Weakspot/decoration/original-punctuation/repeat; owned words and runtime adapters, no corpus/RNG/device parity claim).`);

// Metadata-only inventory: read values to count sections, never print, persist
// or import upstream word strings into the native content pool.
const languages = path.join(root, 'frontend/static/languages');
const codeFiles = fs.readdirSync(languages).filter(name => /^code_.*\.json$/.test(name));
const sectionIdentities = codeFiles.flatMap(filename => {
  const language = JSON.parse(fs.readFileSync(path.join(languages, filename), 'utf8'));
  const multiword = language.words.filter(word => word.includes(' ')).length;
  return multiword ? [[language.name, language.words.length, multiword]] : [];
}).sort((a, b) => a[0].localeCompare(b[0]));
assert.equal(codeFiles.length, 69);
assert.deepEqual(sectionIdentities, [['code_abap', 200, 2], ['code_haskell', 208, 5],
  ['code_javascript', 126, 3], ['code_javascript_react', 202, 3], ['code_ocaml', 495, 57],
  ['code_ook', 9, 9], ['code_rust', 192, 13], ['code_typst', 43, 1], ['code_vim', 167, 1]]);
console.log('Metadata-only section inventory passed: 69 code identities, 9 multiword pools; no vocabulary parity claim.');

let ordinaryRawPools = 0, ordinarySectionPools = 0;
const entryMetadata = [];
for (const filename of fs.readdirSync(languages).filter(name => name.endsWith('.json') && !name.startsWith('code_'))) {
  const language = JSON.parse(fs.readFileSync(path.join(languages, filename), 'utf8'));
  if (language.words.some(word => word.includes(' '))) ordinaryRawPools++;
  const multiword = language.words.filter(word => word.replace(/ +/g, ' ')
    .replace(/(^ )|( $)/g, '').split(' ').length > 1).length;
  if (multiword) ordinarySectionPools++;
  if (['league_of_legends', 'pokemon_1k', 'tamil_old', 'typing_of_the_dead'].includes(language.name)) {
    entryMetadata.push([language.name, language.words.length, multiword, language.originalPunctuation ?? false]);
  }
}
assert.equal(ordinaryRawPools, 67); assert.equal(ordinarySectionPools, 66);
assert.deepEqual(entryMetadata.sort((a, b) => a[0].localeCompare(b[0])),
  [['league_of_legends', 442, 229, false], ['pokemon_1k', 1025, 28, false],
    ['tamil_old', 460, 1, false], ['typing_of_the_dead', 10098, 7338, true]]);
console.log('Metadata-only ordinary inventory passed: 67 raw-space identities, 66 normalized multiword pools; 4 entry routes audited, remaining routes not proven equivalent.');
