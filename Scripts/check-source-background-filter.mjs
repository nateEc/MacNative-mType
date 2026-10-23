// QA only. Execute the pinned complete filter setter with owned style capture.
// This observes emitted declarations, not browser CSS parsing or image pixels.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const [argument] = process.argv.slice(2);
assert.ok(argument);
const root = path.resolve(argument), pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/controllers/theme-controller.ts'), 'utf8');
const start = source.indexOf('export function applyCustomBackgroundFilters(');
const end = source.indexOf('\nwindow\n', start);
assert.ok(start >= 0 && end > start);
const code = stripTypeScriptTypes(source.slice(start, end), {mode: 'transform'}).replace(/^export /gm, '');
const cases = [[0, 1, 1, 1], [-0, 1, 1, 1], [0.25, 2.5, 4, 0.4], [60, 5, 7, 3], [0, 0, 0, 0]];
for (let position = 0; position < 4; position++) {
  for (const value of [-1, Infinity, -Infinity, NaN, -0, 1e-7, 1e21]) {
    const values = [0.2, 0.5, 2, 0.8];
    values[position] = value;
    cases.push(values);
  }
}
const fixtures = [];
for (const values of cases) {
  let style, writes = 0;
  const context = vm.createContext({getConfig: {customBackgroundFilter: values}, qs: selector => {
    assert.equal(selector, '.customBackground img');
    return {setStyle: value => { style = value; writes++; }};
  }});
  vm.runInContext(code, context, {timeout: 1000});
  // Verify both the explicit preview argument and the saved-config path.
  context.applyCustomBackgroundFilters(values);
  const explicit = JSON.stringify(style);
  context.applyCustomBackgroundFilters();
  assert.equal(JSON.stringify(style), explicit);
  assert.equal(writes, 2);
  fixtures.push({values: values.map(value => Object.is(value, -0) ? '-0' : String(value)), css: style.filter});
}
verify();
console.log(JSON.stringify({pin, fixtures}));
