// QA only: execute the complete pinned wrapper function with owned geometry.
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
const profiles = [
  {id: 'words', mode: 'words', limitMode: 'word', limit: 25},
  {id: 'time', mode: 'time', limitMode: 'time', limit: 30},
  {id: 'quote', mode: 'quote', limitMode: 'word', limit: 25},
  {id: 'custom-words', mode: 'custom', limitMode: 'word', limit: 25},
  {id: 'custom-time', mode: 'custom', limitMode: 'time', limit: 30},
  {id: 'custom-infinite', mode: 'custom', limitMode: 'word', limit: 0},
];
const fixtures = [];
for (const profile of profiles) for (const tapeMode of ['word', 'letter'])
for (const inkHeight of [24, 46]) for (const force of [false, true])
for (const expanded of [false, true]) for (const hasNewline of [false, true])
for (const gate of ['test', 'settings', 'result', 'missing-word']) {
  let height = null, outOfFocus = null, shown = 0;
  const rowHeight = inkHeight + 5, wordsHeight = inkHeight === 24 ? undefined : rowHeight * 4;
  const active = {native: {}, getOffsetHeight: () => inkHeight};
  const context = vm.createContext({Config: {mode: profile.mode, tapeMode, showAllLines: expanded},
    getActivePage: () => gate === 'settings' ? 'settings' : 'test',
    getResultVisible: () => gate === 'result',
    getActiveWordElement: () => gate === 'missing-word' ? null : active,
    window: {getComputedStyle: () => ({marginTop: '2.9px', marginBottom: '3.9px'})},
    wordsWrapperEl: {show() { shown++; }, setStyle(value) { height = value.height; }},
    wordsEl: {getOffsetHeight: () => wordsHeight}, wordsHaveNewline: () => hasNewline,
    CustomText: {getLimitMode: () => profile.limitMode, getLimitValue: () => profile.limit},
    setOutOfFocusMaxHeight(value) { outOfFocus = value; },
  });
  vm.runInContext(code + '\nupdateWordsWrapperHeight(' + force + ');', context, {timeout: 1000});
  const runs = gate === 'test' && (force || profile.mode === 'custom');
  const timed = profile.mode === 'time' || profile.mode === 'custom'
    && (profile.limitMode === 'time' || profile.limit === 0);
  const expected = expanded && !timed ? '' : `${hasNewline ? rowHeight * 3 : wordsHeight ?? rowHeight}px`;
  assert.equal(height, runs ? expected : null);
  assert.equal(outOfFocus, runs ? rowHeight * 3 : null); assert.equal(shown, runs ? 1 : 0);
  fixtures.push({...profile, tapeMode, force, expanded, hasNewline, gate, rowHeight, height,
    wordsHeight: wordsHeight ?? null});
}
assert.equal(fixtures.length, 768);
function module(id) {
  return stripTypeScriptTypes(fs.readFileSync(path.join(root, 'frontend/src/ts', id + '.ts'), 'utf8')
    .replace(/^import [\s\S]*?;\n/gm, ''), {mode: 'transform'}).replace(/^export /gm, '');
}
const buildStart = source.indexOf('function buildWordHTML(');
const buildEnd = source.indexOf('function updateWordWrapperClasses(', buildStart);
assert.ok(buildStart >= 0 && buildEnd > buildStart);
const build = stripTypeScriptTypes(source.slice(buildStart, buildEnd), {mode: 'transform'});
const wordFixtures = [];
for (const tokens of [['a\n', 'b\n'], ['a ', ' ', 'b '], ['a\n', '\n'], ['a '], ['\n'],
  ['a\n', 'b'], ['ab ', 'tail\n', 'first\n', 'second\n', 'third\n'], ['א\n', '👩🏽‍💻é']]) {
  const context = vm.createContext({tokens, getActiveWordIndex: () => 0,
    findSingleActiveFunboxWithFunction: () => undefined});
  vm.runInContext(module('utils/strings') + '\nglobalThis.Strings = {splitIntoCharacters};\n'
    + module('test/test-words') + '\n' + build, context, {timeout: 1000});
  const result = vm.runInContext(`tokens.forEach(token => words.push(token, 0));
    JSON.stringify({display: words.get().map(word => word.display), wordCount: words.length,
      html: words.get().map((word, index) => buildWordHTML(word.display, index)).join('')})`, context);
  const {display, wordCount, html} = JSON.parse(result);
  assert.equal(wordCount, tokens.length);
  assert.equal((html.match(/data-wordindex=/g) ?? []).length, tokens.length);
  assert.equal((html.match(/class='newline'/g) ?? []).length, display.filter(word => word.includes('\n')).length);
  wordFixtures.push({tokens, display, wordCount});
}
assert.equal(wordFixtures.length, 8); verify();
if (option) process.stdout.write(JSON.stringify({pin, fixtures, wordFixtures}));
else console.log('Ordinary tape viewport source passed (768 complete wrapper-height cases and 8 real Words/Strings/buildWordHTML sequences; four modes, finite/timed/infinite custom, declared-newline three rows vs natural words height/fallback, force/raw showAll, page/result/missing-word gates, no invented trailing word; owned metrics, no browser/native-font equivalence)');
