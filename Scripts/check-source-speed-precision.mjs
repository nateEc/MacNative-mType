// QA only: execute both complete pinned number modules; no browser, result
// controller, persistence or anti-cheat claim. Fixtures contain owned numbers.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? '');
const emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const context = vm.createContext({});
const load = relative => new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(path.join(root,relative),'utf8'),
  {mode:'transform'}),{context});
const utilities = load('packages/util/src/numbers.ts');
await utilities.link(id => { throw new Error('Unexpected number dependency '+id); }); await utilities.evaluate();
const frontend = load('frontend/src/ts/utils/numbers.ts');
await frontend.link(id => {
  assert.equal(id,'@monkeytype/util/numbers');
  return utilities;
}); await frontend.evaluate();
const rounding = [0,1.005,59.995,60.005,60.495,60.499,419.995,420]
  .map(input => ({input,expected:utilities.namespace.roundTo2(input)}));
const speeds = [[0,15],[1,15],[5,3],[75,900/60.41],[75,900/60.49],[5,15.125]]
  .map(([units,seconds]) => ({units,seconds,expected:utilities.namespace.roundTo2(frontend.namespace.calculateWpm(units,seconds))}));
for (const value of [...rounding,...speeds]) assert.ok(Number.isFinite(value.expected));
assert.equal(speeds[3].expected,60.41); assert.equal(speeds[4].expected,60.49);
assert.equal(rounding[1].expected,1.01); assert.equal(rounding[4].expected,60.5);
verify();
console.log(emit ? JSON.stringify({referenceCommit:pin,rounding,speeds})
  : 'Speed precision source passed (8 rounding and 6 speed fixtures; two complete number modules; no GUI)');
