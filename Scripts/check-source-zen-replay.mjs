// Six complete pinned modules execute in memory. DOM, event storage and sound
// are bounded adapters; no native dependency or reference asset is packaged.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? '');
assert.ok(process.argv[2]);
assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
  '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
class Element {
  children = []; names = new Set(); text = ''; parent = null;
  get className() { return [...this.names].join(' '); }
  set className(value) { this.names = new Set(value.split(' ').filter(Boolean)); }
  get classList() { return {add: name => this.names.add(name), remove: name => this.names.delete(name),
    contains: name => this.names.has(name)}; }
  set innerHTML(value) { this.text = value; this.children = []; }
  appendChild(child) { child.parent = this; this.children.push(child); }
  remove() { this.parent.children = this.parent.children.filter(child => child !== this); }
}
let events = [], sounds = [];
const holder = new Element();
const selector = {on() {}, onChild() {}, setText() {}};
globalThis.document = {getElementById: id => id === 'replayWords' ? holder : null, createElement: () => new Element()};
const actual = new Set(['test/replay-ui', 'test/events/stats', 'test/events/helpers',
  'utils/strings', 'utils/numbers', '@monkeytype/util/numbers']);
const modules = new Map();
const eventLog = () => ({events, context: {mode: 'zen', mode2: 'zen', bailedOut: false,
  koreanStatus: false, targetWords: []}});
const bindings = {
  'config/store': {Config: {mode: 'zen', funbox: [], playSoundOnError: 'error'}},
  'constants/keys': {Keycode: {}}, '@monkeytype/schemas/languages': {Language: {}},
  'test/events/types': {InputEventNoMs: {}, TestEventNoMs: {}, EventLog: {}},
  'hangul-js': {default: {disassemble() { throw Error('No target Korean disassembly permitted'); }}},
  'controllers/sound-controller': {playClick: () => sounds.push('click'), playError: () => sounds.push('error')},
  'utils/arrays': {lastElementFromArray: values => values.at(-1)},
  'utils/dom': {qs: () => selector, qsr: () => selector},
  'test/test-words': {words: {get() { throw Error('Zen must not consult target words'); }}},
  'test/events/data': {getAllTestEvents: () => events, buildEventLog: eventLog,
    getInputForWord: index => {
      const helpers = modules.get('test/events/helpers').namespace;
      return helpers.getInputFromDom(helpers.getEventsForWord(events, index));
    }},
};
// Test-only bridge to private state, not a substitute behavior implementation.
const bridge = `export const ownedProbe = {
  prepare(){wordsList=getWordsList();replayData=deriveReplayActions();wordPos=0;curPos=0;initializeReplayPrompt();},
  actions(){return replayData;},
  applyThrough(time){for(const action of replayData){if(action.time<=time)handleDisplayLogic(action);}},
  seek(word,position){targetWordPos=word;targetCurPos=position;initializeReplayPrompt();return loadOldReplay();},
  frame(){return {word:wordPos,position:curPos,fields:[...document.getElementById('replayWords').children].map(word=>({error:word.classList.contains('error'),letters:[...word.children].map(letter=>({text:letter.text,classes:letter.className}))}))};}
};`;
function moduleFor(id) {
  if (modules.has(id)) return modules.get(id);
  let mod;
  if (actual.has(id)) {
    const file = id === '@monkeytype/util/numbers' ? path.join(root, 'packages/util/src/numbers.ts')
      : path.join(root, 'frontend/src/ts', id + '.ts');
    // Remove only an erased imported type which single-file stripping retains.
    const source = fs.readFileSync(file, 'utf8')
      .replace('import { CharCounts, countChars, isSpace }', 'import { countChars, isSpace }');
    mod = new vm.SourceTextModule(stripTypeScriptTypes(source, {mode: 'transform'})
      + (id === 'test/replay-ui' ? '\n' + bridge : ''), {identifier: id});
  } else {
    assert.ok(bindings[id], 'Unknown adapter: ' + id);
    const values = bindings[id];
    mod = new vm.SyntheticModule(Object.keys(values), function () {
      for (const [name, value] of Object.entries(values)) this.setExport(name, value);
    }, {identifier: id});
  }
  modules.set(id, mod); return mod;
}
const main = moduleFor('test/replay-ui');
await main.link((id, from) => moduleFor(id.startsWith('.')
  ? path.posix.normalize(path.posix.join(path.posix.dirname(from.identifier), id)) : id));
await main.evaluate();
const probe = main.namespace.ownedProbe;
const stats = modules.get('test/events/stats').namespace;
const insert = (wordIndex, inputValue, data, testMs = 0, inputStopped = false) =>
  ({type: 'input', testMs, data: {wordIndex, inputValue, data, inputType: 'insertText', correct: true, inputStopped}});
const deletion = (wordIndex, inputValue, testMs, clearedNextWord = false) =>
  ({type: 'input', testMs, data: {wordIndex, inputValue, data: '', inputType: 'deleteContentBackward', clearedNextWord}});
function prepare(tape) { events = tape; sounds = []; probe.prepare(); }
const text = frame => frame.fields.map(field => field.letters.map(letter => letter.text).join('')).join('');
const marks = frame => frame.fields.flatMap(field => field.letters.map(letter => letter.classes));
let count = 0;
const opening = [insert(0, 'a', 'a'), insert(0, 'a ', ' '), insert(1, 'b', 'b')];
prepare(opening);
assert.deepEqual(stats.getInputHistory(eventLog()), ['a ', 'b']);
assert.equal(text(probe.frame()), 'a b'); assert.deepEqual(marks(probe.frame()), ['', '', '']);
probe.applyThrough(0); assert.deepEqual(marks(probe.frame()), ['correct', 'correct', 'correct']);
assert.deepEqual(sounds, ['click', 'click', 'click', 'click']); count++;
prepare(opening); assert.equal(probe.seek(1, 0), 3); assert.equal(probe.frame().position, 0);
assert.deepEqual(sounds, []); count++;
prepare([insert(0, 'a', 'a'), insert(0, 'ab', 'b', 1), deletion(0, 'a', 2), insert(0, 'ac', 'c', 3)]);
assert.equal(text(probe.frame()), 'ac'); probe.applyThrough(2);
assert.deepEqual(marks(probe.frame()), ['correct', '']); assert.equal(probe.frame().position, 1);
assert.deepEqual(sounds, ['click', 'click', 'click']); count++;
prepare([insert(0, '', 'x', 0, true)]); probe.applyThrough(1);
assert.equal(text(probe.frame()), ''); assert.deepEqual(probe.actions(), []); assert.deepEqual(sounds, []); count++;
prepare([insert(0, 'a ', 'a '), insert(1, '', 'x', 1, true)]); probe.applyThrough(1);
assert.deepEqual([probe.frame().word, probe.frame().position], [1, 0]);
assert.deepEqual(sounds, ['click', 'click']); count++;
for (const spelling of ['🙂', 'e\u0301', '\t', '\r\n', '']) {
  prepare([insert(0, spelling, spelling)]);
  assert.equal(text(probe.frame()), spelling); probe.applyThrough(0);
  // The source operates on rendered letters, not a new grapheme cursor.
  assert.equal(probe.frame().position, 1); count++;
}
prepare([...opening, deletion(0, 'a', 1, true)]);
assert.deepEqual(stats.getInputHistory(eventLog()), ['a', '']);
assert.equal(probe.frame().fields.length, 1); probe.applyThrough(1);
assert.deepEqual([probe.frame().word, probe.frame().position], [1, 0]); // missing active word ignores retreat
assert.ok(!probe.frame().fields[0].error); count++;
prepare([insert(0, 'a', 'a'), insert(2, 'b', 'b', 1)]); probe.applyThrough(1);
assert.deepEqual(stats.getInputHistory(eventLog()), ['a', 'b']);
assert.deepEqual([probe.frame().word, probe.frame().position], [1, 1]); count++;
prepare([insert(0, 'a', 'a'), insert(1, '', '', 1)]); probe.applyThrough(1);
assert.deepEqual(stats.getInputHistory(eventLog()), ['a', '']);
assert.deepEqual([probe.frame().word, probe.frame().position], [1, 1]);
assert.deepEqual(sounds, ['click', 'click', 'click']); count++;
console.log(`${count} owned Zen replay fixtures passed (six complete actual modules; real history/action/display/seek functions, explicit DOM/storage/sound adapters, no browser/timer/IME/audio or native UI claim).`);
