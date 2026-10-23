// QA only: execute the pinned quote controller and generator selection method
// over our authored catalog. No reference quote text or asset is loaded.
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
const frontend = path.join(root, 'frontend/src/ts');
const read = relative => fs.readFileSync(path.join(frontend, relative), 'utf8');
const state = {snapshot: null, current: null, selected: 101, last: false, changes: []};
const listeners = [];
const context = vm.createContext({Config: {},
  isRepeated: () => false, showLoaderBar() {}, hideLoaderBar() {},
  getSelectedQuoteId: () => state.selected,
  setCurrentQuote: quote => { state.current = quote; }, getCurrentQuote: () => state.current,
  WordGenError: class extends Error {},
  setConfig: (key, value) => {
    context.Config[key] = value;
    state.changes.push([key, structuredClone(value)]);
    listeners.forEach(notify => notify({key, newValue: value}));
    return true;
  },
});
function extract(source, start, end) {
  const first = source.indexOf(start), last = source.indexOf(end, first);
  assert.ok(first >= 0 && last > first, `Pinned method not found: ${start}`);
  return source.slice(first, last).replace(/^export /, '');
}
vm.runInContext(stripTypeScriptTypes(extract(read('utils/strings.ts'),
  'export function removeLanguageSize(', '\n}\n') + '\n}', {mode: 'transform'}), context);
context.Strings = {removeLanguageSize: context.removeLanguageSize};
vm.runInContext(stripTypeScriptTypes(extract(read('config/setters.ts'),
  'export function setQuoteLengthAll(', '\nexport function toggleFunbox'), {mode: 'transform'}), context);
vm.runInContext(stripTypeScriptTypes(extract(read('test/words-generator.ts'),
  'async function getQuoteWordList(', '\nlet currentWordset:'), {mode: 'transform'}), context);

const authoredQuotes = [
  [101, 5], [102, 7], [103, 15], [104, 25], [105, 35],
].map(([id, length]) => ({id, length, text: `Owned QA sample ${id}`, source: 'Typebar QA'}));
const data = {language: 'english', quotes: authoredQuotes, groups: [[0, 10], [11, 20], [21, 30], [31, 40]]};
const adapters = {
  '../utils/strings': {removeLanguageSize: context.removeLanguageSize},
  '@monkeytype/util/numbers': {randomIntFromRange: (min, max) => state.last ? max : min},
  '../utils/json-data': {cachedFetchJson: async url => url.includes('spanish')
    ? {language: 'spanish', quotes: [], groups: []} : structuredClone(data)},
  '../events/config': {configEvent: {subscribe: callback => listeners.push(callback)}},
  '../db': {getSnapshot: () => state.snapshot},
  '../ape': {default: {}},
  '@monkeytype/util/trycatch': {tryCatch: async promise => {
    try { return {data: await promise}; } catch (error) { return {error}; }
  }},
  '@monkeytype/schemas/languages': {Language: undefined},
  '@monkeytype/schemas/quotes': {QuoteData: undefined},
  '../types/quotes': {Quote: undefined, QuoteWithTextSplit: undefined},
};
const modules = new Map();
function moduleFor(id) {
  if (modules.has(id)) return modules.get(id);
  let result;
  if (id === 'controller' || id === '../utils/arrays') {
    const relative = id === 'controller' ? 'controllers/quotes-controller.ts' : 'utils/arrays.ts';
    result = new vm.SourceTextModule(stripTypeScriptTypes(read(relative), {mode: 'transform'}), {context});
  } else {
    const values = adapters[id];
    assert.ok(values, `Unexpected pinned dependency: ${id}`);
    result = new vm.SyntheticModule(Object.keys(values), function() {
      for (const [key, value] of Object.entries(values)) this.setExport(key, value);
    }, {context});
  }
  modules.set(id, result);
  return result;
}
const module = moduleFor('controller');
await module.link(id => moduleFor(id));
await module.evaluate();
const controller = module.namespace.default;
context.QuotesController = controller;

const groups = [[]];
for (let length = 1; length <= 4; length++) {
  const append = prefix => {
    if (prefix.length === length) { groups.push(prefix); return; }
    for (const value of [-3, -2, 0, 1, 2, 3]) append([...prefix, value]);
  };
  append([]);
}
const inputs = groups.map(groups => ({groups, selectedQuoteID: '101', favoriteIDs: ['103', '103', '999']}));
inputs.push(
  {groups: [-3], favoriteIDs: null}, {groups: [-3], favoriteIDs: []},
  {groups: [-3, 0], favoriteIDs: ['999', '103']},
  {groups: [-3, -2], favoriteIDs: ['103', '999'], randomLast: true},
  {groups: [-2], selectedQuoteID: '999'}, {groups: [-2], selectedQuoteID: null},
  {groups: [0, 1], emptyCatalog: true},
);
const fixtures = [];
for (const input of inputs) {
  const language = input.emptyCatalog ? 'spanish' : 'english_1k';
  context.Config = {language, mode: 'quote', quoteLength: [...input.groups], britishEnglish: false};
  state.last = input.randomLast ?? false;
  state.selected = Number(input.selectedQuoteID ?? 999);
  state.current = null;
  state.snapshot = input.favoriteIDs == null ? null : {favoriteQuotes: {
    english_1k: input.favoriteIDs.slice(0, 2), english_5k: input.favoriteIDs.slice(2), spanish: ['101'],
  }};
  await controller.getQuotes(language, input.groups);
  listeners.forEach(notify => notify({key: 'quoteLength', newValue: input.groups}));
  assert.ok(Array.isArray(controller.quoteQueue), 'Expected actual controller queue');
  const pool = controller.quoteQueue.map(quote => String(quote.id));
  state.changes = [];
  const draws = [];
  let failure = null;
  for (let index = 0; index < Math.max(2, pool.length * 2); index++) {
    try {
      await context.getQuoteWordList({name: language});
      draws.push(String(state.current.id));
    } catch (error) { failure = error.message; break; }
  }
  fixtures.push({...input, pool, draws, failure, recovery: Object.fromEntries(state.changes)});
}
verify();
assert.equal(fixtures.length, 1562);
console.log(JSON.stringify({fixtures}));
