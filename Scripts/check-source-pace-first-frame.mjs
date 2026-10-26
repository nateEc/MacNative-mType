// QA only: execute complete pinned pace and word-directory modules in memory.
// Owned clock, timer queue and caret adapters prove requests, not browser pixels
// or delivery of any later timer. No reference implementation is packaged.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

assert.equal(process.argv.length, 3, 'Exactly one read-only reference path required');
const root = path.resolve(process.argv[2]);
const revision = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verifyReference() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), revision);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verifyReference();
const sourcePath = id => path.join(root, 'frontend/src/ts', id);
const config = {mode: 'time', paceCaret: 'custom', paceCaretStyle: 'default',
  paceCaretCustomSpeed: 60, blindMode: false};
const unexpected = name => () => { throw Error('Outside first-frame probe: ' + name); };
let milliseconds = 0, moves = [], hidden = true, publishedSpeed;
let nextTimer = 0;
const timers = new Map();
class OwnedCaret {
  hide() { hidden = true; }
  show() { hidden = false; }
  isHidden() { return hidden; }
  goTo(options) { moves.push(structuredClone(options)); }
  stopAllAnimations() { throw Error('Unexpected caret animation reset'); }
  clearMargins() { throw Error('Unexpected caret margin reset'); }
  setStyle() { throw Error('Unexpected caret style edit'); }
}
const adapters = new Map([
  [sourcePath('config/store'), {Config: config}],
  [sourcePath('db'), {getLocalPB: unexpected('local PB')}],
  [sourcePath('collections/tags'), {getActiveTagsPB: unexpected('tag PB')}],
  [sourcePath('collections/results'), {getUserAverage10Once: unexpected('average'),
    getUserDailyBestOnce: unexpected('daily best')}],
  [sourcePath('utils/misc'), {getMode2: () => '30'}],
  [sourcePath('events/config'), {configEvent: {subscribe() {}}}],
  [sourcePath('test/funbox/list'), {getActiveFunboxes: unexpected('funbox selection')}],
  [sourcePath('elements/caret'), {Caret: OwnedCaret}],
  [sourcePath('utils/dom'), {qsr: () => ({})}],
  [sourcePath('states/test'), {isDirectionReversed: () => false, isLanguageRightToLeft: () => false,
    getActiveWordIndex: () => 0, getCurrentQuote: () => null, getResultVisible: () => false,
    isPaceRepeat: () => false, isTestActive: () => true,
    setPaceCaretWpm: speed => { publishedSpeed = speed; }}],
]);
const context = vm.createContext({console: {log() {}, error: unexpected('source error')},
  performance: {now: () => milliseconds},
  setTimeout(callback, delay) {
    assert.ok(Number.isFinite(delay) && delay >= 0);
    const id = ++nextTimer; timers.set(id, {callback, delay}); return id;
  },
  clearTimeout: id => timers.delete(id)});
const modules = new Map();
for (const name of ['test/pace-caret', 'test/test-words']) {
  const id = sourcePath(name);
  modules.set(id, new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(id + '.ts', 'utf8'),
    {mode: 'transform'}), {identifier: id, context}));
}
function resolveModule(id, importer) {
  assert.ok(id.startsWith('.'), 'Unexpected external import: ' + id);
  const resolved = path.resolve(path.dirname(importer), id);
  if (modules.has(resolved)) return modules.get(resolved);
  assert.ok(adapters.has(resolved), 'Unapproved source adapter: ' + id);
  const values = adapters.get(resolved);
  const module = new vm.SyntheticModule(Object.keys(values), function () {
    for (const [key, value] of Object.entries(values)) this.setExport(key, value);
  }, {identifier: resolved, context});
  modules.set(resolved, module);
  return module;
}
const source = modules.get(sourcePath('test/pace-caret'));
await source.link((id, importer) => resolveModule(id, importer.identifier));
await source.evaluate();
const pace = source.namespace, words = modules.get(sourcePath('test/test-words')).namespace.words;
const fixtures = [];
for (const speed of [1, 60, 1e12, 1e100, Number.MAX_VALUE / 5, Number.MAX_VALUE]) {
  for (const origin of [0, 0.001, 600, 1000]) {
    for (const rawWords of [['ab ', 'cd'], ['😀 ', 'x']]) {
      pace.reset(); assert.equal(timers.size, 0);
      moves = []; milliseconds = origin * 1000;
      config.paceCaretCustomSpeed = speed;
      words.reset(); rawWords.forEach(word => words.push(word, 0));
      await pace.init(); assert.equal(publishedSpeed, speed); assert.equal(hidden, true);
      pace.start();
      assert.equal(hidden, false); assert.equal(moves.length, 1); assert.equal(timers.size, 1);
      const first = moves[0];
      assert.equal(first.wordIndex, 0); assert.equal(first.letterIndex, 1);
      assert.equal(first.animate, true); assert.equal(first.animationOptions.easing, 'linear');
      // A word commit records correction; it does not deliver the queued timer
      // or issue a second caret request at this same clock sample.
      pace.handleSpace(false, words.get(0).textWithCommit);
      assert.equal(moves.length, 1); assert.equal(timers.size, 1); assert.equal(hidden, false);
      fixtures.push({speed, origin, rawWords, word: first.wordIndex, letter: first.letterIndex,
        durationMilliseconds: first.animationOptions.duration, requestsAfterWrongCommit: moves.length});
    }
  }
}
pace.reset(); assert.equal(timers.size, 0);
verifyReference();
console.log(JSON.stringify({revision, actualModules: 2, fixtures}));
