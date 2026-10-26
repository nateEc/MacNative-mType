// QA only: actual Keymap parameters, complete Anime applyAnimation and engine.
// Role scalars, element, signals and clock/driver are owned adapter boundaries.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? '');
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const archive = process.env.TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE;
assert.ok(archive);
const integrity = 'sha512-' + createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
assert.equal(integrity, 'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
assert.ok(fs.readFileSync(path.join(root, 'pnpm-lock.yaml'), 'utf8').includes(integrity));
const bundle = execFileSync('tar', ['-xOf', archive, 'package/dist/bundles/anime.esm.js'],
  {encoding: 'utf8', maxBuffer: 2 ** 21});
const keymap = fs.readFileSync(path.join(root, 'frontend/src/ts/components/pages/test/Keymap.tsx'), 'utf8');
const wrapper = fs.readFileSync(path.join(root, 'frontend/src/ts/components/common/anime/Anime.tsx'), 'utf8');
function section(text, from, to) {
  const start = text.indexOf(from), end = text.indexOf(to, start);
  assert.ok(start >= 0 && end > start);
  return text.slice(start, end);
}
const keyCode = stripTypeScriptTypes(section(keymap, 'const isSteno = () =>', '\n  return (\n    <Anime'), {mode: 'transform'});
const applyCode = stripTypeScriptTypes(section(wrapper, '  const applyAnimation =', '\n  const applyInitialState ='), {mode: 'transform'});
const paramsCode = '{' + section(keymap, '      animation={{', '\n      }}').slice('      animation={{'.length) + '\n}';
assert.ok(keymap.includes('respectReducedMotion={false}'));
const fixtures = [];
for (const rate of [15, 30, 60, 120, 1000]) for (const warmup of [0, 37, 120]) {
  for (const mode of ['react', 'static', 'nextExit']) {
    let time = 10000;
    const originalNow = Date.now;
    let anime;
    try {
      Date.now = () => time;
      anime = await import('data:text/javascript;base64,' + Buffer.from(bundle).toString('base64') +
        `#keymap-autoplay-${rate}-${warmup}-${mode}`);
    } finally { Date.now = originalNow; }
    const engine = anime.engine;
    engine.useDefaultMainLoop = false; engine.fps = rate; engine.defaults.frameRate = rate;
    for (time = 10001; time <= 10000 + warmup; time++) engine.update();
    time = 10000 + warmup;
    const config = {keymapMode: mode === 'nextExit' ? 'next' : mode, keymapStyle: 'staggered'};
    const effects = [], clears = [], frames = [], completions = [];
    const element = {'--keybgcolor': 0, '--keycolor': 0, style: {height: '0px'}};
    const context = vm.createContext({element, currentAnimation: undefined, getConfig: config,
      getKeymapHighlightKey: () => 'a', getTheme: () => ({main: 0, subAlt: 1, bg: 0, sub: 1, error: 0}),
      props: {legends: ['a', 'A'], flashEntry: () => mode === 'react' ? {tick: 1, correct: true} : undefined},
      createMemo: fn => () => fn(), createSignal: value => [() => value, next => { value = next; }],
      createEffect: fn => { effects.push(fn); fn(); }, setKeymapFlashState: (...args) => clears.push(args),
      local: {respectReducedMotion: false}, animejsAnimate: anime.animate,
      applyReducedMotion() { assert.fail('Keymap explicitly opts out of reduced motion'); }});
    vm.runInContext(keyCode, context, {timeout: 1000});
    if (mode === 'nextExit') { config.keymapMode = 'static'; effects.forEach(fn => fn()); }
    vm.runInContext(applyCode, context, {timeout: 1000});
    const params = vm.runInContext('(' + paramsCode + ')', context, {timeout: 1000});
    assert.equal(params.duration, mode === 'static' ? 0 : 250);
    const started = time, originalComplete = params.onComplete;
    params.onComplete = animation => { completions.push(time - started); originalComplete(animation); };
    params.onRender = () => frames.push({elapsed: time - started,
      progress: element['--keybgcolor'], foreground: element['--keycolor']});
    context.params = params;
    const animation = vm.runInContext('applyAnimation(params)', context, {timeout: 1000});
    const initial = element['--keybgcolor'];
    for (time = started + 1; time <= started + 400; time++) engine.update();
    assert.equal(completions.length, 1);
    assert.equal(element['--keybgcolor'], 1);
    assert.deepEqual(clears.map(x => x[0]), ['a', 'A']);
    const fading = vm.runInContext('isFading()', context);
    assert.equal(fading, false);
    fixtures.push({rate, warmup, mode, duration: params.duration, initial, frames, completedAt: completions[0]});
    animation.cancel(); engine.pause();
  }
}
verify();
console.log(JSON.stringify({fixtures}));
