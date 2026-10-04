// Complete pinned source modules, owned data and explicit bounded adapters.
// Query DSL adapter is not TanStack execution, persistence or browser evidence.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const root = path.resolve(process.argv[2] ?? '');
assert.ok(process.argv[2], 'Read-only reference required');
assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
  '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
const local = id => path.join(root, 'frontend/src/ts', id);
const resolve = (id, importer) => id.startsWith('.') ? path.resolve(path.dirname(importer), id) : id;
const unexpected = label => () => { throw Error('Outside pace selection probe: ' + label); };
let rows = [], activeTags = [], authenticated = true, repeat = false, observed, calls = [];
const now = 1_800_000_000_000;
const config = {mode: 'time', time: 30, words: 50, punctuation: false, numbers: false,
  language: 'english', difficulty: 'normal', lazyMode: false, funbox: [],
  paceCaret: 'last', paceCaretStyle: 'default', paceCaretCustomSpeed: 100};
let quote = {id: 'owned-quote'};

// Only the operations used by the actual one-shot selectors are implemented.
const ref = (alias, field) => ({kind: 'ref', alias, field});
const scope = alias => ({[alias]: new Proxy({}, {get: (_target, field) => ref(alias, field)})});
const operation = (kind, ...args) => ({kind, args});
function value(expression, row) {
  if (expression?.kind === 'ref') return row[expression.alias][expression.field];
  if (!expression?.kind) return expression;
  const args = expression.args.map(it => value(it, row));
  switch (expression.kind) {
    case 'eq': return args[0] === args[1];
    case 'gte': return args[0] >= args[1];
    case 'or': return args.some(Boolean);
    case 'inArray': return args[1]?.includes(args[0]) ?? false;
    default: throw Error('Unsupported DSL expression: ' + expression.kind);
  }
}
class Query {
  constructor() { this.predicates = []; this.orders = []; this.take = Infinity; }
  from(source) { [this.alias, this.source] = Object.entries(source)[0]; return this; }
  where(callback) { this.predicates.push(callback(scope(this.alias))); return this; }
  orderBy(callback, direction) { this.orders.push([callback(scope(this.alias)), direction]); return this; }
  limit(count) { this.take = count; return this; }
  select(callback) { this.selection = callback(scope(this.alias)); return this; }
  findOne() { this.single = true; return this; }
  execute() {
    const data = this.source instanceof Query ? this.source.execute() : rows;
    let matches = data.map(it => ({[this.alias]: it}))
      .filter(row => this.predicates.every(expression => value(expression, row)));
    for (const [expression, direction] of this.orders) matches.sort((a, b) =>
      (value(expression, a) - value(expression, b)) * (direction === 'desc' ? -1 : 1));
    matches = matches.slice(0, this.take);
    if (this.selection) {
      if (!matches.length) return undefined;
      const aggregate = {};
      for (const [key, expression] of Object.entries(this.selection)) {
        assert.equal(expression.kind, 'avg');
        aggregate[key] = matches.reduce((sum, row) => sum + value(expression.args[0], row), 0)
          / matches.length;
      }
      return aggregate;
    }
    const selected = matches.map(row => row[this.alias]);
    return this.single ? selected[0] : selected;
  }
}
let active = false, resultVisible = false, activeWord = 0, clock = 1000;
let hidden = true, moves = [], nextTimer = 0;
const timers = new Map();
class OwnedCaret {
  hide() { hidden = true; } show() { hidden = false; } isHidden() { return hidden; }
  stopAllAnimations() {} clearMargins() {} setStyle() {}
  goTo(options) { moves.push(structuredClone(options)); }
}
class OwnedDate extends Date { static now() { return now; } }
const bindings = new Map([
  [local('config/store'), {Config: config, getConfig: config}],
  [local('states/test'), {isPaceRepeat: () => repeat, setPaceCaretWpm: speed => { observed = speed; },
    getCurrentQuote: () => quote, getActiveWordIndex: () => activeWord,
    isTestActive: () => active, getResultVisible: () => resultVisible,
    isLanguageRightToLeft: () => false, isDirectionReversed: () => false}],
  [local('states/core'), {isAuthenticated: () => authenticated}],
  [local('utils/misc'), {getMode2: c => c.mode === 'time' ? String(c.time) :
    c.mode === 'words' ? String(c.words) : c.mode === 'quote' ? quote.id : c.mode}],
  [local('test/funbox/list'), {getActiveFunboxes: () => config.funbox}],
  [local('collections/tags'), {getActiveTagsOnce: async () => activeTags.map(_id => ({_id})),
    getActiveTagsPB: (...args) => { calls.push(args); return activeTags.length ? 72.49 : 0; }}],
  [local('elements/caret'), {Caret: OwnedCaret}],
  [local('utils/dom'), {qsr: () => ({})}],
  [local('events/config'), {configEvent: {subscribe() {}}}],
  [local('events/auth'), {authEvent: {dispatch: unexpected('auth dispatch')}}],
  [local('states/snapshot'), {_setSnapshot() {}}],
  [local('utils/date-and-time'), {getFirstDayOfTheWeek: () => 1}],
  [local('hooks/effects'), {createEffectOn() {}}],
  [local('queries'), {queryClient: {}}],
  [local('queries/utils/keys'), {baseKey: () => ['owned-results']}],
  ['@tanstack/query-db-collection', {queryCollectionOptions: options => options}],
  ['@tanstack/solid-db', {Query, queryOnce: async callback => callback(new Query()).execute(),
    eq: (...args) => operation('eq', ...args), gte: (...args) => operation('gte', ...args),
    or: (...args) => operation('or', ...args), inArray: (...args) => operation('inArray', ...args),
    avg: argument => operation('avg', argument), BTreeIndex: class {},
    createCollection: () => ({createIndex() {}}),
    createOptimisticAction: () => unexpected('optimistic mutation')}],
]);
const dormant = new Set(['ape', 'states/notifications', 'elements/test-activity-calendar',
  'states/loader-bar', 'constants/default-snapshot', 'ape/server-configuration',
  'states/header', 'ape/user', 'utils/snapshot-init-error', 'states/result-filters',
  'collections/utils/misc', 'utils/strings'].map(local).concat(['date-fns',
  '@tanstack/solid-query', 'solid-js', '@monkeytype/schemas/users',
  '@monkeytype/schemas/configs', '@monkeytype/schemas/shared',
  '@monkeytype/schemas/languages', '@monkeytype/schemas/results', '@monkeytype/funbox']));
const actualIDs = ['test/pace-caret', 'collections/results', 'db', 'test/test-words'].map(local);
const modules = new Map(), importedNames = new Map();
const context = vm.createContext({console, Date: OwnedDate, performance: {now: () => clock},
  setTimeout: (callback, delay) => {
    const id = ++nextTimer; timers.set(id, {callback, due: clock + delay}); return id;
  }, clearTimeout: id => timers.delete(id)});
for (const id of actualIDs) {
  const code = stripTypeScriptTypes(fs.readFileSync(id + '.ts', 'utf8'), {mode: 'transform'});
  modules.set(id, new vm.SourceTextModule(code, {identifier: id, context}));
  for (const match of code.matchAll(/import\s+([\s\S]*?)\s+from\s+["']([^"']+)["'];/g)) {
    const dependency = resolve(match[2], id), clause = match[1].trim();
    const names = importedNames.get(dependency) ?? new Set();
    if (clause.startsWith('{')) for (const name of clause.slice(1, clause.lastIndexOf('}'))
      .split(',').map(it => it.trim()).filter(Boolean)) names.add(name.split(/\s+as\s+/)[0]);
    else if (!clause.startsWith('*')) names.add('default');
    importedNames.set(dependency, names);
  }
}
function moduleFor(id) {
  if (modules.has(id)) return modules.get(id);
  assert.ok(bindings.has(id) || dormant.has(id), 'Unapproved adapter: ' + id);
  const values = {...(bindings.get(id) ?? {})};
  for (const name of importedNames.get(id) ?? []) values[name] ??= unexpected(id + '.' + name);
  const module = new vm.SyntheticModule(Object.keys(values), function () {
    for (const [name, binding] of Object.entries(values)) this.setExport(name, binding);
  }, {identifier: id, context});
  modules.set(id, module); return module;
}
const module = modules.get(local('test/pace-caret'));
await module.link((id, importer) => moduleFor(resolve(id, importer.identifier)));
await module.evaluate();
const pace = module.namespace, db = modules.get(local('db')).namespace;
const queries = modules.get(local('collections/results')).namespace;
const words = modules.get(local('test/test-words')).namespace.words;
let fixtures = 0;
async function target(mode, expected) {
  config.paceCaret = mode; await pace.init(); assert.equal(observed, expected); fixtures++;
}
function row(wpm, {age = 0, tags = [], ...overrides} = {}) {
  return {mode: 'time', mode2: '30', punctuation: false, numbers: false, language: 'english',
    difficulty: 'normal', lazyMode: false, timestamp: now - age * 1000, tags,
    wpm, acc: 100, ...overrides};
}
for (const speed of [1, 9, 60.49, 350, 420]) {
  repeat = false; pace.setLastTestWpm(speed); await target('last', speed);
}
pace.setLastTestWpm(80); repeat = true;
pace.setLastTestWpm(120.25); await target('last', 120.25);
pace.setLastTestWpm(60); await target('off', 120.25);
config.paceCaretCustomSpeed = 11.25; await target('custom', 11.25);
for (const speed of [0, 0.25, 0.99, 1, 9, 60.123456789, 350, 1e100, Number.MAX_VALUE]) {
  config.paceCaretCustomSpeed = speed;
  await target('custom', speed < 1 ? undefined : speed);
}
// Raw invalid state may still admit infinity; native finite-input validation
// deliberately excludes it. This is not a schema or browser-input probe.
config.paceCaretCustomSpeed = Infinity; await target('custom', Infinity);
repeat = false; await target('off', undefined);
for (const speed of [0, 0.99, -1, NaN]) { pace.setLastTestWpm(speed); await target('last', undefined); }
pace.setLastTestWpm(NaN); repeat = true; pace.setLastTestWpm(120);
await target('last', undefined); repeat = false;

rows = Array.from({length: 10}, (_, index) => row(50, {age: index + 1}));
rows.push(row(150, {bailedOut: true}));
await target('average', 60);
rows = [row(60.49), row(60.50, {bailedOut: true})];
await target('average', 60); await target('daily', 61);
rows = [row(60), row(120, {age: 86400, bailedOut: true}),
  row(140, {age: 86400.01, bailedOut: true})];
await target('daily', 120);
rows = [row(60, {tags: ['focus']}), row(120, {tags: ['focus'], bailedOut: true}),
  row(300, {tags: ['other'], bailedOut: true}), row(500, {mode2: '60'}),
  row(500, {punctuation: true}), row(500, {numbers: true}), row(500, {language: 'other'}),
  row(500, {difficulty: 'master'}), row(500, {lazyMode: true})];
activeTags = ['focus']; await target('average', 90); await target('daily', 120);
const filter = {...config, mode2: '30'};
assert.equal((await queries.getUserAverage10Once(filter)).wpm, 90); fixtures++;
authenticated = false; await target('average', undefined); await target('daily', undefined);
authenticated = true; activeTags = []; rows = [];
await target('average', undefined); await target('daily', undefined);
const pb = {punctuation: false, numbers: false, language: 'english', difficulty: 'normal',
  lazyMode: false, wpm: 60.49};
db.setSnapshot({personalBests: {time: {'30': [pb], '60': [{...pb, wpm: 300}]}}},
  {dispatchEvent: false});
await target('pb', 60.49);
config.funbox = [{canGetPb: false}]; await target('pb', undefined);
activeTags = ['focus']; await target('tagPb', 72.49);
assert.deepEqual(calls.at(-1), ['time', '30', false, false, 'english', 'normal', false]); fixtures++;
activeTags = []; await target('tagPb', undefined);
config.funbox = []; config.time = 60; await target('pb', 300); config.time = 30;
for (const [key, setting] of [['punctuation', true], ['numbers', true], ['language', 'other'],
  ['difficulty', 'expert'], ['lazyMode', true]]) {
  const original = config[key]; config[key] = setting; await target('pb', undefined); config[key] = original;
}
let animationFixtures = 0;
async function prepare(rawWords = ['ab ', 'cd ', 'efg']) {
  pace.reset(); timers.clear(); moves = []; clock = 1000; activeWord = 0;
  active = true; resultVisible = false; config.blindMode = false;
  config.paceCaret = 'custom'; config.paceCaretCustomSpeed = 60;
  words.reset(); rawWords.forEach(word => words.push(word, 0));
  await pace.init(); pace.start();
}
async function deliver(at) {
  clock = at;
  for (let count = 0; ; count++) {
    assert.ok(count < 1000, 'Owned timer delivery bound');
    const ready = [...timers].filter(([, timer]) => timer.due <= clock)
      .sort((a, b) => a[1].due - b[1].due)[0];
    if (!ready) break;
    timers.delete(ready[0]); ready[1].callback(); await Promise.resolve();
  }
}
function position(wordIndex, letterIndex, duration) {
  const move = moves.at(-1);
  assert.equal(move.wordIndex, wordIndex); assert.equal(move.letterIndex, letterIndex);
  if (duration !== undefined) assert.ok(Math.abs(move.animationOptions.duration - duration) < 1e-8);
}
await prepare(); position(0, 1, 200); animationFixtures++;
await deliver(1200); position(0, 2, 200);
await deliver(1400); position(1, 0, 200); animationFixtures++;
await prepare(); pace.handleSpace(false, words.get(0).textWithCommit);
pace.handleSpace(false, words.get(0).textWithCommit);
await deliver(1200); position(1, 2); animationFixtures++;
pace.handleSpace(true, words.get(0).textWithCommit);
pace.handleSpace(true, words.get(0).textWithCommit);
await deliver(1400); position(1, 0); animationFixtures++;
await prepare(); pace.handleSpace(false, words.get(0).textWithCommit);
config.blindMode = true; await deliver(1200); position(0, 2);
await deliver(1400); position(1, 0);
config.blindMode = false; await deliver(1600); position(2, 1); animationFixtures++;
await prepare(); config.blindMode = true; pace.handleSpace(false, words.get(0).textWithCommit);
config.blindMode = false; pace.handleSpace(true, words.get(0).textWithCommit);
await deliver(1200); position(0, 2); animationFixtures++;
await prepare(['😀 ', 'x ', 'abcd']);
pace.handleSpace(false, words.get(0).textWithCommit);
await deliver(1200); position(2, 0); animationFixtures++;
await prepare(['ab', 'cd', 'efg']); pace.handleSpace(false, words.get(0).textWithCommit);
await deliver(1200); position(1, 1); animationFixtures++;
await prepare(['ab\n', 'cd ', 'efg']); pace.handleSpace(false, words.get(0).textWithCommit);
await deliver(1200); position(1, 2); animationFixtures++;
await prepare(); await deliver(1250); position(0, 2, 150); animationFixtures++;
await prepare(); await deliver(1400); position(1, 0, 200); animationFixtures++;
await prepare(['ab']); await deliver(1400); position(1, 0);
await deliver(1600); assert.equal(hidden, true); animationFixtures++;
await prepare(); const beforeReset = moves.length; pace.reset();
await deliver(1200); assert.equal(moves.length, beforeReset); animationFixtures++;
await prepare(); const beforeInit = moves.length; await pace.init();
await deliver(1200); assert.equal(moves.length, beforeInit); assert.equal(hidden, true); animationFixtures++;
await prepare(); resultVisible = true; const beforeResult = moves.length;
await deliver(1200); assert.equal(moves.length, beforeResult); animationFixtures++;
await prepare(); active = false; const beforeInactive = moves.length;
await deliver(1200); assert.equal(moves.length, beforeInactive); animationFixtures++;
await prepare(); config.paceCaretCustomSpeed = 120;
await deliver(1200); position(0, 2, 200); animationFixtures++;
pace.reset();
assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
console.log('pace source probe passed: ' + fixtures + ' selection and ' + animationFixtures
  + ' progression fixtures; 4 complete source modules; bounded Query DSL, tag PB, monotonic timer '
  + 'and caret adapters; no browser, GUI, live account or copied assets');
