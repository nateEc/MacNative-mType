// QA only: complete pinned word update and caret entry points, never product JS.
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
function source(id) { return fs.readFileSync(path.join(root, 'frontend/src/ts', id + '.ts'), 'utf8'); }
function javascript(text) {
  return stripTypeScriptTypes(text.replace(/^import [\s\S]*?;\n/gm, ''), {mode: 'transform'})
    .replace(/^export /gm, '');
}
const ui = source('test/test-ui'), begin = ui.indexOf('export let pendingWordData:');
const end = ui.indexOf('// this is needed in tape mode', begin);
assert.ok(begin >= 0 && end > begin);
const update = javascript(ui.slice(begin, end));
const caret = javascript(source('test/caret'));
const css = fs.readFileSync(path.join(root, 'frontend/src/styles/test.scss'), 'utf8');
assert.match(css, /&\.dead\s*\{[^}]*border-bottom-color: var\(--untyped-letter-color\);/);
const samples = [
  ['abcde', '', 'XY'], ['abcde', 'a', 'bX'], ['ab', 'a', 'XYZ'],
  ['ab', 'abcd', 'XY'], ['abc', '', ''], ['', '', 'XY'], ['', '', ''],
  ['abcd', 'ab', ''], ['abcd', 'abcd', ''], ['abcd', 'abcd', 'X'],
  ['abcd', 'X', 'bc'], ['abcd', 'a', ' '], ['a\tb\n', 'a', 'XYZ'],
  ['a\tb\n', 'a', ' \n\t'], ['\na', '', '\n'], ['\t', '', '\t'],
  ['候选文字', '候', '选X'], ['אבגד', 'א', 'בX'], ['طريق', 'ط', 'ري'],
  ['abc', '', 'XY Z'], ['abc', 'a', '\t'], ['abc', '', '\n'],
];
const unicodeSamples = [
  ['a😀bc', 'a', '😀'], ['a👩‍💻bc', 'a', '👨‍👩‍👧‍👦'],
  ['ae\u0301bc', 'a', 'e\u0301'], ['a😀bc', 'a😀', 'X'],
  ['éz', '', 'e\u0301'], ['e\u0301z', '', 'é'],
];
function units(text) { return Array.from({length: text.length}, (_, i) => text.charCodeAt(i)); }
function letters(html) {
  return Array.from(html.matchAll(/<letter\b([^>]*)>([\s\S]*?)<\/letter>/g), ([, attributes, body]) => ({
    textUnits: units(body.includes('fa-level-down-alt') ? '↵' : body.includes('fa-long-arrow-alt-right') ? '→' : body),
    marked: /\bdead\b/.test(attributes), correct: /\bcorrect\b/.test(attributes),
    placeholder: /\binvisible\b/.test(attributes),
  }));
}
const fixtures = [], unicodeFixtures = [];
for (const [collection, values] of [[fixtures, samples], [unicodeFixtures, unicodeSamples]])
for (const mode of ['words', 'zen']) for (const style of ['off', 'below', 'replace'])
for (const [original, input, composition] of values) {
  let html = '', position;
  const word = {setHtml(value) { html = value; }, qsa: () => [], appendHtml() { assert.fail('Unexpected hints'); },
    native: {insertAdjacentHTML() {}, getElementsByTagName: () => []}};
  class ObservedCaret { goTo(value) { position = value; } }
  const context = vm.createContext({original, input, composition,
    Config: {mode, indicateTypos: 'off', compositionDisplay: style, tapeMode: 'off', showAllLines: true,
      caretStyle: 'bar', smoothCaret: 'off'},
    findSingleActiveFunboxWithFunction: () => undefined,
    requestDebouncedAnimationFrame: (_key, callback) => callback(), getWordElement: () => word,
    getActiveWordIndex: () => 0, getCurrentInput: () => input,
    isLanguageRightToLeft: () => false, isDirectionReversed: () => false,
    SlowTimer: {get: () => false}, Caret: ObservedCaret, qsr: () => ({}),
    CompositionState: {getData: () => composition}, configEvent: {subscribe() {}}});
  new vm.Script(javascript(source('utils/strings')) + '\nglobalThis.Strings = {splitIntoCharacters};\n' +
    javascript(source('test/test-words')) + '\nglobalThis.TestWords = {words};\n' + update + '\n' + caret)
    .runInContext(context, {timeout: 1000});
  const display = vm.runInContext('words.push(original, 0).display', context);
  await vm.runInContext('updateWordLetters({wordIndex: 0, input, compositionData: composition})', context);
  vm.runInContext('updatePosition(true)', context);
  assert.equal(position.wordIndex, 0); assert.equal(position.letterIndex, input.length + composition.length);
  const cells = letters(html), tail = cells.slice(Array.from(input).length);
  if (mode === 'words') assert.equal(tail.filter(value => value.marked).length, composition.length);
  if (mode === 'zen' && composition !== '') assert.ok(!cells.some(value => value.placeholder));
  collection.push({mode, style, display, input, composition, tail, letterIndex: position.letterIndex});
}
assert.equal(fixtures.length, 132); assert.equal(unicodeFixtures.length, 36);
const emoji = unicodeFixtures.find(value => value.mode === 'words' && value.style === 'replace'
  && value.input === 'a' && value.composition === '😀');
assert.deepEqual(emoji.tail.slice(0, 2).map(value => value.textUnits), [[0xD83D], [0xDE00]],
  'Pinned source splits ordinary marked emoji into surrogate cells; do not call this native grapheme parity');
verify();
if (option) process.stdout.write(JSON.stringify({pin, fixtures, unicodeFixtures}));
else console.log('Composition projection source passed (132 complete word-update/caret cases and 36 explicit Unicode cases; real Words/Strings, off/below/replace, Zen, overflow, controls, cancel; owned DOM/RAF and no browser geometry; source mixed UTF-16/scalar defects retained)');
