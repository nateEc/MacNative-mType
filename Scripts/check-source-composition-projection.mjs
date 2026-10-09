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
// Complete event getters consume explicit, owned input snapshots. This does
// not execute insertion/navigation, generation, live-cache math or browser IME.
const fieldSamples = [
  {words: ['abcdef ', 'gh ', 'ij'], accepted: 'a gXYZ', index: 1, snapshots: [[0, 'a '], [1, 'gXYZ']]},
  {words: ['a\n', '\n', 'b ', 'c'], accepted: 'a\n', index: 1, snapshots: [[0, 'a\n']]},
  {words: ['a\n', '\n', 'b ', 'c'], accepted: 'a\n\n', index: 2, snapshots: [[0, 'a\n'], [1, '\n']]},
  {words: ['a ', '\u0301b ', 'tail'], accepted: 'a ', index: 1, snapshots: [[0, 'a ']]},
  {words: ['ab', 'CD', 'xy'], hidden: true, accepted: 'abC', index: 1, snapshots: [[0, 'ab'], [1, 'C']]},
  {words: ['ab', '', 'xy'], hidden: true, accepted: 'ab', index: 1, snapshots: [[0, 'ab']]},
  {words: ['a', '\u0301b', 'tail'], hidden: true, accepted: 'a', index: 1, snapshots: [[0, 'a']]},
  {words: ['🇫', '🇷🇨', 'tail'], hidden: true, accepted: '🇫', index: 1, snapshots: [[0, '🇫']]},
  {words: ['🙂x', 'tail'], hidden: true, accepted: '🙃', stop: true, index: 0, snapshots: [[0, '\ud83d']]},
  {words: ['\n', 'a ', 'tail'], strict: true, accepted: '\n', index: 0, snapshots: [[0, '\n']]},
  {words: [], zen: true, accepted: 'one\n🙂', index: 1, snapshots: [[0, 'one\n'], [1, '🙂']]},
  {words: [], zen: true, accepted: '', index: 0, snapshots: []},
  {words: ['ab'], hidden: true, stop: true, accepted: 'abx', index: 0, snapshots: [[0, '']]},
  {words: ['a ', 'tail'], hidden: true, accepted: 'a', index: 0, snapshots: [[0, 'a']]},
  {words: ['', ''], hidden: true, accepted: '', index: 0, snapshots: []},
];
const fieldFixtures = [];
for (const sample of fieldSamples) {
  let html = '', position;
  const mode = sample.zen ? 'zen' : 'words';
  const context = vm.createContext({Config: {mode, indicateTypos: 'off', compositionDisplay: 'replace',
    tapeMode: 'off', showAllLines: true, caretStyle: 'bar', smoothCaret: 'off'},
    getActiveWordIndex: () => sample.index, isResultCalculating: () => false,
    roundTo2: value => Math.round(value * 100) / 100, isSafeNumber: Number.isFinite,
    recordEventForCache() {}, resetLiveCache() {}, console: {debug() {}},
    findSingleActiveFunboxWithFunction: () => undefined,
    requestDebouncedAnimationFrame: (_key, callback) => callback(),
    getWordElement: () => ({setHtml(value) {html = value;}, qsa: () => [],
      native: {insertAdjacentHTML() {}, getElementsByTagName: () => []}}),
    isLanguageRightToLeft: () => false, isDirectionReversed: () => false,
    SlowTimer: {get: () => false}, Caret: class {goTo(value) {position = value;}},
    qsr: () => ({}), CompositionState: {getData: () => 'XYZ'}, configEvent: {subscribe() {}}});
  new vm.Script(javascript(source('utils/strings')) + '\nglobalThis.Strings = {splitIntoCharacters};\n' +
    javascript(source('test/test-words')) + '\nglobalThis.TestWords = {words};\n' +
    javascript(source('test/events/helpers')) + '\n(() => {\n' + javascript(source('test/events/data')) +
    '\nObject.assign(globalThis, {getCurrentInput, logTestEvent});\n})();\n' +
    update + '\n' + caret).runInContext(context, {timeout: 1000});
  context.sample = sample;
  vm.runInContext('for (const word of sample.words) words.push(word, 0);' +
    'for (const [wordIndex, inputValue] of sample.snapshots) logTestEvent("input", 0,' +
    '{inputType: "insertText", wordIndex, inputValue, data: inputValue, correct: true});', context);
  const display = vm.runInContext('words.getCurrent()?.display ?? ""', context);
  const input = vm.runInContext('getCurrentInput()', context);
  await vm.runInContext('updateWordLetters({wordIndex: sample.index, input: getCurrentInput(), compositionData: "XYZ"})', context);
  vm.runInContext('updatePosition(true)', context);
  assert.equal(position.wordIndex, sample.index); assert.equal(position.letterIndex, input.length + 3);
  assert.ok(letters(html).some(value => value.marked));
  fieldFixtures.push({words: sample.words, hidden: sample.hidden ?? false, zen: sample.zen ?? false,
    strict: sample.strict ?? false, stop: sample.stop ?? false, accepted: sample.accepted,
    index: sample.index, targetUnits: units(display), inputUnits: units(input), letterIndex: position.letterIndex,
    marked: letters(html).filter(value => value.marked)});
}
assert.equal(fieldFixtures.length, 15);
assert.deepEqual(fieldFixtures[8].inputUnits, [55357], 'Never decode a retained lone surrogate into a replacement unit');
verify();
if (option) process.stdout.write(JSON.stringify({pin, fixtures, unicodeFixtures, fieldFixtures}));
else console.log('Composition projection source passed (132 complete word-update/caret cases, 36 explicit Unicode cases and 15 complete Words/event-getter/update/caret field cases; seeded snapshots and owned DOM/RAF/cache bindings, no insertion/navigation/browser/IME parity; source mixed UTF-16/scalar defects retained)');
