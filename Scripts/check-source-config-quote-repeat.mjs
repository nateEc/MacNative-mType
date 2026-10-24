// QA only: execute the complete pinned getQuoteWordList function's repeat
// branch with an owned synthetic pool. No source data or implementation is
// bundled in the product. This is not the full generator or browser lifecycle.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {stripTypeScriptTypes} from 'node:module';

assert.ok(process.argv[2], 'Read-only pinned reference required');
const root = path.resolve(process.argv[2]);
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/test/words-generator.ts'), 'utf8');
const start = source.indexOf('async function getQuoteWordList(');
const end = source.indexOf('\nlet currentWordset:', start);
assert.ok(start >= 0 && end > start, 'Pinned complete function boundaries changed');
const code = stripTypeScriptTypes(source.slice(start, end), {mode: 'transform'});
class WordGenError extends Error {}
let fixtures = 0;
for (const language of ['english', 'spanish']) {
  for (const quoteLength of [[0], [3], [0, 0, 1]]) {
    for (const wordOrder of [undefined, 'reverse']) {
      for (const previousQuote of [null, {id: 'owned'}]) {
        const words = ['ab', 'cd'];
        let selected = Symbol('not selected');
        const result = await vm.runInNewContext(code + '\ngetQuoteWordList(language, wordOrder)', {
          Config: {mode: 'quote', language, quoteLength}, language: {name: language}, wordOrder,
          isRepeated: () => true, currentWordset: {words}, previousRandomQuote: previousQuote,
          setCurrentQuote: quote => { selected = quote; }, WordGenError,
          QuotesController: {getQuotes: () => { throw Error('Repeat must not request a catalog'); }},
        });
        assert.equal(selected, previousQuote);
        assert.equal(result, words, 'Repeat uses the owned pool, not a copy of display text');
        assert.deepEqual(result, wordOrder === 'reverse' ? ['cd', 'ab'] : ['ab', 'cd']);
        fixtures++;
      }
    }
  }
}
await assert.rejects(vm.runInNewContext(code + '\ngetQuoteWordList(language)', {
  language: {name: 'english'}, isRepeated: () => true, currentWordset: null, WordGenError,
}), {message: 'Current wordset is null'});
verify();
process.stdout.write(JSON.stringify({fixtures, nullWordset: 1}) + '\n');
