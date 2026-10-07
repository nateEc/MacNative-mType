// QA only: execute the pinned ButtonGroup activation callback, without Solid/DOM.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const root = path.resolve(process.argv[2] ?? '');
const emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
const referenceCommit = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), referenceCommit);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/components/pages/account/Filters.tsx'), 'utf8');
const marker = 'onClick={(e) => {';
assert.equal(source.split(marker).length, 2);
const start = source.indexOf(marker);
const end = source.indexOf('\n              />', start);
assert.ok(end > start);
const callback = source.slice(start + 'onClick={'.length, end).trimEnd().slice(0, -1);
// Load the source's actual finite group keys; language/Funbox providers are irrelevant here.
const defaultsSource = fs.readFileSync(path.join(root, 'frontend/src/ts/constants/default-result-filters.ts'), 'utf8');
const defaults = defaultsSource.slice(defaultsSource.indexOf('const object:'))
  .replace('export default structuredClone(object);', 'globalThis.defaults = object;');
let changedGroup;
const context = vm.createContext({structuredClone, LanguageList: [], getFunboxNames: () => [],
  props: {filters: {}}, options: {group: ''}, item: {id: ''},
  setFilter: (group, value) => { changedGroup = group; context.props.filters[group] = value; }});
new vm.Script(stripTypeScriptTypes(`${defaults}\nglobalThis.activate = ${callback};`, {mode: 'transform'}))
  .runInContext(context);

const groups = Object.fromEntries(['mode', 'difficulty', 'time', 'words', 'quoteLength']
  .map(group => [group, Object.keys(context.defaults[group])]));
const fixtures = [];
for (const [group, values] of Object.entries(groups)) {
  for (let bits = 0; bits < 2 ** values.length; bits++) {
    const selected = values.filter((_, i) => bits & (1 << i));
    for (const value of values) for (const shift of [false, true]) {
      context.props.filters = {[group]: Object.fromEntries(values.map(key => [key, selected.includes(key)])),
        untouched: {sentinel: true}};
      context.options = {group}; context.item = {id: value}; changedGroup = undefined;
      context.activate({shiftKey: shift});
      assert.equal(changedGroup, group);
      assert.equal(context.props.filters.untouched.sentinel, true);
      const expected = values.filter(key => context.props.filters[group][key]);
      assert.deepEqual(expected, shift ? [value] : values.filter(key =>
        key === value ? !selected.includes(key) : selected.includes(key)));
      fixtures.push({group, values, selected, value, shift, expected});
    }
  }
}
assert.equal(fixtures.length, 1136);
verify();
console.log(emit ? JSON.stringify({referenceCommit, groups, fixtures}) :
  'History filter choice source passed (1136 complete callback activations across five groups; owned props/event/setFilter adapters, no Solid/browser/native input acceptance)');
