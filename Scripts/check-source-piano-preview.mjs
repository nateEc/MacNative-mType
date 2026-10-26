// Read-only QA: pinned key tracking, note table, playNote and both click callers.
// AudioContext and modifier state are owned adapters; no audio or browser claim.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? '');
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/controllers/sound-controller.ts'), 'utf8');
function section(start, end) {
  const from = source.indexOf(start), to = source.indexOf(end, from);
  assert.ok(from >= 0 && to > from);
  return source.slice(from, to);
}
const code = stripTypeScriptTypes(section('let currentCode =', 'type ScaleData =') +
  section('function playNote(', 'export async function playError(') +
  section('export async function previewClick(', 'export async function previewError('),
  {mode: 'transform'}).replaceAll('export async function', 'async function');
const fixtures = [];
for (const waveform of ['sine', 'square', 'sawtooth', 'triangle']) {
  for (const initial of ['KeyZ', 'Space', 'ShiftLeft', 'CapsLock']) {
    for (const raised of [false, true]) {
      const frequencies = [], handlers = new Map();
      class AudioContext {
        currentTime = 0; destination = {};
        createOscillator() {
          const frequency = {value: 0};
          return {frequency, connect() {}, start() { frequencies.push(frequency.value); }, stop() {}};
        }
        createGain() { return {gain: {value: 0, setTargetAtTime() {}}, connect() {}}; }
      }
      const context = vm.createContext({AudioContext, Config: {soundVolume: 5, playSoundOnClick: 'owned'},
        soundsConfig: {owned: {oscillatorType: waveform}},
        document: {addEventListener(type, fn) { handlers.set(type, fn); }},
        getModifierState: () => ({shift: raised}), isCapsLockOn: () => false,
        showErrorNotification() { assert.fail('unexpected audio initialization failure'); }});
      vm.runInContext(code, context, {timeout: 1000});
      handlers.get('keydown')({code: initial});
      const play = () => vm.runInContext('playClick()', context, {timeout: 1000});
      await play(); const initialCount = frequencies.length;
      await vm.runInContext("previewClick('owned')", context, {timeout: 1000});
      await play();
      const afterPreview = frequencies.slice(initialCount);
      assert.deepEqual(afterPreview, [raised ? 523.25 : 261.63, raised ? 523.25 : 261.63]);
      handlers.get('keydown')({code: 'Space'}); await play();
      assert.equal(frequencies.length, initialCount + 2);
      handlers.get('keydown')({code: 'KeyZ'});
      handlers.get('keyup')?.({code: 'Space'}); await play();
      assert.equal(frequencies.at(-1), raised ? 261.63 : 130.81);
      fixtures.push({waveform, initial, raised, frequencies});
    }
  }
}
verify();
console.log(JSON.stringify({fixtures}));
