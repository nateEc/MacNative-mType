// QA only: execute complete pinned word building/updating and real Words/Strings.
// DOM, hint placement, frame scheduling and CSS metrics remain owned boundaries.
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
function module(id) {
  return stripTypeScriptTypes(fs.readFileSync(path.join(root, 'frontend/src/ts', id + '.ts'), 'utf8')
    .replace(/^import [\s\S]*?;\n/gm, ''), {mode: 'transform'}).replace(/^export /gm, '');
}
const ui = fs.readFileSync(path.join(root, 'frontend/src/ts/test/test-ui.ts'), 'utf8');
function completeSpan(startMarker, endMarker) {
  const start = ui.indexOf(startMarker), end = ui.indexOf(endMarker, start);
  assert.ok(start >= 0 && end > start);
  return stripTypeScriptTypes(ui.slice(start, end), {mode: 'transform'}).replace(/^export /gm, '');
}
const build = completeSpan('function buildWordHTML(', 'function updateWordWrapperClasses(');
const update = completeSpan('export let pendingWordData:', '// this is needed in tape mode');
const appendEmpty = completeSpan('export function appendEmptyWordElement(', 'export function updateWordsInputPosition(');
const css = fs.readFileSync(path.join(root, 'frontend/src/styles/test.scss'), 'utf8');
const indexCSS = fs.readFileSync(path.join(root, 'frontend/src/styles/index.scss'), 'utf8');
assert.match(indexCSS, /\.invisible\s*\{[^}]*opacity: 0;[^}]*visibility: hidden;/);
assert.match(css, /\.newline\s*\{\s*width: inherit;/);
assert.match(css, /\.beforeNewline\s*\{[^}]*height: 1em;/);
assert.match(css, /&\.tabChar,\s*&\.nlChar\s*\{[^}]*opacity: 0\.2;/);
const asl = fs.readFileSync(path.join(root, 'frontend/static/funbox/asl.css'), 'utf8');
assert.ok(asl.includes('font-family: Gallaudet !important;'));
assert.ok(!asl.includes('nlChar') && !asl.includes('tabChar'));
function letters(html) {
  return Array.from(html.matchAll(/<letter\b([^>]*)>([\s\S]*?)<\/letter>/g), ([, attributes, body]) => ({
    text: body.includes('fa-level-down-alt') ? '↵' : body.includes('fa-long-arrow-alt-right') ? '→' : body,
    isExtra: /\bextra\b/.test(attributes), hidden: /\binvisible\b|opacity:\s*0(?:[;'"\s]|$)/.test(attributes),
    isTab: /\btabChar\b/.test(attributes), isReturn: /\bnlChar\b/.test(attributes),
  }));
}
let emptyMarkup = '';
vm.runInNewContext(appendEmpty + '\nappendEmptyWordElement(7);',
  {wordsEl: {appendHtml(value) { emptyMarkup = value; }}}, {timeout: 1000});
assert.ok(emptyMarkup.includes("data-wordindex='7'"));
assert.deepEqual(letters(emptyMarkup).map(({text, hidden}) => ({text, hidden})), [{text: '_', hidden: true}]);
const samples = [
  ['a\n', ''], ['a\n', 'a\n'], ['\n', '\n'], ['\ta', '\ta'], ['a\t', 'a\t'],
  ['\n', 'X'], ['a', '\n'], ['a', 'a\n'], ['a\n', 'aX'],
  ['', ''], ['\t', ''],
];
const fixtures = [];
for (const mode of ['words', 'zen']) for (const style of ['off', 'replace'])
for (const [original, input] of samples) {
  let markup = '', adjacent = '';
  const word = {setHtml(value) { markup = value; }, qsa: () => [], appendHtml() {},
    native: {insertAdjacentHTML(_where, value) { adjacent += value; }, getElementsByTagName: () => []}};
  const context = vm.createContext({getActiveWordIndex: () => 0,
    Config: {mode, indicateTypos: style, compositionDisplay: 'off', tapeMode: 'off', showAllLines: true},
    findSingleActiveFunboxWithFunction: () => undefined,
    requestDebouncedAnimationFrame: (_key, callback) => callback(),
    getWordElement: () => word, SlowTimer: {get: () => false}, original, input});
  new vm.Script(module('utils/strings') + '\nglobalThis.Strings = {splitIntoCharacters};\n' +
    module('test/test-words') + '\nglobalThis.TestWords = {words};\n' + build + '\n' + update)
    .runInContext(context, {timeout: 1000});
  const initial = vm.runInContext('words.push(original, 0); buildWordHTML(words.get(0).display, 0)', context);
  const display = vm.runInContext('words.get(0).display', context);
  await vm.runInContext('updateWordLetters({wordIndex: 0, input, compositionData: ""})', context);
  const initialLetters = letters(initial), updated = letters(markup);
  if (mode === 'zen' && input === '') {
    assert.deepEqual(updated.map(({text, hidden}) => ({text, hidden})), [{text: '_', hidden: true}]);
  }
  const helpers = (initial.match(/class='(?:beforeNewline|newline|afterNewline)'/g) ?? []).length;
  assert.equal(helpers, display.includes('\n') ? 3 : 0);
  assert.equal(initialLetters.filter(letter => letter.isReturn).length, Array.from(display).filter(char => char === '\n').length);
  if (mode === 'words' && !display.includes('\n')) {
    assert.equal(adjacent, '', 'Mistyped or extra Return cannot add target newline helpers');
    assert.ok(updated.filter(letter => letter.text === '↵').every(letter => !letter.isReturn));
  }
  if (mode === 'zen' && input.includes('\n')) assert.ok(adjacent.includes("class='newline'"));
  fixtures.push({mode, style, original, input, display, initial: initialLetters, updated, helpers});
}
assert.equal(fixtures.length, 44); verify();
if (option) process.stdout.write(JSON.stringify({pin, fixtures}));
else console.log('ASL controls source passed (44 complete build/update cases; real Words/Strings, target/extra Return and Zen controls/empty sentinel; CSS rules static, owned DOM/hints/RAF, no browser metrics or font assets)');
