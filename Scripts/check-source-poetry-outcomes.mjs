// Execute the pinned provider itself with owned transport responses. No network
// request or upstream content/asset is stored in this repository.
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
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/test/poetry.ts'), 'utf8');
const cases = [
  {name: 'valid section', body: [{title: 'Owned', author: 'Fixture', lines: ['north south']}], words: ['north', 'south']},
  {name: 'decoded empty section', body: [{title: 'Owned', author: 'Fixture', lines: ['— _']}], words: []},
  {name: 'valid JSON on HTTP 404', status: 404, body: [{title: 'Owned', author: 'Fixture', lines: ['north south']}], words: ['north', 'south']},
  {name: 'empty section on HTTP 503', status: 503, body: [{title: 'Owned', author: 'Fixture', lines: ['— _']}], words: []},
  {name: 'empty response array', body: [], failure: true},
  {name: 'missing lines', body: [{title: 'Owned', author: 'Fixture'}], failure: true},
  {name: 'JSON rejection', jsonFailure: true, failure: true},
  {name: 'transport rejection', transportFailure: true, failure: true},
];
for (const fixture of cases) {
  let calls = 0;
  const context = vm.createContext({
    console: {log() {}},
    fetch: async url => {
      calls++;
      assert.equal(url, 'https://poetrydb.org/random');
      if (fixture.transportFailure) throw new Error('Owned transport failure');
      return {status: fixture.status ?? 200, ok: (fixture.status ?? 200) < 400, json: async () => {
        if (fixture.jsonFailure) throw new Error('Owned decoding failure');
        return fixture.body;
      }};
    },
  });
  const section = new vm.SyntheticModule(['Section'], function () {
    this.setExport('Section', class {
      constructor(title, author, words) { Object.assign(this, {title, author, words}); }
    });
  }, {context});
  const provider = new vm.SourceTextModule(stripTypeScriptTypes(source, {mode: 'transform'}), {context});
  await provider.link(specifier => {
    assert.equal(specifier, '../utils/json-data');
    return section;
  });
  await provider.evaluate();
  const outcome = await provider.namespace.getPoem();
  assert.equal(calls, 1);
  assert.notEqual(outcome, undefined);
  if (fixture.failure) assert.equal(outcome, false);
  else assert.deepEqual(Array.from(outcome.words), fixture.words);
  console.log(`PASS ${fixture.name}`);
}
console.log('Pinned poetry provider: 8 cases passed; HTTP status does not reject decoded sections; undefined is not a provider outcome in these cases.');
