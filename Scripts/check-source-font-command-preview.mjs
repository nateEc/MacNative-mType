// QA only: complete pinned preview/apply/clear, active-command and hide bodies.
// Owned DOM/modal/font-file/language boundaries; not browser font pixels.
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
const read = file => fs.readFileSync(path.join(root, 'frontend/src/ts', file), 'utf8');
function between(source, first, last) {
  const a = source.indexOf(first), b = source.indexOf(last, a);
  assert.ok(a >= 0 && b > a, first);
  return source.slice(a, b);
}
const plain = text => stripTypeScriptTypes(text, {mode: 'transform'}).replace(/^export /gm, '');
const fontCode = plain(between(read('ui.ts'), 'let isPreviewingFont = false;', '\nexport function setMediaQueryDebugLevel('));
const commands = read('commandline/commandline.ts');
const activeCode = plain(between(commands, 'async function updateActiveCommand(', '\nlet shakeTimeout:'));
const hideCode = plain(between(commands, 'function hide(', '\nasync function goBackOrHide('));
const metadata = between(read('commandline/commandline-metadata.ts'), '\n  fontFamily: {', '\n  keymapMode: {');
const hover = metadata.match(/hover: (\(name\) => UI\.previewFontFamily\(name\)),/);
assert.ok(hover, 'Pinned complete hover callback');
const fixtures = [];
for (const local of [false, true]) for (const preferred of [false, true])
for (const hideRoute of ['store', 'chain', 'legacy']) {
  const Config = {fontFamily: 'Courier', language: 'owned-language'};
  let css = '', fileReads = 0, hints = 0, rows = [], themeClears = 0;
  const pending = [], trace = [], modalEvents = [];
  const noop = () => {};
  const context = vm.createContext({Config, isAnimating: false, activeIndex: 0, activeCommand: null,
    TestUI: {updateHintsPositionDebounced: () => hints++},
    document: {documentElement: {style: {setProperty: (key, value) => {
      assert.equal(key, '--font'); css = value; trace.push(value);
    }}}, querySelectorAll: () => rows.map(() => ({classList: {add: noop, remove: noop}}))},
    fileStorage: {getFile: async key => { assert.equal(key, 'LocalFontFamilyFile'); fileReads++; return local ? 'owned-font-file' : undefined; }},
    qs: selector => { assert.equal(selector, '.customFont'); return {empty: noop, setHtml: noop}; },
    replaceUnderscoresWithSpaces: value => value.replaceAll('_', ' '),
    getLanguage: async () => preferred ? {preferredFont: 'Noto_Sans_Lao'} : {},
    getList: async () => rows, ThemeController: {clearPreview: () => themeClears++},
    keepActiveCommandInView: noop, addCommandlineBackground: noop, removeCommandlineBackground: noop,
    MODAL_STORE_ID: 'owned-command-modal', isModalOpen: () => hideRoute !== 'legacy',
    storeClearChain: () => modalEvents.push('chain'), storeHideModal: () => modalEvents.push('store'),
    modal: {hide: options => { modalEvents.push('legacy'); pending.push(options.afterAnimation()); }},
    hideWarning: noop, getActivePage: () => 'test', setCommandlineSubgroup: noop, subgroupOverride: null,
  });
  vm.runInContext(fontCode + '\n' + activeCode + '\n' + hideCode, context, {timeout: 1000});
  context.UI = {previewFontFamily: context.previewFontFamily};
  const preview = vm.runInContext('(' + hover[1] + ')', context);
  await context.applyFontFamily();
  assert.ok(css.startsWith(local ? '"LOCALCUSTOM"' : '"Courier"'));
  if (preferred) assert.ok(css.includes('Noto Sans Lao'));
  const initial = css;
  rows = [{id: 'setFontFamilyGeorgia', found: true, hover: () => preview('Georgia')}];
  await context.updateActiveCommand();
  assert.ok(css.startsWith('"Georgia"')); assert.equal(Config.fontFamily, 'Courier');
  assert.equal(fileReads, 1, 'Hover never loads or replaces the local file');
  rows = [{id: 'setFontFamilyRoboto_Mono', found: true, hover: () => preview('Roboto_Mono')}];
  await context.updateActiveCommand(); assert.ok(css.startsWith('"Roboto Mono"'));
  rows = [{id: 'history', found: true}]; await context.updateActiveCommand();
  assert.ok(css.startsWith('"Courier"')); assert.ok(!css.includes('LOCALCUSTOM'));
  assert.ok(!css.includes('Noto Sans Lao'), 'clear uses saved family, not complete apply cascade');
  rows = [{id: 'setFontFamilyGeorgia', found: true, hover: () => preview('Georgia')}];
  await context.updateActiveCommand(); rows = []; await context.updateActiveCommand();
  assert.ok(css.startsWith('"Courier"'));
  rows = [{id: 'setFontFamilyGeorgia', found: true, hover: () => preview('Georgia')}];
  await context.updateActiveCommand();
  Config.fontFamily = 'Menlo'; // An intervening accepted setting must win over the opening snapshot.
  context.hide(hideRoute === 'chain'); await Promise.all(pending);
  assert.ok(css.startsWith('"Menlo"')); assert.equal(Config.fontFamily, 'Menlo');
  assert.deepEqual(modalEvents, [hideRoute]); assert.ok(hints > 0); assert.ok(themeClears > 0);
  const afterHide = css;
  context.clearFontPreview(); assert.equal(css, afterHide, 'Repeated clear is inert');
  fixtures.push({local, preferred, hideRoute, initial, restored: afterHide, traceCount: trace.length});
}
verify();
if (option) console.log(JSON.stringify({pin, fixtures}));
else console.log('Font command preview source passed: 12 complete hover/active-command/preview/apply/clear/hide trajectories, store/chain/legacy, empty/non-font choices and intervening saved choice. Clear restores saved name without reapplying local/preferred cascade; owned DOM/modal/file/language boundaries, not browser/native pixel parity.');
