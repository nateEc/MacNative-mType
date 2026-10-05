// QA-only: execute the exact pinned TanStack dependency's full comparator.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
const verify = () => {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
};
verify();
assert.ok(fs.readFileSync(path.join(root,'pnpm-lock.yaml'),'utf8').includes("'@tanstack/db@0.6.8':"));
const runtime = process.env.TYPEBAR_INBOX_SOURCE_PACKAGE;
assert.ok(runtime,'TYPEBAR_INBOX_SOURCE_PACKAGE must point at QA-only @tanstack/db 0.6.8');
assert.equal(JSON.parse(fs.readFileSync(path.join(runtime,'package.json'),'utf8')).version,'0.6.8');
const context = vm.createContext({});
const module = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(path.join(runtime,'src/utils/comparison.ts'),'utf8'),
  {mode:'transform'}),{context});
// String-only probes never enter Temporal handling; no application module adapter.
await module.link(async identifier => {
  assert.equal(identifier,'../utils');
  return new vm.SyntheticModule(['isTemporal'],function() { this.setExport('isTemporal',() => false); },{context});
});
await module.evaluate();
const collection = fs.readFileSync(path.join(runtime,'src/collection/index.ts'),'utf8');
const start = collection.indexOf('function buildCompareOptionsFromConfig(');
assert.ok(start >= 0);
new vm.Script(stripTypeScriptTypes(collection.slice(start),{mode:'transform'})).runInContext(context);
const defaults = context.buildCompareOptionsFromConfig({});
assert.equal(defaults.stringSort,'locale');
const inputs = [ ['z','ö','a','A','å','ä','é','e','\uE000','😀'],
  ['Éclair','eclair','Eclair','苹果','香蕉','草莓'], ['same','same','e\u0301','é','B','b'] ];
const fixtures = [];
for (const locale of ['en-US','de','sv','zh']) for (const input of inputs) {
  const compare = module.namespace.makeComparator({...defaults,direction:'asc',nulls:'first',locale});
  fixtures.push({locale,input,expected:[...input].sort(compare)});
}
verify();
process.stdout.write(emit ? JSON.stringify({referenceCommit:pin,dependency:'@tanstack/db@0.6.8',fixtures})
  : `Inbox title order source passed (${fixtures.length} locale samples; actual full comparator/default collection config; string-only Temporal adapter; no GUI)\n`);
