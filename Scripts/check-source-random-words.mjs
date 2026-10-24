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
const ip = module('frontend/src/ts/utils/ip-addresses.ts');
const strings = new vm.SyntheticModule([], () => {}, {context});
const link = id => {
  if (id === '@monkeytype/util/numbers') return numbers;
  if (id === './arrays') return arrays;
  if (id === './strings') return strings;
  throw Error('Unexpected primitive dependency: ' + id);
};
await generate.link(link);
await generate.evaluate();
await ip.link(link);
await ip.evaluate();
context.IPAddresses = ip.namespace;
// Evaluate the complete handler table, as the existing ordered-text probe
// does. Only the two IP getWord/punctuateWord handlers are invoked here;
// dormant browser dependencies are deliberately not supplied.
const handlers = fs.readFileSync(path.join(root, 'frontend/src/ts/test/funbox/funbox-functions.ts'), 'utf8');
const first = handlers.indexOf('const list: Partial<Record<FunboxName, FunboxFunctions>> = {');
assert.ok(first >= 0);
vm.runInContext(stripTypeScriptTypes(handlers.slice(first).replace(/^export /gm, ''),
  {mode: 'transform'}), context);
const networkFunctions = context.getFunboxFunctions();
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
for (const kind of ['IPv4', 'IPv6']) for (const samples of tapes) {
  tape = samples; draws = 0;
  fixtures.push({kind, samples, word: networkFunctions[kind].getWord(), draws});
}
const punctuation = [];
const addresses = {
  IPv4: ['0.0.0.0', '255.255.255.255', '192.168.23.47'],
  IPv6: ['0000:0000:0000:0000:0000:0000:0000:0000',
    'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff', '0001:0000:0000:0002:0000:0000:0003:0004',
    '0000:0000:0001:0002:0003:0004:0005:0006', '0001:0002:0003:0004:0005:0006:0000:0000',
    '0001:0000:0002:0003:0004:0005:0006:0007'],
};
const punctuationTapes = [...tapes, [0, 1 - Number.EPSILON / 2], [0.249999, 0.5], [0.25], [0.75]];
for (const kind of ['IPv4', 'IPv6']) for (const input of addresses[kind]) for (const samples of punctuationTapes) {
  tape = samples; draws = 0;
  const word = networkFunctions[kind].punctuateWord(input);
  punctuation.push({kind, input, samples, word, draws});
}
verify();
process.stdout.write(JSON.stringify({fixtures, punctuation}) + '\n');
