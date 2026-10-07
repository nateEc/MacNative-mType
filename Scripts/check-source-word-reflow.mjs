// QA only: execute the complete pinned word-update function and real debounce,
// SlowTimer, strings and words modules. DOM geometry/hints/lineJump are adapters.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const [argument, option] = process.argv.slice(2);
assert.ok(argument && (!option || option === '--emit-fixtures'));
const root = path.resolve(argument);
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/test/test-ui.ts'), 'utf8');
const start = source.indexOf('export let pendingWordData:');
const end = source.indexOf('// this is needed in tape mode', start);
assert.ok(start >= 0 && end > start);
const callback = stripTypeScriptTypes(source.slice(start, end), {mode: 'transform'})
  .replace(/^export /gm, '');
const cases = [];
for (const mode of ['time', 'words', 'quote', 'custom', 'zen'])
for (const slow of [false, true]) for (const showAllLines of [false, true])
for (const transitioning of [false, true]) for (const top of [0, 45, 46, 89, 90, 91, 135])
for (const indicateTypos of ['off', 'both']) {
  const events = [], frames = new Map(), jumps = [];
  let nextFrame = 0, canceled = 0;
  const context = vm.createContext({console: {error() {}},
    requestAnimationFrame: fn => { frames.set(++nextFrame, fn); return nextFrame; },
    cancelAnimationFrame: id => { if (frames.delete(id)) canceled++; },
  });
  const adapters = {
    '@monkeytype/schemas/languages': {Language: undefined},
    'states/test': {getActiveWordIndex: () => 0},
  };
  const modules = new Map();
  function moduleFor(id) {
    if (modules.has(id)) return modules.get(id);
    let module;
    if (adapters[id]) {
      const bindings = adapters[id];
      module = new vm.SyntheticModule(Object.keys(bindings), function() {
        for (const [name, value] of Object.entries(bindings)) this.setExport(name, value);
      }, {identifier: id, context});
    } else {
      assert.ok(['utils/strings', 'utils/debounced-animation-frame',
        'legacy-states/slow-timer', 'test/test-words'].includes(id));
      module = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(
        path.join(root, 'frontend/src/ts', id + '.ts'), 'utf8'), {mode: 'transform'}),
        {identifier: id, context});
    }
    modules.set(id, module); return module;
  }
  for (const id of ['utils/strings', 'utils/debounced-animation-frame',
    'legacy-states/slow-timer', 'test/test-words']) {
    const module = moduleFor(id);
    await module.link((specifier, parent) => moduleFor(specifier.startsWith('.')
      ? path.posix.normalize(path.posix.join(path.posix.dirname(parent.identifier), specifier)) : specifier));
    await module.evaluate();
  }
  const SlowTimer = modules.get('legacy-states/slow-timer').namespace;
  if (slow) SlowTimer.set();
  const TestWords = modules.get('test/test-words').namespace;
  TestWords.words.push('aa ', 0);
  const word = {
    setHtml: html => {
      assert.match(html, mode === 'zen' ? />x<\/letter>/ : /class="incorrect/);
      events.push('render');
    },
    qsa: () => [], appendHtml: () => events.push('appendHints'),
    native: {getElementsByTagName: () => []},
    getOffsetTop: () => { events.push('measure'); return top; },
  };
  Object.assign(context, {
    Config: {mode, showAllLines, tapeMode: 'letter', indicateTypos, compositionDisplay: 'replace'},
    SlowTimer, TestWords, Strings: modules.get('utils/strings').namespace,
    requestDebouncedAnimationFrame: modules.get('utils/debounced-animation-frame').namespace.requestDebouncedAnimationFrame,
    activeWordTop: 45, wordTopBeforeLineJump: 90, lineTransition: transitioning,
    getWordElement: () => word, findSingleActiveFunboxWithFunction: () => null,
    createHintsHtml: () => { events.push('makeHints'); return '<hint>x</hint>'; },
    joinOverlappingHints: async () => { events.push('joinHints'); },
    scrollTape: () => events.push('tape'),
    lineJump: async from => { events.push('jump'); jumps.push(from); },
  });
  new vm.Script(callback, {filename: 'pinned-complete-updateWordLetters'}).runInContext(context);
  await context.updateWordLetters({wordIndex: 0, input: 'a', compositionData: ''});
  await context.updateWordLetters({wordIndex: 0, input: 'ax', compositionData: ''});
  assert.equal(vm.runInContext('pendingWordData.get(0)', context), 'ax');
  assert.equal(frames.size, 1);
  assert.equal(canceled, 1);
  for (const [id, frame] of [...frames]) { frames.delete(id); frame(); }
  // The real RAF wrapper intentionally does not return the async callback's
  // promise. Drain its hint-await/jump-await continuations, not a fake await RAF.
  for (let tick = 0; tick < 8; tick++) await Promise.resolve();
  assert.equal(vm.runInContext('pendingWordData.size', context), 0);
  const eligible = (mode === 'zen' || slow) && !showAllLines;
  const expected = eligible && top > 45 && (!transitioning || top > 90);
  assert.deepEqual(jumps, expected ? [45] : []);
  const thresholdAfter = context.wordTopBeforeLineJump;
  assert.equal(thresholdAfter, eligible && top > 45 && !transitioning ? top : 90);
  const order = ['render'];
  if (mode !== 'zen' && indicateTypos === 'both') order.push('makeHints', 'appendHints', 'joinHints');
  order.push('tape');
  if (eligible) order.push('measure');
  if (expected) order.push('jump');
  assert.deepEqual(events, order);
  cases.push({mode, slow, showAllLines, transitioning, top, indicateTypos,
    jumpFrom: jumps[0] ?? null, thresholdAfter});
}
assert.equal(cases.length, 560);
const jumpStart = source.indexOf('function removeTestElements(');
const jumpEnd = source.indexOf('\nexport function setJoiningClass(', jumpStart);
assert.ok(jumpStart >= 0 && jumpEnd > jumpStart);
const jumpCode = stripTypeScriptTypes(source.slice(jumpStart, jumpEnd), {mode: 'transform'});
const lineJumps = [];
for (const smooth of [false, true]) for (const initialLine of [0, 1]) for (const prefixTop of [0, 45]) {
  let finishAnimation;
  const caret = [];
  const words = [prefixTop, 90].map(top => ({
    native: {isConnected: true}, hasClass: name => name === 'word',
    getOffsetTop: () => top, getOuterHeight: () => 45, getOffsetHeight: () => 33,
    remove() { this.native.isConnected = false; },
  }));
  const context = vm.createContext({currentTestLine: initialLine, lineTransition: false,
    activeWordTop: 45, activeWordHeight: 33, Config: {smoothLineScroll: smooth},
    getActiveWordElement: () => words[1],
    wordsEl: {getChildren: () => words.filter(word => word.native.isConnected), setStyle() {},
      promiseAnimate: () => new Promise(resolve => { finishAnimation = resolve; })},
    Caret: {caret: {handleLineJump: options => caret.push(options)}},
    PaceCaret: {caret: {handleLineJump() {}}}, updateWordsWrapperHeight() {},
  });
  new vm.Script(jumpCode).runInContext(context);
  const pending = vm.runInContext('lineJump(45)', context);
  const willRemove = initialLine > 0 && prefixTop < 45;
  assert.equal(caret.length, willRemove ? 1 : 0);
  assert.equal(words[0].native.isConnected, !willRemove || smooth);
  if (finishAnimation) finishAnimation();
  await pending;
  assert.equal(words[0].native.isConnected, !willRemove);
  assert.equal(context.currentTestLine, initialLine + 1);
  assert.equal(context.lineTransition, false);
  if (willRemove) assert.deepEqual({...caret[0]}, {newMarginTop: -45, duration: smooth ? 125 : 0});
  lineJumps.push({smooth, initialLine, prefixTop, willRemove});
}
verify();
if (option) console.log(JSON.stringify({cases, lineJumps}));
else console.log('Word reflow source passed: 560 complete word-update cases; real latest-input RAF debounce, SlowTimer, strings and words; ordered render/hints/tape/measure/jump; 8 complete lineJump first/no-prefix/smooth cases; controlled DOM/hints/animation boundary, no browser/font/animation-queue equivalence claim');
