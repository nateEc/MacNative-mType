// QA only: execute the complete pinned generation, numeric and array modules
// under controlled entropy. This probes primitives, not the full browser RNG
// stream, wordset selection, activation or event lifecycle.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {stripTypeScriptTypes} from 'node:module';
assert.ok(process.argv[2], 'Pinned read-only reference required');
const root = path.resolve(process.argv[2]);
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
let tape = [0], draws = 0;
const math = Object.create(Math);
math.random = () => tape[draws++ % tape.length];
const context = vm.createContext({Math: math});
function module(relative) {
  return new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(path.join(root, relative), 'utf8'),
    {mode: 'transform'}), {context, identifier: relative});
}
const numbers = module('packages/util/src/numbers.ts');
const arrays = module('frontend/src/ts/utils/arrays.ts');
const generate = module('frontend/src/ts/utils/generate.ts');
const strings = new vm.SyntheticModule([], () => {}, {context});
const link = id => {
  if (id === '@monkeytype/util/numbers') return numbers;
  if (id === './arrays') return arrays;
  if (id === './strings') return strings;
  throw Error('Unexpected primitive dependency: ' + id);
};
await generate.link(link);
await generate.evaluate();
const tapes = [[0], [0.5], [1 - Number.EPSILON / 2], [0, 0.99, 0.2, 0.7]];
for (let seed = 1; seed <= 16; seed++) {
  let state = seed;
  tapes.push(Array.from({length: 32}, () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 2 ** 32;
  }));
}
const fixtures = [];
for (const [kind, name] of [['binary', 'getBinary'], ['hexadecimal', 'getHexadecimal'],
  ['gibberish', 'getGibberish'], ['ascii', 'getASCII'], ['specials', 'getSpecials']]) {
  for (const samples of tapes) {
    tape = samples; draws = 0;
    const word = generate.namespace[name]();
    fixtures.push({kind, samples, word, draws});
  }
}
verify();
process.stdout.write(JSON.stringify({fixtures}) + '\n');
