// QA only. Complete pinned callbacks share real RAF, word/state modules and
// Anime.js. Geometry, classes and layout changes are explicit owned adapters.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
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
const archive = process.env.TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE;
assert.ok(archive, 'Requires pinned Anime.js 4.2.2 archive');
const integrity = 'sha512-' + createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
assert.equal(integrity, 'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
assert.ok(fs.readFileSync(path.join(root, 'pnpm-lock.yaml'), 'utf8').includes(integrity));
const bundle = execFileSync('tar', ['-xOf', archive, 'package/dist/bundles/anime.esm.js'],
  {encoding: 'utf8', maxBuffer: 2 ** 21});
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/test/test-ui.ts'), 'utf8');
function section(text, from, until) {
  const start = text.indexOf(from), end = text.indexOf(until, start);
  assert.ok(start >= 0 && end > start);
  return stripTypeScriptTypes(text.slice(start, end), {mode: 'transform'}).replace(/^export /gm, '');
}
const callbacks = section(source, 'export function updateActiveElement(', '\nfunction createHintsHtml(')
  + section(source, 'export let pendingWordData:', '// this is needed in tape mode')
  + section(source, 'function removeTestElements(', '\nexport function setJoiningClass(');
const dom = fs.readFileSync(path.join(root, 'frontend/src/ts/utils/dom.ts'), 'utf8');
const promiseStart = dom.indexOf('  async promiseAnimate(');
const promiseEnd = dom.indexOf('\n  /**', promiseStart);
assert.ok(promiseStart >= 0 && promiseEnd > promiseStart);
const adapter = stripTypeScriptTypes('class Adapter {\n' + dom.slice(promiseStart, promiseEnd) + '\n}', {mode: 'transform'});
const fixtures = [];
for (const smooth of [false, true]) for (const scenario of ['multirow', 'advance', 'first', 'nextActive']) {
  const advancesFirst = scenario === 'advance' || scenario === 'nextActive';
  let clock = 10_000, active = advancesFirst ? 1 : 2, nextFrame = 0;
  const frames = new Map(), events = [], native = {marginTop: 0};
  let renderStage = 0;
  const rawTops = [0, 45, 45, 90, 135, 180];
  const words = rawTops.map((_, index) => ({index, native: {isConnected: true}, classes: new Set(),
    hasClass(name) { return this.classes.has(name) || name === 'word'; },
    addClass(name) { this.classes.add(name); }, removeClass(name) { this.classes.delete(name); },
    getOffsetTop() { return Math.round(rawTops[index] - first() * 45 + native.marginTop); },
    getOffsetHeight: () => 33, getOuterHeight: () => 45,
    remove() { events.push({type: 'remove', index, baseline: context.activeWordTop}); this.native.isConnected = false; },
    setHtml() {
      if (renderStage === 1) {
        const delta = scenario === 'advance' ? 45 : 90;
        for (let i = active; i < rawTops.length; i++) rawTops[i] += delta;
      }
      events.push({type: 'render', index});
    },
    qsa: () => [], appendHtml() {},
  }));
  function connected() { return words.filter(word => word.native.isConnected); }
  function first() { return connected()[0]?.index ?? words.length; }
  class ControlledDate extends Date { static now() { return clock; } }
  const context = vm.createContext({Date: ControlledDate, console: {log() {}, error() {}},
    requestAnimationFrame: callback => { frames.set(++nextFrame, callback); return nextFrame; },
    cancelAnimationFrame: id => frames.delete(id),
    // Anime's browserless main loop is disabled below, but its RAF symbol
    // still binds to this same controlled scheduling boundary.
    setImmediate() { throw new Error('Unexpected automatic engine loop'); }, clearImmediate() {},
  });
  const modules = new Map();
  function moduleFor(id) {
    if (modules.has(id)) return modules.get(id);
    let module;
    const bindings = id === 'states/test' ? {getActiveWordIndex: () => active}
      : id === '@monkeytype/schemas/languages' ? {Language: undefined} : null;
    if (bindings) module = new vm.SyntheticModule(Object.keys(bindings), function() {
      for (const [name, value] of Object.entries(bindings)) this.setExport(name, value);
    }, {identifier: id, context});
    else {
      assert.ok(['utils/strings', 'utils/debounced-animation-frame',
        'legacy-states/slow-timer', 'test/test-words'].includes(id));
      module = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(
        path.join(root, 'frontend/src/ts', id + '.ts'), 'utf8'), {mode: 'transform'}), {identifier: id, context});
    }
    modules.set(id, module); return module;
  }
  for (const id of ['utils/strings', 'utils/debounced-animation-frame', 'legacy-states/slow-timer', 'test/test-words']) {
    const module = moduleFor(id);
    await module.link((specifier, parent) => moduleFor(specifier.startsWith('.')
      ? path.posix.normalize(path.posix.join(path.posix.dirname(parent.identifier), specifier)) : specifier));
    await module.evaluate();
  }
  const anime = new vm.SourceTextModule(bundle, {context});
  await anime.link(id => { throw new Error('Unexpected bundle import: ' + id); });
  await anime.evaluate();
  anime.namespace.engine.useDefaultMainLoop = false;
  anime.namespace.engine.fps = 1000;
  anime.namespace.engine.defaults.frameRate = 1000;
  const SlowTimer = modules.get('legacy-states/slow-timer').namespace;
  SlowTimer.set();
  const TestWords = modules.get('test/test-words').namespace;
  for (let i = 0; i < words.length; i++) TestWords.words.push('aa ', 0);
  Object.assign(context, {Config: {mode: 'words', smoothLineScroll: smooth, showAllLines: false,
    tapeMode: 'off', indicateTypos: 'off', compositionDisplay: 'replace'},
    activeWordTop: 0, activeWordHeight: 33, wordTopBeforeLineJump: 0,
    currentTestLine: scenario === 'first' ? 0 : 1, lineTransition: false,
    SlowTimer, TestWords, Strings: modules.get('utils/strings').namespace,
    requestDebouncedAnimationFrame: modules.get('utils/debounced-animation-frame').namespace.requestDebouncedAnimationFrame,
    getActiveWordElement: () => words[active], getWordElement: index => words[index],
    Joining: {set() {}}, findSingleActiveFunboxWithFunction: () => null,
    Caret: {caret: {handleLineJump: value => events.push({type: 'jump', ...value})}},
    PaceCaret: {caret: {handleLineJump() {}}}, updateWordsWrapperHeight() {},
    updateWordsInputPosition: () => events.push({type: 'inputPosition'}),
    animejsAnimate: (target, options) => anime.namespace.animate(target, options),
  });
  vm.runInContext(`${adapter}; globalThis.wrapper = new Adapter();`, context);
  context.wrapper.native = native;
  context.wordsEl = {getChildren: connected, qs: () => connected().find(word => word.classes.has('active')) ?? null,
    setStyle: value => { events.push({type: 'resetMargin', baseline: context.activeWordTop}); native.marginTop = Number(value.marginTop); },
    promiseAnimate: value => context.wrapper.promiseAnimate(value)};
  vm.runInContext(callbacks, context);
  async function drain() { for (let i = 0; i < 12; i++) await Promise.resolve(); }
  async function flush() {
    for (const [id, callback] of [...frames]) { frames.delete(id); callback(); }
    await drain();
  }
  async function finish() {
    for (let i = 0; i < 140; i++) { clock++; anime.namespace.engine.update(); await drain(); }
  }
  function snapshot() { return {first: first(), top: words[active].getOffsetTop(),
    baseline: context.activeWordTop, margin: native.marginTop,
    line: context.currentTestLine, jumps: events.filter(event => event.type === 'jump').length}; }
  context.updateActiveElement({initial: true}); await flush();
  if (advancesFirst) { active = 3; context.updateActiveElement({direction: 'forward'}); }
  else { renderStage = 1; await context.updateWordLetters({wordIndex: active, input: 'ax', compositionData: ''}); }
  await flush(); await finish();
  const afterFirst = snapshot();
  renderStage = scenario === 'advance' ? 1 : 2;
  if (scenario === 'nextActive') {
    active = 4;
    context.updateActiveElement({direction: 'forward'});
  } else {
    await context.updateWordLetters({wordIndex: active, input: 'axy', compositionData: ''});
    await context.updateWordLetters({wordIndex: active, input: 'axyz', compositionData: ''});
    assert.equal(vm.runInContext(`pendingWordData.get(${active})`, context), 'axyz');
  }
  assert.equal(frames.size, 1);
  await flush(); await finish();
  const afterFollowup = snapshot();
  assert.equal(afterFirst.first, scenario === 'first' ? 0 : 1);
  if (scenario === 'multirow') {
    assert.equal(afterFirst.top, 90);
    assert.equal(afterFirst.baseline, smooth ? 90 : 45);
    assert.equal(afterFollowup.first, smooth ? 1 : 2);
  } else if (scenario === 'advance') {
    assert.equal(afterFirst.top, 45);
    assert.equal(afterFirst.baseline, smooth ? 45 : 90);
    assert.equal(afterFollowup.first, smooth ? 3 : 1);
  } else if (scenario === 'nextActive') {
    assert.equal(afterFirst.top, 45);
    assert.equal(afterFirst.baseline, smooth ? 45 : 90);
    assert.equal(afterFollowup.first, 3);
  } else {
    assert.equal(afterFirst.baseline, 45);
    assert.equal(afterFirst.jumps, 0);
    assert.equal(afterFollowup.first, 1);
  }
  assert.equal(afterFirst.margin, 0); assert.equal(afterFollowup.margin, 0);
  const removes = events.filter(event => event.type === 'remove');
  if (scenario !== 'first') assert.equal(removes[0].baseline, afterFirst.baseline);
  fixtures.push({scenario, smooth, afterFirst, afterFollowup, events});
}
verify();
if (option) console.log(JSON.stringify(fixtures));
else console.log('Prefix baseline source passed: 8 composed complete active/word/lineJump callbacks with real shared RAF, SlowTimer, words and Anime.js 4.2.2; immediate retained anchor versus smooth pre-removal anchor, first jump, subsequent same-word and active-word decisions; owned DOM/layout, no browser pixel or arbitrary RAF interleaving equivalence claim');
