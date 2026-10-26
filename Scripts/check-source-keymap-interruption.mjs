// Actual Solid core/store, pinned keymap state, Key logic and Anime effects.
// Scalar theme, element, config signal and external clock/driver are adapters.
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
const lock = fs.readFileSync(path.join(root, 'pnpm-lock.yaml'), 'utf8');
function unpack(archive, file) {
  return execFileSync('tar', ['-xOf', archive, file], {encoding: 'utf8', maxBuffer: 2 ** 21});
}
function verifiedArchive(key, integrity) {
  const archive = process.env[key]; assert.ok(archive, key);
  assert.equal('sha512-' + createHash('sha512').update(fs.readFileSync(archive)).digest('base64'), integrity);
  assert.ok(lock.includes(integrity)); return archive;
}
const animeArchive = verifiedArchive('TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE',
  'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
const solidArchive = verifiedArchive('TYPEBAR_SOLID_QA_ARCHIVE',
  'sha512-6hJeJMOcEX8ktqjpDoJZEmld3ijvcvWBDtiXBm7f4332SiFN66QeAQI1REQshvyUoISsSeJ4PHDauKYbwao9JQ==');
const uri = code => 'data:text/javascript;base64,' + Buffer.from(code).toString('base64');
const solidCode = unpack(solidArchive, 'package/dist/solid.js');
const storeCode = unpack(solidArchive, 'package/store/dist/store.js');
const bundle = unpack(animeArchive, 'package/dist/bundles/anime.esm.js');
const read = file => fs.readFileSync(path.join(root, 'frontend/src/ts', file), 'utf8');
function part(text, from, to) {
  const start = text.indexOf(from), end = text.indexOf(to, start);
  assert.ok(start >= 0 && end > start, from); return text.slice(start, end);
}
const ts = code => stripTypeScriptTypes(code.replace(/^export \{[^}]+\};/gm, ''), {mode: 'transform'});
const keymap = read('components/pages/test/Keymap.tsx'), wrapper = read('components/common/anime/Anime.tsx');
const keyCode = ts(part(keymap, 'const isSteno = () =>', '\n  return (\n    <Anime'));
const applyCode = ts(part(wrapper, '  const applyAnimation =', '\n  const applyInitialState ='));
const effectCode = ts(part(wrapper, '  // Handle initial state and mounting animation', '\n  const setElementRef'));
const stateCode = ts(part(read('states/test.ts'), 'const [getKeymapHighlightKey,', 'const getInputLayout ='));
const selectorCode = part(keymap, '                  const flashEntry = () =>', '\n                  return (');
const paramsCode = '{' + part(keymap, '      animation={{', '\n      }}').slice('      animation={{'.length) + '\n}';
assert.ok(keymap.includes('respectReducedMotion={false}'));
const fixtures = [];
for (const rate of [15, 60, 1000]) for (const scenario of ['repeat', 'static', 'fade-react', 'fade-next', 'unmount']) {
  let time = 10000;
  const originalNow = Date.now;
  let anime;
  try { Date.now = () => time; anime = await import(uri(bundle) + `#solid-${rate}-${scenario}`); }
  finally { Date.now = originalNow; }
  anime.engine.useDefaultMainLoop = false; anime.engine.fps = rate; anime.engine.defaults.frameRate = rate;
  let mode, setMode;
  const config = {get keymapMode() { return mode(); }, keymapStyle: 'staggered'};
  const element = {'--keybgcolor': 1, '--keycolor': 1, style: {height: '0px'}};
  const instances = [], completed = [], frames = [];
  let listener, dispose, nextID = 0;
  const context = vm.createContext({getConfig: config,
    keymapEvent: {useListener(fn) { listener = fn; }},
    element, currentAnimation: undefined, hasInitialized: false, presenceContext: null,
    getTheme: () => ({main: 0, subAlt: 1, bg: 0, sub: 1, error: -1}),
    props: {legends: ['a', 'A']}, key: {legends: ['a', 'A']},
    applyReducedMotion() { assert.fail('Keymap opts out of reduced motion'); },
    animejsAnimate(target, params) {
      const range = value => [value[0], value.at(-1)];
      const record = {id: nextID++, at: time - 10000, duration: params.duration,
        background: range(params['--keybgcolor']), foreground: range(params['--keycolor'])};
      instances.push(record);
      record.animation = anime.animate(target, {...params,
        onRender: () => frames.push({id: record.id, at: time - 10000,
          background: element['--keybgcolor'], foreground: element['--keycolor']}),
        onComplete: value => { completed.push({id: record.id, at: time - 10000}); params.onComplete?.(value); }});
      record.initialBackground = element['--keybgcolor']; record.initialForeground = element['--keycolor'];
      return record.animation;
    }});
  // Source literals and the store runtime share a realm, preserving deep proxy
  // and object-merge behavior rather than relying on cross-realm fallbacks.
  const coreModule = new vm.SourceTextModule(solidCode, {context, identifier: 'pinned-solid-core'});
  await coreModule.link(() => { throw new Error('Unexpected Solid core dependency'); });
  await coreModule.evaluate();
  const storeModule = new vm.SourceTextModule(storeCode, {context, identifier: 'pinned-solid-store'});
  await storeModule.link(id => { assert.equal(id, 'solid-js'); return coreModule; });
  await storeModule.evaluate();
  const solid = coreModule.namespace;
  Object.assign(context, solid, {createStore: storeModule.namespace.createStore});
  [mode, setMode] = solid.createSignal(scenario.startsWith('fade') ? 'next' : 'react');
  context.local = {respectReducedMotion: false, get animation() { return vm.runInContext('(' + paramsCode + ')', context); }};
  solid.createRoot(d => {
    dispose = d; vm.runInContext(stateCode, context);
    assert.ok(vm.runInContext('Object.getPrototypeOf(getKeymapFlashState) === Object.prototype', context));
    context.props.flashState = vm.runInContext('getKeymapFlashState', context);
    vm.runInContext(selectorCode, context); context.props.flashEntry = vm.runInContext('flashEntry', context);
    vm.runInContext(keyCode, context); vm.runInContext(applyCode, context); vm.runInContext(effectCode, context);
  });
  const state = () => JSON.parse(vm.runInContext('JSON.stringify(getKeymapFlashState)', context));
  if (scenario.startsWith('fade')) listener({mode: 'highlight', key: 'a'});
  else listener({mode: 'flash', key: 'a', correct: true});
  const checkpoints = [];
  for (time = 10001; time <= 10500; time++) {
    const elapsed = time - 10000;
    if (elapsed === 10 && scenario.startsWith('fade')) setMode('static');
    if (elapsed === 80) {
      if (scenario === 'repeat') listener({mode: 'flash', key: 'a', correct: false});
      if (scenario === 'static') setMode('static');
      if (scenario === 'fade-react') { setMode('react'); listener({mode: 'flash', key: 'a', correct: true}); }
      if (scenario === 'fade-next') { setMode('next'); listener({mode: 'highlight', key: 'a'}); }
      if (scenario === 'unmount') dispose();
    }
    anime.engine.update();
    if (state().a) {
      assert.ok(vm.runInContext('getKeymapFlashState.a[$PROXY] === getKeymapFlashState.a', context), 'Entry must retain real deep-store proxy semantics');
    }
    if ([79, 80, 237, 238, 248, 250, 318, 400].includes(elapsed)) {
      checkpoints.push({at: elapsed, state: state(), background: element['--keybgcolor'],
        fading: vm.runInContext('isFading()', context)});
    }
  }
  const positive = instances.filter(x => x.duration > 0), finished = completed.filter(x => positive.some(p => p.id === x.id));
  if (scenario === 'repeat') { assert.equal(finished.length, 1); assert.equal(positive.find(x => x.id === finished[0].id).at, 80); }
  if (scenario.startsWith('fade')) { assert.equal(positive.length, 1); assert.equal(positive[0].at, 10); assert.equal(finished.length, 1); }
  if (scenario === 'unmount') { assert.equal(finished.length, 0); assert.ok(state().a); }
  else assert.deepEqual(state(), {});
  fixtures.push({rate, scenario, instances: instances.map(({animation, ...rest}) => rest), completed, frames, checkpoints});
  dispose(); instances.forEach(({animation}) => animation.cancel()); anime.engine.pause();
}
verify();
console.log(JSON.stringify({fixtures}));
