// QA only: train the actual pinned generator on owned fixtures, never on
// reference word lists. Dormant base-wordset operations are explicit traps.
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
let samples = [0], draws = 0, wordStart = 0;
const math = Object.create(Math);
math.random = () => {
  assert.ok(draws - wordStart < 20000, 'QA entropy fixture did not terminate');
  return samples[draws++ % samples.length];
};
const context = vm.createContext({Math: math});
function module(relative) {
  return new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(path.join(root, relative), 'utf8'),
    {mode: 'transform'}), {context, identifier: relative});
}
const numbers = module('packages/util/src/numbers.ts');
const arrays = module('frontend/src/ts/utils/arrays.ts');
const wordset = module('frontend/src/ts/test/wordset.ts');
const misc = new vm.SyntheticModule(['zipfyRandomArrayIndex'], function() {
  this.setExport('zipfyRandomArrayIndex', () => { throw Error('Pseudolang must ignore base Zipf'); });
}, {context});
await wordset.link(id => {
  if (id === '../utils/misc') return misc;
  if (id === '../utils/arrays') return arrays;
  if (id === '@monkeytype/util/numbers') return numbers;
  throw Error('Unexpected pseudolang dependency: ' + id);
});
await wordset.evaluate();
context.Wordset = wordset.namespace.Wordset;
context.randomIntFromRange = numbers.namespace.randomIntFromRange;
const handlers = fs.readFileSync(path.join(root, 'frontend/src/ts/test/funbox/funbox-functions.ts'), 'utf8');
const first = handlers.indexOf('class CharDistribution {');
assert.ok(first >= 0);
vm.runInContext(stripTypeScriptTypes(handlers.slice(first).replace(/^export /gm, ''), {mode: 'transform'}), context);
const functions = context.getFunboxFunctions();
const corpora = [['ab', 'ac', 'ba'], ['1a', '2b', '3c', '0d'], ['éa', 'e\u0301b', 'éa'],
  ['😀a', '😁b', '😀c'], ['ab', 'ab', 'ac', 'ac', 'ac', 'ad'], ['ab cd', 'ef'], ['', 'a', 'b'], ['I', 'Ä', 'ΟΣ']];
const tapes = [[0], [0.5], [1 - Number.EPSILON / 2], [0, 0.99, 0.2, 0.7]];
for (let seed = 1; seed <= 16; seed++) {
  let state = seed;
  tapes.push(Array.from({length: 64}, () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 2 ** 32;
  }));
}
const fixtures = [];
for (const corpus of corpora) for (const tape of tapes) {
  const generator = await functions.pseudolang.withWords(corpus);
  assert.equal(generator.length, Infinity);
  samples = tape; draws = 0;
  const words = [];
  for (let index = 0; index < 20; index++) {
    wordStart = draws;
    words.push({word: generator.randomWord(index % 2 ? 'zipf' : 'normal'), draws: draws - wordStart});
  }
  fixtures.push({corpus, samples, words});
}
const generator = await functions.pseudolang.withWords(['aaa']);
samples = [...Array(9999).fill(0), 0.99]; draws = wordStart = 0;
const longWord = generator.randomWord('normal');
verify();
process.stdout.write(JSON.stringify({fixtures, longWord: {length: longWord.length, draws}}) + '\n');
