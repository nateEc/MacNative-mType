// QA only: complete pinned wrapper-height function, owned word/CSS metrics.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const [argument, option] = process.argv.slice(2);
assert.ok(argument && (!option || option === '--emit-fixtures'));
const root = path.resolve(argument), pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/test/test-ui.ts'), 'utf8');
const start = source.indexOf('export function updateWordsWrapperHeight(');
const end = source.indexOf('\nfunction updateWordsMargin(', start);
assert.ok(start >= 0 && end > start);
const code = stripTypeScriptTypes(source.slice(start, end).replace(/^export /gm, ''), {mode: 'transform'});
const fixtures = [];
for (const tapeMode of ['off', 'word', 'letter']) for (const inkHeight of [24, 28, 34, 46])
for (const force of [false, true]) for (const expanded of [false, true])
for (const gate of ['test', 'settings', 'result', 'missing-word']) {
  let height = null, outOfFocus = null, shown = 0;
  const rowHeight = inkHeight + 5;
  const active = {native: {}, getOffsetHeight: () => inkHeight};
  const context = vm.createContext({Config: {mode: 'zen', tapeMode, showAllLines: expanded},
    getActivePage: () => gate === 'settings' ? 'settings' : 'test',
    getResultVisible: () => gate === 'result',
    getActiveWordElement: () => gate === 'missing-word' ? null : active,
    window: {getComputedStyle: () => ({marginTop: '2.9px', marginBottom: '3.9px'})},
    wordsWrapperEl: {show() { shown++; }, setStyle(value) { height = value.height; }},
    setOutOfFocusMaxHeight(value) { outOfFocus = value; },
    CustomText: {getLimitMode() { throw new Error('Zen must not query a custom limit'); }},
  });
  vm.runInContext(code + '\nupdateWordsWrapperHeight(' + force + ');', context, {timeout: 1000});
  const runs = force && gate === 'test';
  assert.equal(height, runs ? expanded ? '' : `${rowHeight * 2}px` : null);
  assert.equal(outOfFocus, runs ? rowHeight * 3 : null);
  assert.equal(shown, runs ? 1 : 0);
  fixtures.push({tapeMode, force, expanded, gate, rowHeight, height});
}
assert.equal(fixtures.length, 192); verify();
if (option) process.stdout.write(JSON.stringify({pin, fixtures}));
else console.log('Zen tape viewport source passed (192 complete wrapper-height cases; off/word/letter, force/raw showAll, result/page/missing-word gates, fractional margin truncation; owned word/CSS metrics, no browser/native-font equivalence)');
