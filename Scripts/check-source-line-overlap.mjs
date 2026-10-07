// QA only: actual pinned Anime.js engine/composition and complete source
// promiseAnimate/lineJump. The clock, word boxes and DOM are controlled.
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
const start = source.indexOf('function removeTestElements(');
const end = source.indexOf('\nexport function setJoiningClass(', start);
assert.ok(start >= 0 && end > start);
const code = stripTypeScriptTypes(source.slice(start, end), {mode: 'transform'});
const dom = fs.readFileSync(path.join(root, 'frontend/src/ts/utils/dom.ts'), 'utf8');
const promiseStart = dom.indexOf('  async promiseAnimate(');
const promiseEnd = dom.indexOf('\n  /**', promiseStart);
assert.ok(promiseStart >= 0 && promiseEnd > promiseStart);
const promiseCode = stripTypeScriptTypes('class Adapter {\n' + dom.slice(promiseStart, promiseEnd) + '\n}',
  {mode: 'transform'});
const fixtures = [];
for (const spacing of [0, 25, 75]) for (const jumps of [2, 3])
for (const varyingHeight of [false, true]) {
  let clock = 10_000;
  class ControlledDate extends Date { static now() { return clock; } }
  const context = vm.createContext({Date: ControlledDate, console,
    setImmediate() { throw new Error('Unexpected automatic engine loop'); }, clearImmediate() {}});
  const anime = new vm.SourceTextModule(bundle, {context});
  await anime.link(id => { throw new Error('Unexpected bundle import: ' + id); });
  await anime.evaluate();
  context.anime = anime.namespace;
  new vm.Script(`
    anime.engine.useDefaultMainLoop = false;
    anime.engine.fps = 1000;
    anime.engine.defaults.frameRate = 1000;
    const animations = [];
    const resolutions = [];
    const caret = [];
    const native = {marginTop: 0};
    let active = 2, height = 45;
    function animejsAnimate(target, options) {
      const animation = anime.animate(target, options);
      animations.push(animation); return animation;
    }
    ${promiseCode}
    const wrapper = new Adapter(); wrapper.native = native;
    const words = Array.from({length: 8}, (_, index) => ({
      index, native: {isConnected: true}, hasClass: name => name === 'word',
      getOffsetTop() { return Math.round((index - first()) * 45 + native.marginTop); },
      getOuterHeight: () => height, getOffsetHeight: () => height - 12,
      remove() { this.native.isConnected = false; },
    }));
    function connected() { return words.filter(word => word.native.isConnected); }
    function first() { return connected()[0]?.index ?? 8; }
    const wordsEl = {getChildren: connected,
      setStyle: options => { native.marginTop = Number(options.marginTop); },
      promiseAnimate: options => wrapper.promiseAnimate(options)};
    const getActiveWordElement = () => words[active];
    const Config = {smoothLineScroll: true};
    let currentTestLine = 1, lineTransition = false, activeWordTop = 45, activeWordHeight = 33;
    const Caret = {caret: {handleLineJump: options => caret.push({...options})}};
    const PaceCaret = {caret: {handleLineJump() {}}};
    function updateWordsWrapperHeight() {}
    ${code}
  `).runInContext(context);
  async function tickTo(time) {
    while (clock < 10_000 + time) { clock++; anime.namespace.engine.update(); }
    for (let tick = 0; tick < 8; tick++) await Promise.resolve();
  }
  const samples = [];
  for (let index = 0; index < jumps; index++) {
    await tickTo(index * spacing);
    const height = varyingHeight ? [45, 25, 59][index] : 45;
    vm.runInContext(`active = ${2 + index}; height = ${height};
      lineJump(words[${index + 1}].getOffsetTop()).then(() => resolutions.push(${index}));`, context);
    samples.push(JSON.parse(vm.runInContext(`JSON.stringify({time: ${index * spacing},
      margin: native.marginTop, first: first(), count: currentLinesJumping,
      targets: caret.map(value => value.newMarginTop), resolved: [...resolutions], height})`, context)));
  }
  const motionSamples = [];
  const finalStart = (jumps - 1) * spacing;
  const from = samples.at(-1).margin;
  const target = samples.at(-1).targets.at(-1);
  for (const elapsed of [1, 10, 25, 50, 75, 100, 112, 113, 114]) {
    await tickTo(finalStart + elapsed);
    const sample = JSON.parse(vm.runInContext(`JSON.stringify({elapsed: ${elapsed},
      margin: native.marginTop, first: first(), resolved: [...resolutions],
      animationTime: animations.at(-1).currentTime})`, context));
    if (!sample.resolved.length) {
      const fraction = Math.min(1, sample.animationTime / 125);
      assert.ok(Math.abs(sample.margin - (from + (target - from) * fraction * (2 - fraction))) < 1e-6,
        JSON.stringify({spacing, jumps, varyingHeight, from, target, sample}));
      if (elapsed >= 10) assert.equal(sample.animationTime, elapsed + 12);
      assert.equal(sample.first, 0);
    }
    motionSamples.push(sample);
  }
  await tickTo((jumps - 1) * spacing + 126);
  samples.push(JSON.parse(vm.runInContext(`JSON.stringify({time: ${(jumps - 1) * spacing + 126},
    margin: native.marginTop, first: first(), count: currentLinesJumping,
    targets: caret.map(value => value.newMarginTop), resolved: [...resolutions],
    canceled: animations.map(animation => !!animation._cancelled),
    completed: animations.map(animation => animation.completed), currentTestLine, lineTransition})`, context)));
  const last = samples.at(-1);
  assert.deepEqual(last.targets, Array.from({length: jumps}, (_, index) =>
    -(varyingHeight ? [45, 25, 59][index] : 45) * (index + 1)));
  assert.deepEqual(last.resolved, [jumps - 1], 'Only the newest animation promise resolves');
  assert.deepEqual(last.completed, Array.from({length: jumps}, (_, index) => index === jumps - 1));
  assert.equal(last.first, jumps);
  assert.equal(last.currentTestLine, 2, 'Canceled awaits do not increment the line count');
  assert.equal(last.lineTransition, false);
  assert.equal(last.count, 0);
  assert.equal(last.margin, 0);
  fixtures.push({spacing, jumps, varyingHeight, samples, motionSamples});
  vm.runInContext('for (const animation of animations) animation.cancel();', context);
}
verify();
if (option) console.log(JSON.stringify(fixtures));
else console.log('Line overlap source passed: 12 complete lineJump/promiseAnimate sequences; real Anime.js 4.2.2 engine/composition with controlled millisecond clock; newest-only promise completion, accumulated height targets and 108 live-engine samples including 12ms autoplay lead; owned object properties/DOM boxes, no browser pixel/layout or RAF ordering claim');
