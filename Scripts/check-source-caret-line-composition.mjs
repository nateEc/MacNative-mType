// QA only: complete pinned Caret, main/pace controllers, RAF and word modules
// plus complete word-change/lineJump callbacks and real locked Anime.js.
// Clock, frame cadence, CSS defaults, DOM boxes and service boundaries are owned.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const [argument, option] = process.argv.slice(2);
assert.ok(argument && (!option || ['--emit-fixtures', '--emit-sparse-fixtures'].includes(option)));
const frameIntervals = option === '--emit-sparse-fixtures' ? [16, 33, 100] : [1];
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
function section(from, until) {
  const start = source.indexOf(from), end = source.indexOf(until, start);
  assert.ok(start >= 0 && end > start);
  return stripTypeScriptTypes(source.slice(start, end), {mode: 'transform'}).replace(/^export /gm, '');
}
const callbacks = section('export function updateActiveElement(', '\nfunction createHintsHtml(')
  + section('function removeTestElements(', '\nexport function setJoiningClass(')
  + section('export async function afterTestWordChange(', '\nexport function onTestStart(');
const dom = fs.readFileSync(path.join(root, 'frontend/src/ts/utils/dom.ts'), 'utf8');
const promiseStart = dom.indexOf('  async promiseAnimate('), promiseEnd = dom.indexOf('\n  /**', promiseStart);
assert.ok(promiseStart >= 0 && promiseEnd > promiseStart);
const adapter = stripTypeScriptTypes('class Adapter {\n' + dom.slice(promiseStart, promiseEnd) + '\n}', {mode: 'transform'});
const fixtures = [];
for (const frameInterval of frameIntervals)
for (const smooth of [false, true]) for (const motion of ['off', 'slow', 'medium', 'fast'])
for (const style of ['default', 'block', 'underline']) for (const overlap of [false, true]) {
  let clock = 10_000, active = 1, input = '', frameID = 0, timeoutID = 0;
  const frames = new Map(), timeouts = new Map(), animations = [], writes = [], trace = [];
  const Config = {mode: 'words', smoothCaret: motion, smoothLineScroll: smooth,
    caretStyle: style, paceCaretStyle: style, paceCaret: 'custom', paceCaretCustomSpeed: 300,
    tapeMode: 'off', tapeMargin: 50, blindMode: false, hideExtraLetters: false,
    showAllLines: false, funbox: [], keymapMode: 'off'};
  class ControlledDate extends Date { static now() { return clock; } }
  const context = vm.createContext({Date: ControlledDate, console: {log() {}, error() {}},
    performance: {now: () => clock - 10_000},
    requestAnimationFrame: callback => { frames.set(++frameID, callback); return frameID; },
    cancelAnimationFrame: id => frames.delete(id),
    setTimeout: (callback, delay) => { timeouts.set(++timeoutID, {at: clock + delay, callback}); return timeoutID; },
    clearTimeout: id => timeouts.delete(id),
    setImmediate() { throw new Error('Unexpected automatic engine loop'); }, clearImmediate() {},
  });
  const anime = new vm.SourceTextModule(bundle, {context});
  await anime.link(id => { throw new Error('Unexpected bundle import: ' + id); });
  await anime.evaluate();
  anime.namespace.engine.useDefaultMainLoop = false;
  anime.namespace.engine.fps = 1000;
  anime.namespace.engine.defaults.frameRate = 1000;
  let inEngineUpdate = false, engineRendered = false;
  const requestTick = anime.namespace.engine.requestTick.bind(anime.namespace.engine);
  anime.namespace.engine.requestTick = time => {
    const result = requestTick(time);
    if (inEngineUpdate) engineRendered = !!result;
    return result;
  };
  class Element {
    constructor(id) {
      this.native = {id, left: 0, top: 0, marginTop: 0, marginLeft: 0, width: 2, isConnected: true};
      this.classes = new Set();
    }
    addClass(value) { for (const name of Array.isArray(value) ? value : [value]) this.classes.add(name); }
    removeClass(value) { for (const name of Array.isArray(value) ? value : [value]) this.classes.delete(name); }
    hasClass(value) { return this.classes.has(value); }
    show() { this.removeClass('hidden'); }
    hide() { this.addClass('hidden'); }
    getOffsetWidth() { return this.native.width; }
    getOffsetHeight() { return this.hasClass('underline') ? 2 : 33; }
    getStyle() { return Object.fromEntries(['left', 'top', 'marginTop', 'marginLeft', 'width'].map(key => [key, `${this.native[key]}px`])); }
    setStyle(value) {
      writes.push({time: clock - 10_000, id: this.native.id, ...value});
      for (const [key, item] of Object.entries(value)) {
        if (['left', 'top', 'marginTop', 'marginLeft', 'width'].includes(key)) {
          this.native[key] = item === '' ? key === 'width' ? 2 : 0 : parseFloat(item);
        }
      }
    }
    animate(options) {
      const channel = options.marginTop !== undefined ? 'margin' : 'position';
      const animation = anime.namespace.animate(this.native, options);
      animations.push({id: this.native.id, channel, time: clock - 10_000,
        duration: options.duration, ease: options.ease ?? 'out(2)', animation});
      return animation;
    }
    remove() { this.native.isConnected = false; }
  }
  const wordsEl = new Element('words'), mainElement = new Element('caret'), paceElement = new Element('paceCaret');
  const wrapper = {getOffsetWidth: () => 420};
  const words = Array.from({length: 12}, (_, index) => {
    const word = new Element('word' + index); word.index = index; word.addClass('word');
    if (index === 1) word.addClass('active');
    word.getOffsetTop = () => Math.round((index - first()) * 45 + wordsEl.native.marginTop);
    word.getOffsetLeft = () => 0;
    word.getOffsetWidth = () => 24;
    word.getOffsetHeight = () => 33;
    word.getOuterHeight = () => 45;
    word.getAttribute = name => name === 'data-wordindex' ? String(index) : null;
    const letters = Array.from({length: 2}, (_, letter) => ({native: {textContent: 'a'},
      getOffsetTop: () => 0, getOffsetLeft: () => letter * 12, getOffsetWidth: () => 12,
      getOffsetHeight: () => 33, addClass() {}}));
    word.qsa = selector => { assert.equal(selector, 'letter'); return letters; };
    return word;
  });
  function connected() { return words.filter(word => word.native.isConnected); }
  function first() { return connected()[0]?.index ?? words.length; }
  wordsEl.getChildren = connected;
  wordsEl.qs = selector => {
    if (selector === '.active') return connected().find(word => word.hasClass('active')) ?? null;
    const match = /^\.word\[data-wordindex="(\d+)"\]$/.exec(selector);
    assert.ok(match, selector); return connected().find(word => word.index === Number(match[1])) ?? null;
  };
  const state = {getActiveWordIndex: () => active, isDirectionReversed: () => false,
    isLanguageRightToLeft: () => false, getCurrentQuote: () => null,
    getResultVisible: () => false, isPaceRepeat: () => false, isTestActive: () => true, setPaceCaretWpm() {}};
  const adapters = {
    'config/store': {Config}, 'events/config': {configEvent: {subscribe() {}}},
    'states/test': state, 'test/events/data': {getCurrentInput: () => input},
    'legacy-states/composition': {getData: () => ''},
    'utils/misc': {getTotalInlineMargin: () => 12, getMode2: () => 0},
    'utils/dom': {ElementWithUtils: Element, qsr: selector => {
      const element = {'#words': wordsEl, '#wordsWrapper': wrapper, '#caret': mainElement, '#paceCaret': paceElement}[selector];
      assert.ok(element, selector); return element;
    }},
    'db': {getLocalPB: () => null}, 'collections/tags': {getActiveTagsPB: () => 0},
    'test/funbox/list': {getActiveFunboxes: () => []},
    'collections/results': {getUserAverage10Once: async () => ({wpm: 0}), getUserDailyBestOnce: async () => ({wpm: 0})},
    '@monkeytype/schemas/languages': {Language: undefined},
    '@monkeytype/schemas/configs': {CaretStyle: undefined},
    'animejs': {EasingParam: undefined, JSAnimation: undefined},
  };
  const modules = new Map();
  function moduleFor(id) {
    if (modules.has(id)) return modules.get(id);
    let module;
    if (adapters[id]) {
      const bindings = adapters[id];
      module = new vm.SyntheticModule(Object.keys(bindings), function() {
        for (const [key, value] of Object.entries(bindings)) this.setExport(key, value);
      }, {context, identifier: id});
    } else {
      assert.ok(['elements/caret', 'test/caret', 'test/pace-caret', 'test/test-words',
        'utils/debounced-animation-frame', 'utils/strings'].includes(id), id);
      module = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(
        path.join(root, 'frontend/src/ts', id + '.ts'), 'utf8'), {mode: 'transform'}), {context, identifier: id});
    }
    modules.set(id, module); return module;
  }
  const resolve = (specifier, parent) => moduleFor(specifier.startsWith('.')
    ? path.posix.normalize(path.posix.join(path.posix.dirname(parent.identifier), specifier)) : specifier);
  for (const id of ['test/caret', 'test/pace-caret']) {
    const module = moduleFor(id); await module.link(resolve); await module.evaluate();
  }
  const Caret = modules.get('test/caret').namespace, PaceCaret = modules.get('test/pace-caret').namespace;
  // Observe complete source entry points without substituting their behavior.
  // Geometry is captured before source margin folding, not reconstructed from
  // the rendered result that the native replay is supposed to verify.
  for (const [caret, element] of [[Caret.caret, mainElement], [PaceCaret.caret, paceElement]]) {
    let target;
    const geometry = caret.getTargetPositionAndWidth.bind(caret);
    caret.getTargetPositionAndWidth = options => { target = geometry(options); return target; };
    for (const method of ['setPosition', 'animatePosition']) {
      const original = caret[method].bind(caret);
      caret[method] = options => {
        assert.ok(target, 'Position must follow actual source geometry');
        trace.push({type: 'position', id: element.native.id, time: clock - 10_000,
          left: target.left, top: target.top,
          width: caret.isFullWidth() ? target.width : element.native.width,
          height: element.getOffsetHeight(),
          duration: method === 'setPosition' ? 0 : options.duration ?? {off: 0, slow: 150, medium: 100, fast: 85}[motion],
          linear: options.easing === 'linear'});
        return original(options);
      };
    }
    const lineJump = caret.handleLineJump.bind(caret);
    caret.handleLineJump = options => {
      trace.push({type: 'margin', id: element.native.id, time: clock - 10_000,
        margin: options.newMarginTop, duration: options.duration});
      return lineJump(options);
    };
  }
  const TestWords = modules.get('test/test-words').namespace;
  for (let i = 0; i < words.length; i++) TestWords.words.push('aa ', 0);
  Object.assign(context, {Config, Caret, PaceCaret, currentTestLine: 1,
    activeWordTop: 45, activeWordHeight: 33, lineTransition: false, wordsEl,
    getActiveWordElement: () => words[active], getActiveWordIndex: () => active,
    getCurrentInput: () => input, Joining: {set() {}}, updateWordsWrapperHeight() {}, updateWordsInputPosition() {},
    CustomText: {getLimitMode: () => 'words', getLimitValue: () => 12},
    Numbers: {isSafeNumber: value => Number.isFinite(value)},
    requestDebouncedAnimationFrame: modules.get('utils/debounced-animation-frame').namespace.requestDebouncedAnimationFrame,
    animejsAnimate: (target, options) => {
      assert.equal(target, wordsEl.native);
      return wordsEl.animate(options);
    },
  });
  vm.runInContext(`${adapter}; globalThis.promiseAdapter = new Adapter();`, context);
  context.promiseAdapter.native = wordsEl.native;
  wordsEl.promiseAnimate = options => context.promiseAdapter.promiseAnimate(options);
  vm.runInContext(callbacks, context);
  async function drain() { for (let i = 0; i < 12; i++) await Promise.resolve(); }
  async function flush() {
    for (const [id, callback] of [...frames]) { frames.delete(id); callback(); }
    await drain();
  }
  async function tickTo(time) {
    while (clock < 10_000 + time) {
      clock++;
      inEngineUpdate = true; engineRendered = false;
      if ((clock - 10_000) % frameInterval === 0) anime.namespace.engine.update();
      inEngineUpdate = false;
      trace.push({type: 'frame', time: clock - 10_000, rendered: engineRendered});
      await drain();
      for (const [id, timeout] of [...timeouts]) if (timeout.at <= clock) {
        timeouts.delete(id); timeout.callback(); await drain();
      }
      // Controlled 1ms RAF cadence. Real debounce cancellation/key ownership,
      // not a browser display-rate or arbitrary callback-order claim.
      await flush();
      trace.push({type: 'sample', ...snapshot(clock - 10_000)});
    }
  }
  function marker(element, caret) {
    const record = channel => animations.filter(item => item.id === element.native.id && item.channel === channel).at(-1);
    return {left: element.native.left, top: element.native.top, width: element.native.width,
      margin: element.native.marginTop, visibleTop: element.native.top + element.native.marginTop,
      ready: caret.readyToResetMarginTop,
      positionTime: record('position')?.animation.currentTime ?? null,
      marginTime: record('margin')?.animation.currentTime ?? null};
  }
  function snapshot(time) { return {time, first: first(), wordMargin: wordsEl.native.marginTop,
    activeTop: words[active].getOffsetTop(), main: marker(mainElement, Caret.caret),
    pace: marker(paceElement, PaceCaret.caret), lineTransition: context.lineTransition}; }
  Caret.updatePosition(true); await PaceCaret.init(); PaceCaret.start(); await flush();
  active = 2; await context.afterTestWordChange('forward'); await flush();
  const samples = [snapshot(0)];
  trace.push({type: 'sample', ...samples[0]});
  if (!smooth) {
    assert.equal(samples[0].main.margin, 0);
    assert.equal(samples[0].main.ready, false);
    assert.equal(samples[0].pace.margin, -45);
    assert.equal(samples[0].pace.ready, true);
  }
  for (const time of [10, 25, 40, 50, 75, 100, 112, 113, 125, 150, 153, 175, 199]) {
    await tickTo(time);
    if (time === 40 && overlap) {
      active = 3; await context.afterTestWordChange('forward'); await flush();
      trace.push({type: 'sample', ...snapshot(time)});
    }
    samples.push(snapshot(time));
  }
  const beforeRefresh = snapshot(199);
  input = 'a'; Caret.updatePosition(); await flush();
  const afterRefresh = snapshot(199);
  trace.push({type: 'sample', ...afterRefresh});
  await tickTo(400);
  const settled = snapshot(400);
  assert.equal(settled.first, overlap ? 2 : 1);
  assert.equal(settled.wordMargin, 0);
  assert.equal(settled.lineTransition, false);
  // With sparse rendering, the 199ms input can precede margin completion.
  // Keep the original 1ms contract; sparse traces retain the actual ready
  // margin until another source request instead of inventing a final fold.
  const delayedFold = smooth && frameInterval === 100;
  assert.equal(settled.main.margin, delayedFold ? overlap ? -90 : -45 : 0);
  assert.equal(settled.main.ready, delayedFold);
  if (frameInterval === 1) {
    assert.equal(settled.main.visibleTop, 45 + (style === 'underline' ? 33 : 0));
  }
  assert.equal(settled.main.left, style === 'default' ? 11 : 12);
  assert.equal(beforeRefresh.main.ready, smooth && !delayedFold);
  if (delayedFold) {
    assert.equal(afterRefresh.main.margin, beforeRefresh.main.margin);
    assert.equal(afterRefresh.main.ready, false);
  }
  if (smooth && beforeRefresh.main.ready) {
    assert.equal(beforeRefresh.main.margin, overlap ? -90 : -45);
    assert.equal(afterRefresh.main.margin, 0);
    const fold = writes.findLast(item => item.id === 'caret' && item.time === 199
      && item.marginTop === '0px' && item.top !== undefined);
    assert.ok(fold);
    assert.ok(Math.abs(parseFloat(fold.top) - beforeRefresh.main.visibleTop) < 1e-6,
      'The folding write preserves the display coordinate, before goTo corrects its target');
  } else if (!smooth) {
    assert.equal(beforeRefresh.main.margin, 0, 'Main duration-zero line jump returns without a margin animation');
  }
  const mainMargins = animations.filter(item => item.id === 'caret' && item.channel === 'margin');
  const paceMargins = animations.filter(item => item.id === 'paceCaret' && item.channel === 'margin');
  assert.equal(mainMargins.length, smooth ? overlap ? 2 : 1 : 0);
  assert.equal(paceMargins.length, smooth ? overlap ? 2 : 1 : 0);
  if (smooth && overlap) {
    assert.equal(mainMargins[0].animation.completed, false);
    assert.equal(paceMargins[0].animation.completed, false);
    assert.equal(mainMargins[1].animation.completed, true);
    assert.equal(paceMargins[1].animation.completed, true);
  }
  const positions = animations.filter(item => item.id === 'caret' && item.channel === 'position');
  const duration = {off: 0, slow: 150, medium: 100, fast: 85}[motion];
  assert.equal(positions.length, motion === 'off' ? 0 : overlap ? 3 : 2);
  assert.ok(positions.every(item => item.duration === duration && item.ease === 'inOut(1.25)'));
  assert.ok(animations.filter(item => item.id === 'paceCaret' && item.channel === 'position')
    .every(item => item.ease === 'linear'));
  const sample = samples.find(item => item.time === 25);
  if (duration) {
    const curve = anime.namespace.eases.inOut(1.25)(sample.main.positionTime / duration);
    const start = 45 + (style === 'underline' ? 33 : 0);
    const target = (smooth ? 90 : 45) + (style === 'underline' ? 33 : 0);
    assert.ok(Math.abs(sample.main.top - (start + (target - start) * curve)) < 1e-6);
  }
  assert.equal(trace.filter(item => item.type === 'sample').length, overlap ? 403 : 402);
  fixtures.push({frameInterval, smooth, motion, style, overlap, samples, beforeRefresh, afterRefresh, settled, trace,
    resets: writes.filter(item => item.marginTop === '0px'),
    animations: animations.map(({animation, ...item}) => ({...item, completed: animation.completed}))});
  Caret.caret.stopAllAnimations(); PaceCaret.caret.stopAllAnimations(); PaceCaret.reset();
  for (const {animation} of animations) animation.cancel();
}
verify();
if (option) console.log(JSON.stringify(fixtures));
else console.log('Caret line composition source passed: 48 complete Caret/controller/pace/RAF/words and after-word-change/lineJump sequences, real locked Anime.js; separate position and margin channels, off/slow/medium/fast, three styles, immediate/smooth/overlap, delayed margin folding and source position easing; owned 1ms frame/clock/DOM/CSS/service boundaries, not browser pixels, native parity or arbitrary scheduling equivalence');
