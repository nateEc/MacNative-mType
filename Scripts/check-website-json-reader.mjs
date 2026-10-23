// QA only: the JSON intrinsic used by the pinned import helper. No JS runtime
// or reference code is embedded in the native reader.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root = path.resolve(process.argv[2] ?? '');
assert.ok(process.argv[2]);
assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
assert.ok(fs.readFileSync(path.join(root, 'packages/util/src/json.ts'), 'utf8').includes('JSON.parse(json)'));
function describe(value) {
  if (value === null) return {null: true};
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') { const bytes = Buffer.alloc(8); bytes.writeDoubleBE(value); return {number: bytes.toString('hex')}; }
  if (typeof value === 'string') return {string: Array.from({length: value.length}, (_, i) => value.charCodeAt(i))};
  if (Array.isArray(value)) return value.map(describe);
  return {object: Object.keys(value).sort().map(key => [describe(key).string, describe(value[key])])};
}
const fixtures = [];
function add(json, unsupported = null) {
  try {
    const parsed = JSON.parse(json);
    fixtures.push({json, accepted: true, value: describe(parsed), roundTrip: describe(JSON.parse(JSON.stringify(parsed))), unsupported});
  }
  catch { fixtures.push({json, accepted: false, unsupported: null}); }
}
for (const json of ['null', 'true', 'false', '0', '-0', '-0.0', '1.25', '1e400', '-1E400',
  '1e-400', '-1e-400', '9007199254740993', '0e99999999999', '1e99999999999',
  '2.2250738585072012e-308', '5e-324', '-5e-324', '1.7976931348623157e308', '1.7976931348623159e308',
  '""', '"😀"', '"é"', '"e\\u0301"', '"\\uD834\\uDD1E"', '"\\u0000\\b\\f\\n\\r\\t\\/\\\\\\\""',
  '[]', '{}', '[1,true,null,"x",{}]', '{"numbers":false,"numbers":true}',
  '{"a":1,"\\u0061":2}', '{"__proto__":{"x":1},"constructor":2}', ' \t\n\r {"x":-0} ',
  '', ' ', '{', '[', '[1,]', '{"x":1,}', '{}{}', 'true false', '01', '-01', '+1', '1.', '.1',
  '1e', '1e+', '--1', 'NaN', 'Infinity', '/*x*/{}', '"\\x12"', '"\\uZZZZ"', '"\\u123"', '"\n"',
  '\uFEFF{}', '\u0085{}', '\u2028{}']) add(json);
for (let index = 1; index <= 128; index++) for (const exponent of [-400, -309, -308, -200, -1, 0, 1, 308, 309, 400]) {
  add(`${index % 2 ? '-' : ''}${index}.${(index * 7919).toString().padStart(9, '0')}e${exponent}`);
}
for (const json of ['"\\uD800"', '{"future":"\\uDFFF"}', '{"\\ud800":1}']) add(json, 'utf16');
add('{"é":1,"e\\u0301":2}', 'keys');
console.log(JSON.stringify({fixtures}));
