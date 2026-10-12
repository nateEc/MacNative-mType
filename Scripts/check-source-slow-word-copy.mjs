// QA only: execute the complete pinned click callback. Input/burst history,
// modal validation and clipboard are owned adapter boundaries, not browser UI.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
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
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/test/test-ui.ts'), 'utf8');
const start = source.indexOf('qs(".pageTest #copySlowWordsListButton")');
const end = source.indexOf('\nasync function copyToClipboard(', start);
assert.ok(start >= 0 && end > start);
const code = stripTypeScriptTypes(source.slice(start, end), {mode: 'transform'});
const fixtures = [];
const cases = [
  {name: 'empty target keeps position', zen: false, targets: ['', 'harbor', ''], inputs: [' ', 'h', ''], bursts: [0, 30, 0], threshold: 80, expected: ['', 'harbor', '']},
  {name: 'only empty target still selects one word', zen: false, targets: [''], inputs: [' '], bursts: [0], threshold: 80, expected: ['']},
  {name: 'strict boundary and repeated targets', zen: false, targets: ['harbor', 'river', 'harbor'], inputs: ['h', 'r', 'h'], bursts: [40, 80, 20], threshold: 80, expected: ['harbor', 'harbor']},
  {name: 'Zen commits and empty input', zen: true, targets: ['unused'], inputs: ['朝 ', '', 'river\n'], bursts: [10, 0, 20], threshold: 80, expected: ['朝 ', '', 'river\n']},
  {name: 'missing bursts do not select', zen: false, targets: ['harbor', 'river'], inputs: ['h', 'r'], bursts: [null, null], threshold: 80, expected: []},
  {name: 'unreached target omitted', zen: false, targets: ['harbor', 'future'], inputs: ['h'], bursts: [10], threshold: 80, expected: ['harbor']},
];
for (const item of cases) {
  let click, modal;
  const copies = [];
  const numberSchema = {finite() { return this; }, positive() { return this; }};
  const context = vm.createContext({
    qs: selector => {
      assert.equal(selector, '.pageTest #copySlowWordsListButton');
      return {on: (event, callback) => { assert.equal(event, 'click'); click = callback; }};
    },
    getLastEventLog: () => ({}), Config: {mode: item.zen ? 'zen' : 'words'},
    getInputHistory: () => item.inputs,
    getWordBurstHistory: () => item.bursts,
    TestWords: {words: {get: () => item.targets.map(text => ({text}))}},
    showSimpleModal: value => { modal = value; },
    z: {object: value => value, number: () => numberSchema},
    copyToClipboard: async (text, message) => { copies.push({text, message}); },
  });
  new vm.Script(code).runInContext(context, {timeout: 1000});
  assert.equal(typeof click, 'function');
  click();
  assert.ok(modal);
  const outcome = await modal.execFn({speedThreshold: item.threshold});
  assert.equal(outcome.status, item.expected.length ? 'success' : 'notice', item.name);
  assert.equal(copies.length, item.expected.length ? 1 : 0, item.name);
  if (copies.length) assert.equal(copies[0].text, item.expected.join(' '), item.name);
  const positives = item.bursts.filter(value => Number.isFinite(value) && value > 0);
  const defaultThreshold = positives.length ? Math.round(positives.reduce((a, b) => a + b, 0) / positives.length) : 80;
  assert.equal(modal.inputs.speedThreshold.initVal, defaultThreshold, item.name);
  fixtures.push({...item, defaultThreshold, copiedText: copies[0]?.text ?? null});
}
verify();
if (option === '--emit-fixtures') process.stdout.write(JSON.stringify(fixtures));
else console.log(`Pinned complete slow-word copy callback passed: ${fixtures.length} cases; owned history/modal/clipboard adapters, no browser or real clipboard claim`);
