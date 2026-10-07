// QA only: complete pinned before-input, validation, normalization, strings,
// words and SlowTimer modules. Geometry is controlled, not browser evidence.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const [argument, option] = process.argv.slice(2);
assert.ok(argument && (!option || option === '--emit-fixtures'));
const root = path.resolve(argument);
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const configurations = [
  {}, {blindMode: true}, {hideExtraLetters: true}, {slow: true},
  {deleteOnError: 'letter_hard'}, {deleteOnError: 'word_hard'},
  {deleteOnError: 'letter'}, {deleteOnError: 'word'},
  {stopOnError: 'word'}, {stopOnError: 'letter'}, {strictSpace: true}, {mode: 'zen'},
];
const cases = [];
for (const changes of configurations) for (const input of ['a', 'ab', 'ax', 'abx']) {
  // Soft/hard deletion and letter-stop cannot establish a wrong prefix.
  if ((changes.deleteOnError || changes.stopOnError === 'letter') && !['a', 'ab'].includes(input)) continue;
  for (const data of ['x', ' ', '\u3000', '\n']) for (const growth of ['none', 'top', 'height']) {
    const Config = {mode: 'words', difficulty: 'normal', deleteOnError: 'off', stopOnError: 'off',
      strictSpace: false, blindMode: false, hideExtraLetters: false, language: 'english', ...changes};
    let probes = 0, candidate = null;
    const context = vm.createContext({console: {error() {}}});
    const adapters = {
      // Language is used only in erased type annotations in strings.ts.
      '@monkeytype/schemas/languages': {Language: undefined},
      'config/store': {Config},
      'test/funbox/list': {isFunboxActiveWithProperty: () => false},
      'input/input-element': {getInputElementValue: () => ({inputValue: input})},
      'input/state': {isAwaitingNextWord: () => false},
      'states/test': {isTestRestarting: () => false, getActiveWordIndex: () => 0,
        isResultCalculating: () => false, wordsHaveNewline: () => true},
      'test/events/data': {getCurrentInput: () => input},
      'test/test-ui': {pendingWordData: new Map(), activeWordTop: 20, activeWordHeight: 30,
        getActiveWordTopAndHeightWithDifferentData: value => {
          probes++; candidate = value;
          return {top: growth === 'top' ? 21 : 20, height: growth === 'height' ? 31 : 30};
        }},
    };
    const cache = new Map();
    function moduleFor(id) {
      if (cache.has(id)) return cache.get(id);
      let module;
      if (adapters[id]) {
        const bindings = adapters[id];
        module = new vm.SyntheticModule(Object.keys(bindings), function() {
          for (const [key, value] of Object.entries(bindings)) this.setExport(key, value);
        }, {identifier: id, context});
      } else {
        assert.ok(['input/handlers/before-insert-text', 'input/helpers/validation', 'input/helpers/util',
          'utils/strings', 'test/test-words', 'legacy-states/slow-timer'].includes(id), 'Unexpected module: ' + id);
        module = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(
          path.join(root, 'frontend/src/ts', id + '.ts'), 'utf8'), {mode: 'transform'}), {identifier: id, context});
      }
      cache.set(id, module); return module;
    }
    const entry = moduleFor('input/handlers/before-insert-text');
    await entry.link((specifier, parent) => moduleFor(specifier.startsWith('.')
      ? path.posix.normalize(path.posix.join(path.posix.dirname(parent.identifier), specifier)) : specifier));
    await entry.evaluate();
    const words = cache.get('test/test-words').namespace.words;
    words.push('ab ', 0);
    if (changes.slow) cache.get('legacy-states/slow-timer').namespace.set();
    const prevented = entry.namespace.onBeforeInsertText(data);
    assert.ok(probes <= 1);
    if (probes) assert.equal(prevented, growth !== 'none');
    cases.push({changes, input, data, growth, probes, candidate, prevented});
  }
}
assert.equal(cases.length, 456);
assert.ok(cases.some(test => test.probes && test.prevented));
verify();
if (option) console.log(JSON.stringify(cases));
else console.log('Input wrap source passed: 456 reachable-field complete-module cases; actual normalization/commit/word-display/SlowTimer dependencies; controlled geometry only, no DOM/font/event-queue equivalence claim');
