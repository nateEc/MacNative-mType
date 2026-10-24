// QA only: execute the complete pinned DDR module in isolated contexts.
// A context survives multiple first-word markers, as the source module does.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';
const root = path.resolve(process.argv[2] ?? '');
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const tapes = [[0], [0.5], [1 - Number.EPSILON / 2], [0, 0.99, 0.2, 0.7]];
for (let seed = 1; seed <= 16; seed++) {
  let state = seed;
  tapes.push(Array.from({length: 64}, () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 2 ** 32;
  }));
}
const source = stripTypeScriptTypes(fs.readFileSync(path.join(root, 'frontend/src/ts/utils/ddr.ts'), 'utf8'),
  {mode: 'transform'});
const scenarios = [];
for (const samples of tapes) {
  let draws = 0;
  const math = Object.create(Math);
  math.random = () => samples[draws++ % samples.length];
  const module = new vm.SourceTextModule(source, {context: vm.createContext({Math: math})});
  await module.link(id => { throw Error('Unexpected chart dependency: ' + id); });
  await module.evaluate();
  const words = [];
  for (let index = 0; index < 40; index++) {
    const first = [0, 17, 32].includes(index);
    const before = draws;
    words.push({first, word: module.namespace.chart2Word(first), draws: draws - before});
  }
  scenarios.push({samples, words});
}
verify();
const context = vm.createContext({});
const handlers = fs.readFileSync(path.join(root, 'frontend/src/ts/test/funbox/funbox-functions.ts'), 'utf8');
const first = handlers.indexOf('const list: Partial<Record<FunboxName, FunboxFunctions>> = {');
assert.ok(first >= 0);
vm.runInContext(stripTypeScriptTypes(handlers.slice(first).replace(/^export /gm, ''), {mode: 'transform'}), context);
const keys = ['a', 's', 'w', 'd', 'j', 'k', 'i', 'l', 'ArrowLeft', 'ArrowDown', 'ArrowUp', 'ArrowRight',
  'A', 'S', 'W', 'D', 'J', 'K', 'I', 'L', 'å', '', 'Tab', 'Enter', 'Dead', 'あ'];
const emulation = keys.map(key => ({key, output: context.getFunboxFunctions().arrows.getEmulatedChar({key})}));
verify();
process.stdout.write(JSON.stringify({scenarios, emulation}) + '\n');
