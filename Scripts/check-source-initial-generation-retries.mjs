// Execute the complete pinned init function; generator outcomes and UI are
// owned adapters. This proves caller retry semantics, not provider networking.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

assert.ok(process.argv[2], 'Reference checkout required');
const root = path.resolve(process.argv[2]);
assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
  '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/test/test-logic.ts'), 'utf8');
const begin = source.indexOf('async function init(): Promise<boolean> {');
const end = source.indexOf('//add word during the test', begin);
assert.ok(begin >= 0 && end > begin);
const actualInit = stripTypeScriptTypes(source.slice(begin, end), {mode: 'transform'});

const results = [];
for (const fixture of [
  {name: 'three rejected generations', outcomes: ['reject', 'reject', 'reject'], success: false},
  {name: 'empty and rejected generations share the bound', outcomes: ['empty', 'reject', 'empty'], success: false},
  {name: 'third generation recovers', outcomes: ['reject', 'empty', 'valid'], success: true},
  {name: 'blank WordGenError suppresses its notice', outcomes: ['blank', 'reject', 'valid'], success: true},
  {name: 'blank WordGenError still reaches final failure', outcomes: ['blank', 'blank', 'blank'], success: false},
]) {
  let calls = 0, resets = 0, failureViews = 0, captured = 0, notices = 0, errors = 0;
  let words = [];
  const restarting = [];
  const notifications = [], finalErrors = [], capturedMessages = [];
  const config = {mode: 'words', words: 2, language: 'english', lazyMode: false,
    keymapMode: 'off', funbox: ['wikipedia']};
  class WordGenError extends Error {}
  const noop = () => {};
  const context = vm.createContext({
    Error, WordGenError, Config: config, console: {debug: noop, log: noop, error: noop},
    Sentry: {captureException: error => { captured++; capturedMessages.push(error.message); }},
    TestInitFailed: {showError: message => finalErrors.push(message),
      show: () => { failureViews++; }},
    setIsTestRestarting: value => restarting.push(value),
    TestWords: {words: {
      reset: () => { resets++; words = []; },
      push: word => words.push(word), get: () => words,
      getCurrent: () => words.length ? {text: words[0]} : undefined,
      removeCommitCharacterFromLastWord: noop,
    }},
    resetActiveWordIndex: noop, showLoaderBar: noop, hideLoaderBar: noop,
    tryCatch: async promise => ({data: await promise, error: null}),
    JSONData: {getLanguage: async () => ({name: 'english', words: ['owned'], noLazyMode: false})},
    getActivePage: () => 'test', Funbox: {activate: async () => {}, toggleScript: noop},
    getActiveFunboxNames: () => ['wikipedia'],
    LazyModeState: {getRemember: () => false, setRemember: noop},
    CustomText: {getData: () => ({}), getText: () => []},
    Misc: {getMode2: () => '2'}, getCurrentQuote: () => null,
    showErrorNotification: (message, options) => {
      errors++; notifications.push({level:'error', message, important:options.important, reason:options.error?.message});
    },
    showNoticeNotification: (message, options) => {
      notices++; notifications.push({level:'notice', message, important:options.important});
    },
    WordsGenerator: {
      generateWords: async () => {
        assert.ok(calls < fixture.outcomes.length, 'No fourth generation is allowed');
        const outcome = fixture.outcomes[calls++];
        if (outcome === 'reject') throw new Error('Owned generation rejection');
        if (outcome === 'empty') throw new WordGenError('Owned empty generation');
        if (outcome === 'blank') throw new WordGenError('');
        return {words: ['north ', 'south'], sectionIndexes: [0, 0], hasTab: false, hasNewline: false};
      },
      areAllWordsGenerated: () => true,
    },
    setWordsHaveNumbers: noop, setWordsHaveTab: noop, setWordsHaveNewline: noop,
    TestUI: {setJoiningClass: noop}, setIsLanguageRightToLeft: noop,
    setIsDirectionReversed: noop, isFunboxActiveWithProperty: () => false,
  });
  const module = new vm.SourceTextModule(
    'let lastInitError = null; let showedLazyModeNotification = false; let testReinitCount = 0;\n'
      + actualInit + '\nexport {init};', {context});
  await module.link(() => { throw new Error('Unexpected import'); });
  await module.evaluate();
  assert.equal(await module.namespace.init(), fixture.success);
  assert.equal(calls, 3);
  assert.equal(resets, 3);
  assert.equal(failureViews, fixture.success ? 0 : 1);
  assert.equal(captured, fixture.success ? 0 : 1);
  assert.deepEqual(restarting, fixture.success ? [] : [false]);
  const failedOutcomes = fixture.outcomes.filter(value => value !== 'valid');
  const visibleOutcomes = failedOutcomes.filter(value => value !== 'blank');
  assert.equal(errors + notices, visibleOutcomes.length);
  assert.deepEqual(notifications.map(value => value.level), visibleOutcomes.map(value => value === 'reject' ? 'error' : 'notice'));
  assert.ok(notifications.every(value => value.important === true));
  const lastMessage = {reject:'Owned generation rejection', empty:'Owned empty generation', blank:''}[failedOutcomes.at(-1)];
  assert.deepEqual(capturedMessages, fixture.success ? [] : [lastMessage]);
  assert.deepEqual(finalErrors, fixture.success ? [] : [`Error: ${lastMessage}`]);
  assert.deepEqual(words, fixture.success ? ['north ', 'south'] : []);
  assert.deepEqual(config.funbox, ['wikipedia']);
  results.push({name:fixture.name, outcomes:fixture.outcomes, success:fixture.success, calls, notifications, finalErrors, capturedMessages});
  if (!process.argv.includes('--json')) console.log(`PASS ${fixture.name}`);
}
if (process.argv.includes('--json')) console.log(JSON.stringify({cases:results}));
else console.log('Complete pinned init: 5 caller retry/feedback cases passed; networking and generator implementation are adapter boundaries.');
