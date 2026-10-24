// QA only. Execute the pinned complete getNextWord function, stopping at the
// first fresh-generation dependency. Controlled owned history; no word assets,
// browser, storage or full generation evidence is implied.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {stripTypeScriptTypes} from 'node:module';
assert.ok(process.argv[2], 'Pinned read-only reference required');
const root = path.resolve(process.argv[2]);
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/test/words-generator.ts'), 'utf8');
const start = source.indexOf('export async function getNextWord(');
const end = source.indexOf('\n/**\n * Appends the inter-word commit', start);
assert.ok(start >= 0 && end > start, 'Pinned complete function boundaries changed');
const code = stripTypeScriptTypes(source.slice(start, end).replace(/^export /, ''), {mode: 'transform'});
class WordGenError extends Error {}
const fresh = Symbol('fresh generation boundary');
const fixtures = [];
for (const [mode, customMode] of [['words', 'word'], ['time', 'time'], ['custom', 'time'], ['custom', 'word'], ['custom', 'section']]) {
  for (const limit of [0, 1, 3]) for (const index of [0, 1, 2, 3]) {
    const history = [{word: 'Ab ', wordRaw: 'Ab', sectionIndex: 40}, {word: 'cd\n', wordRaw: 'cd', sectionIndex: 41}];
    const context = vm.createContext({
      console: {debug() {}}, Config: {mode, words: limit},
      currentWordset: {}, currentLanguage: {}, isRepeated: () => true,
      previousGetNextWordReturns: history, sectionIndex: index, index, WordGenError,
      CustomText: {getLimitMode: () => customMode, getLimitValue: () => limit},
      getFunboxWordsFrequency: () => { throw fresh; },
    });
    let outcome;
    try {
      const result = await vm.runInContext(code + '\ngetNextWord(index, 100, "before", "earlier")', context);
      assert.equal(result, history[index]);
      assert.equal(context.sectionIndex, index + 1);
      outcome = 'cached';
    } catch (error) {
      if (error === fresh) outcome = 'fresh';
      else { assert.equal(error.message, 'Repeated word is undefined'); outcome = 'unavailable'; }
    }
    fixtures.push({mode, customMode, limit, index, outcome});
  }
}
verify();
process.stdout.write(JSON.stringify({fixtures}) + '\n');
