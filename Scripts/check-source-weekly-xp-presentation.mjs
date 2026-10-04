// Execute complete pinned frontend utilities read-only; no browser or GUI.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {pathToFileURL} from 'node:url';

const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
const verify = () => {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
};
verify();
const dependencies = process.env.TYPEBAR_PRACTICE_SOURCE_DEPENDENCIES;
assert.ok(dependencies,'Pinned date runtime required; readiness prepares an isolated runtime');
const directory = path.join(dependencies,'node_modules/date-fns');
assert.equal(JSON.parse(fs.readFileSync(path.join(directory,'package.json'))).version,'3.6.0');
assert.equal(JSON.parse(fs.readFileSync(path.join(root,'frontend/package.json'))).dependencies['date-fns'],'3.6.0');
const dates = await import(pathToFileURL(path.join(directory,'index.mjs')).href);
const context = vm.createContext({});
const source = relative => new vm.SourceTextModule(stripTypeScriptTypes(
  fs.readFileSync(path.join(root,relative),'utf8'),{mode:'transform'}),{context});
const numbers = source('packages/util/src/numbers.ts');
await numbers.link(() => { throw new Error('Unexpected number dependency'); });
await numbers.evaluate();
const dateModule = new vm.SyntheticModule(['Day','formatDistanceToNow','formatDuration','intervalToDuration'],function() {
  this.setExport('Day',undefined);
  for (const name of ['formatDistanceToNow','formatDuration','intervalToDuration']) this.setExport(name,dates[name]);
},{context});
const frontend = source('frontend/src/ts/utils/date-and-time.ts');
await frontend.link(id => {
  if (id === '@monkeytype/util/numbers') return numbers;
  if (id === 'date-fns') return dateModule;
  throw new Error('Unexpected frontend dependency '+id);
});
await frontend.evaluate();
const fixtures = [0,0.0001,0.49,0.5,0.5001,1,15.25,45.75,59.49,59.5,60,3599.49,
  3599.5,3600,86399.5,86400,360000,9_007_199_254_740_991].map(seconds => ({seconds,
  label:frontend.namespace.secondsToString(Math.round(seconds),true,true,':')}));
verify();
process.stdout.write(emit ? JSON.stringify({referenceCommit:pin,fixtures})
  : `Pinned frontend weekly time passed (${fixtures.length} fixtures; complete utility modules; no GUI)\n`);
