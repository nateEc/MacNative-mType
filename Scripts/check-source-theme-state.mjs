// QA only: source callbacks and color classification over synthetic inputs.
// No original theme palette or other visual asset is loaded or shipped.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';
const root = path.resolve(process.argv[2] ?? '');
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
const read = file => fs.readFileSync(path.join(root, 'frontend/src/ts', file), 'utf8');
function slice(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a);
  assert.ok(a >= 0 && b > a, `Missing pinned source boundary: ${start}`);
  return source.slice(a, b);
}
let dark = false, selected = null, initialCallback, changeCallback;
const context = vm.createContext({Config: {},
  clearRandom: async () => {}, clearPreview: async () => {}, applyCustomBackground: async () => {},
  prefersColorSchemeDark: () => dark, set: async name => {selected = name;},
  configEvent: {subscribe: callback => {initialCallback = callback;}},
  window: {matchMedia: () => ({addEventListener: (_, callback) => {changeCallback = callback;}})},
});
const colors = read('utils/colors.ts');
for (const name of ['hexToHSL', 'isColorDark']) {
  const text = slice(colors, `export function ${name}(`, '\n}\n') + '\n}';
  vm.runInContext(stripTypeScriptTypes(text.replace(/^export /, ''), {mode:'transform'}), context);
}
const controller = read('controllers/theme-controller.ts');
vm.runInContext(stripTypeScriptTypes(slice(controller, 'window\n  .matchMedia?', '\nlet ignoreConfigEvent'),
  {mode:'transform'}), context);
// Execute the actual full-import branch; omit unrelated setting-event branches.
vm.runInContext(stripTypeScriptTypes('let ignoreConfigEvent = false;\n' +
  slice(controller, 'configEvent.subscribe(async', '\n  // this is here') + '\n});',
  {mode:'transform'}), context);
const events = [];
for (const followsSystem of [false, true]) for (const customEnabled of [false, true]) {
  for (const systemIsDark of [false, true]) {
    context.Config = {autoSwitchTheme:followsSystem, customTheme:customEnabled,
      theme:'serika_dark', themeLight:'serika', themeDark:'dracula'};
    dark = systemIsDark; selected = null;
    await initialCallback({key:'fullConfigChangeFinished'});
    const initial = selected; selected = null;
    changeCallback({matches:systemIsDark});
    events.push({followsSystem, customEnabled, systemIsDark, initial, change:selected});
  }
}
// Exhaust all 511 possible min+max sums, and all shorthand values.
const hexes = [];
for (let sum = 0; sum <= 510; sum++) {
  const low = Math.max(0, sum - 255), high = sum - low;
  hexes.push('#' + [low, high, low].map(x => x.toString(16).padStart(2, '0')).join(''));
}
for (let value = 0; value < 4096; value++) hexes.push('#' + value.toString(16).padStart(3, '0'));
for (let low = 0; low <= 255; low++) {
  hexes.push('#' + [low, 255 - low, low].map(x => x.toString(16).padStart(2, '0')).join(''));
}
verify();
process.stdout.write(JSON.stringify({events, colors:hexes.map(hex => ({hex, dark:context.isColorDark(hex)}))}));
