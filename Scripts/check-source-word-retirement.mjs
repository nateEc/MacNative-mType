// QA only: full pinned before-delete module and complete lineJump/removal functions.
// DOM metrics, animation completion and input state are owned, not a browser.
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
const start = source.indexOf('function removeTestElements(');
const end = source.indexOf('\nexport function setJoiningClass(', start);
assert.ok(start >= 0 && end > start);
const code = stripTypeScriptTypes(source.slice(start, end), {mode: 'transform'});
const sequences = [];
for (const smooth of [false, true]) for (const perRow of [1, 2]) for (const rowHeight of [25, 45, 59]) {
  let active = 0, finishAnimation;
  const words = Array.from({length: perRow * 6}, (_, index) => ({
    index, row: Math.floor(index / perRow), native: {isConnected: true},
    hasClass: name => name === 'word',
    getOffsetTop() { return 10 + (this.row - firstRow()) * rowHeight; },
    getOuterHeight: () => rowHeight, getOffsetHeight: () => rowHeight - 5,
    remove() { this.native.isConnected = false; },
  }));
  const connected = () => words.filter(word => word.native.isConnected);
  const firstRow = () => connected()[0]?.row ?? 6;
  const context = vm.createContext({currentTestLine: 0, lineTransition: false, activeWordTop: 0,
    activeWordHeight: 0, Config: {smoothLineScroll: smooth},
    getActiveWordElement: () => words[active],
    wordsEl: {getChildren: connected, setStyle() {},
      promiseAnimate: options => { assert.equal(options.duration, 125);
        return new Promise(resolve => { finishAnimation = resolve; }); }},
    Caret: {caret: {handleLineJump() {}}}, PaceCaret: {caret: {handleLineJump() {}}},
    updateWordsWrapperHeight() {},
  });
  new vm.Script(code).runInContext(context, {timeout: 1_000});
  const steps = [];
  for (let row = 1; row < 6; row++) {
    context.previousTop = words[active].getOffsetTop(); active = row * perRow;
    const before = connected()[0].index;
    const pending = new vm.Script('lineJump(previousTop)').runInContext(context, {timeout: 1_000});
    const during = connected()[0].index;
    if (smooth && row > 1) {
      assert.equal(during, before, 'Old words remain until the animation resolves');
      assert.equal(context.lineTransition, true);
      assert.equal(typeof finishAnimation, 'function'); finishAnimation(); finishAnimation = undefined;
    }
    await pending;
    const after = connected()[0].index;
    assert.equal(after, Math.max(0, row - 1) * perRow);
    assert.equal(context.lineTransition, false);
    steps.push({activeWordIndex: active, before, during, after});
  }
  sequences.push({smooth, perRow, rowHeight, steps});
}

const file = path.join(root, 'frontend/src/ts/input/handlers/before-delete.ts');
const deleteCode = stripTypeScriptTypes(fs.readFileSync(file, 'utf8'), {mode: 'transform'});
const cases = [];
for (const freedom of [false, true]) for (const confidence of ['off', 'on', 'max']) {
  if (freedom && confidence !== 'off') continue;
  for (const correct of [false, true]) for (const empty of [false, true]) for (const present of [false, true]) {
    const context = vm.createContext({});
    const adapters = new Map([
      ['../../config/store', {Config: {freedomMode: freedom, confidenceMode: confidence}}],
      ['../../test/test-words', {words: {get: () => ({textWithCommit: 'ab '})}}],
      ['../input-element', {getInputElementValue: () => ({inputValue: empty ? '' : 'c'})}],
      ['../../test/test-ui', {getWordElement: () => present ? {} : null}],
      ['../state', {isAwaitingNextWord: () => false}],
      ['../../test/events/data', {getInputForWord: () => correct ? 'ab ' : 'ax '}],
      ['../../states/test', {isTestRestarting: () => false, getActiveWordIndex: () => 1,
        isResultCalculating: () => false, isTestActive: () => true}],
    ]);
    const module = new vm.SourceTextModule(deleteCode, {identifier: file, context});
    await module.link(id => {
      assert.ok(adapters.has(id), 'Unexpected dependency: ' + id);
      const bindings = adapters.get(id);
      return new vm.SyntheticModule(Object.keys(bindings), function() {
        for (const [name, value] of Object.entries(bindings)) this.setExport(name, value);
      }, {identifier: id, context});
    });
    await module.evaluate();
    let prevented = false;
    module.namespace.onBeforeDelete({preventDefault: () => { prevented = true; }});
    if (empty && !present) assert.equal(prevented, true);
    if (freedom && !(empty && !present)) assert.equal(prevented, false);
    cases.push({freedom, confidence, correct, empty, present, prevented});
  }
}
const insertSource = fs.readFileSync(path.join(root, 'frontend/src/ts/input/handlers/insert-text.ts'), 'utf8');
const hardStart = insertSource.indexOf('function handleDeleteOnError(');
const hardEnd = insertSource.indexOf('\nexport async function onInsertText(', hardStart);
assert.ok(hardStart >= 0 && hardEnd > hardStart);
const hardCode = stripTypeScriptTypes(insertSource.slice(hardStart, hardEnd), {mode: 'transform'});
const hardCases = [];
for (const mode of ['letter', 'word', 'letter_hard', 'word_hard']) for (const present of [false, true]) {
  let input = 'x', returned = false;
  const context = vm.createContext({Config: {deleteOnError: mode}, getCurrentInput: () => input,
    setInputElementValue: value => { input = value; },
    replaceInputElementLastValueChar: () => { input = input.slice(0, -1); },
    logDeleteOnErrorEvent() {}, getActiveWordIndex: () => 1,
    TestUI: {getWordElement: () => present ? {} : null},
    goToPreviousWord: () => { returned = true; }, getInputElementValue: () => ({inputValue: input}),
  });
  new vm.Script(hardCode).runInContext(context, {timeout: 1_000});
  new vm.Script('handleDeleteOnError(0)').runInContext(context, {timeout: 1_000});
  assert.equal(returned, present && mode.endsWith('_hard'));
  hardCases.push({mode, present, returned});
}
verify();
assert.equal(sequences.length, 12); assert.equal(cases.length, 32);
if (option) console.log(JSON.stringify({sequences, cases, hardCases}));
else console.log('Word retirement source passed: 12 sequences / 60 row transitions with controlled pre/post-animation deletion; 32 complete before-delete module cases; 8 complete hard-recovery function cases; owned DOM/input/animation/navigation boundaries, no browser/mixed fonts/overlap/code-unindent claim');
