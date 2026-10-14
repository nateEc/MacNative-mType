// Execute the pinned addWord caller with owned section and generator outcomes.
// Provider transport and generator internals remain explicit adapter boundaries.
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
const begin = source.indexOf('export async function addWord(): Promise<void> {');
const end = source.indexOf('type RetrySaving = {', begin);
assert.ok(begin >= 0 && end > begin);
const actualCaller = stripTypeScriptTypes(source.slice(begin, end), {mode: 'transform'});

const cases = [
  {name: 'empty side section still generates', section: {words: []}, next: 'harbor',
    pulls: 1, generates: 1, added: ['harbor'], toggles: 0, restarts: 0, failures: 0},
  {name: 'empty side and failed generation report failure', section: {words: []},
    pulls: 1, generates: 1, added: [], toggles: 0, restarts: 0, failures: 1},
  {name: 'false side section disables and restarts', section: false,
    pulls: 1, generates: 0, added: [], toggles: 1, restarts: 1, failures: 0},
  {name: 'undefined side section returns without generation', section: undefined,
    pulls: 1, generates: 0, added: [], toggles: 0, restarts: 0, failures: 0},
  {name: 'valid side section adds fields before generator word',
    section: {words: ['north', 'south']}, next: 'harbor',
    pulls: 1, generates: 1, added: ['north ', 'south ', 'harbor'], toggles: 0, restarts: 0, failures: 0},
];

for (const fixture of cases) {
  let pulls = 0, generates = 0, toggles = 0, restarts = 0, failures = 0;
  const added = [];
  const records = Array.from({length: 19}, (_, index) => ({text: `owned${index} `}));
  records.get = index => records[index];
  records.push = (word, sectionIndex) => {
    const record = {text: word, display: word, sectionIndex};
    Array.prototype.push.call(records, record);
    return record;
  };
  const funbox = {name: 'poetry', functions: {pullSection: async () => {
    pulls++;
    return fixture.section;
  }}};
  const context = vm.createContext({
    Config: {mode: 'words', words: 300, language: 'english'},
    getActiveWordIndex: () => 0,
    getActiveFunboxes: () => [],
    findSingleActiveFunboxWithFunction: name => name === 'pullSection' ? funbox : undefined,
    TestWords: {words: records},
    TestUI: {addWord: word => added.push(word), appendEmptyWordElement: () => {
      throw new Error('Zen branch unexpectedly entered');
    }},
    WordsGenerator: {
      areAllWordsGenerated: () => false,
      appendCommitCharacter: word => `${word} `,
      getNextWord: async () => {
        generates++;
        if (fixture.next === undefined) throw new Error('Owned generator failure');
        return {word: fixture.next, sectionIndex: 0};
      },
    },
    toggleFunbox: name => { assert.equal(name, 'poetry'); toggles++; },
    restart: async () => { restarts++; },
    timerEvent: {dispatch: event => {
      assert.equal(event.key, 'fail');
      assert.equal(event.value, 'word generation error');
      failures++;
    }},
    showErrorNotification: () => {},
    console: {debug: () => {}},
  });
  const module = new vm.SourceTextModule(actualCaller, {context});
  await module.link(() => { throw new Error('Unexpected import'); });
  await module.evaluate();
  await module.namespace.addWord();
  assert.deepEqual({pulls, generates, added, toggles, restarts, failures}, {
    pulls: fixture.pulls, generates: fixture.generates, added: fixture.added,
    toggles: fixture.toggles, restarts: fixture.restarts, failures: fixture.failures,
  }, fixture.name);
  console.log(`PASS ${fixture.name}`);
}
console.log(`Complete pinned addWord caller: ${cases.length} cases passed; provider and generator internals are adapter boundaries.`);
