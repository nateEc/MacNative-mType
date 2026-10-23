// QA only. Execute the complete pinned legacy replacement function, without
// claiming schema sanitization/default merging/JSON parsing or browser parity.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? '');
assert.ok(process.argv[2]);
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/config/utils.ts'), 'utf8');
const from = source.indexOf('function replaceLegacyValues(');
const to = source.indexOf('\nexport function getConfigChanges(', from);
assert.ok(from >= 0 && to > from);
const context = vm.createContext({});
new vm.Script(stripTypeScriptTypes(source.slice(from, to), {mode: 'transform'})).runInContext(context);
const fixtures = [];
function add(input) {
  const before = structuredClone(input);
  const after = context.replaceLegacyValues(structuredClone(input));
  fixtures.push({before, after}); // JSON projection intentionally turns nonfinite numbers into null.
}
const scalars = [null, true, false, -1001, -1, 0, 1, 9, 10, 19, 20, 90, 100, 101, 1001,
  '', ' ', '125', '15', '15px', '1.25rem', '0x20', '0x', '+0x10', '-0x10', '1e+',
  '1e3tail', '.5suffix', '-Infinity', 'Infinity', 'bad', '\u00851', '\ufeff2.5px',
  '0x 10', '0x\ufeff10', '+ 1', '- 1', '0b101', '0o17', '0b102', ["0x10"], [[-1]],
  [], [1], [-1], [null], [1, 2], {}];
for (const key of ['smoothCaret', 'playSoundOnError', 'indicateTypos', 'soundVolume',
  'funbox', 'customLayoutfluid', 'fontSize', 'minAccCustom', 'quoteLength', 'tapeMargin', 'maxLineWidth']) {
  for (const value of scalars) add({[key]: value, ownedUnknown: {keep: [1, false, null]}});
}
for (const key of ['accountChart', 'customThemeColors', 'customBackgroundFilter']) {
  for (let size = 0; size <= 11; size++) add({[key]: Array.from({length: size}, (_, i) => String(i))});
}
for (const timerStyle of [undefined, null, 'off', 'bar', 'mini', 'text', false]) {
  for (const modern of [undefined, null, 'off', 'mini']) {
    for (const showTimerProgress of [undefined, false, true]) {
      add({showLiveWpm: true, showLiveAcc: true, showLiveBurst: true, timerStyle,
        liveSpeedStyle: modern, liveAccStyle: modern, liveBurstStyle: modern, showTimerProgress});
    }
  }
}
for (const quickRestart of [undefined, null, 'off', 'esc']) {
  add({quickTab: true, swapEscAndTab: true, quickRestart, alwaysShowCPM: true});
}
for (const keymapShowTopRow of ['never', 'always', 'layout', 'other', null]) {
  for (const keymapKeys of [undefined, null, 'full']) add({keymapShowTopRow, keymapKeys});
}
add({funbox: 'read_ahead#no_quit', customLayoutfluid: 'qwerty##dvorak', showAverage: 'wpm'});
add({funbox: 'none', alwaysShowCPM: true, typingSpeedUnit: 'wpm'});
verify();
console.log(JSON.stringify({fixtures}));
