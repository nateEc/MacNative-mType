// QA only: complete pinned lookup and percentage functions, owned DAL fixtures.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
function section(file, start, end) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  assert.equal(source.split(start).length, 2);
  const begin = source.indexOf(start), finish = source.indexOf(end, begin);
  assert.ok(finish > begin);
  return source.slice(begin, finish);
}
function run(code, context) {
  new vm.Script(stripTypeScriptTypes(code.replace(/^export /gm, ''), {mode: 'transform'}))
    .runInContext(context, {timeout: 1000});
}
verify();
const context = vm.createContext({});
run(section('backend/src/api/controllers/user.ts', 'async function getAllTimeLbs(',
  '\nexport function generateCurrentTestActivity(') + '\nglobalThis.lookup = getAllTimeLbs;', context);
run(section('packages/util/src/numbers.ts', 'export function roundTo2(', '\n}\n') + '\n}', context);
run(section('frontend/src/ts/utils/misc.ts', 'export function formatTopPercentage(',
  '\nexport function formatTypingStatsRatio(') + '\nglobalThis.format = formatTopPercentage;', context);
const profile = allTimeLbs => ({id: '11111111-1111-4111-8111-111111111111', displayName: 'Owned ranking profile',
  joinedAt: 0, completedResultCount: 0, bestWPM: 0, leaderboardOptedOut: false, allTimeLbs});
const projections = [], formats = [], states = [null, false, {}, {rank: 1}, {rank: 2}];
for (const first of states) for (const second of states) {
  const calls = [];
  context.LeaderboardsDAL = {
    getRank: async (...args) => { calls.push(['rank', ...args]); return args[1] === '15' ? first : second; },
    getCount: async (...args) => { calls.push(['count', ...args]); return 3; }
  };
  const allTimeLbs = await context.lookup('owned-user');
  assert.deepEqual(calls, [['rank', 'time', '15', 'english', 'owned-user'], ['count', 'time', '15', 'english'],
    ['rank', 'time', '60', 'english', 'owned-user'], ['count', 'time', '60', 'english']]);
  const parameters = [15, 60].filter(seconds => allTimeLbs.time[String(seconds)].english !== undefined);
  projections.push({profile: profile(allTimeLbs), parameters,
    ranks: parameters.map(seconds => allTimeLbs.time[String(seconds)].english.rank ?? null)});
}
for (const count of [1, 3, 100, 100000]) for (const rank of [undefined, 0, 1, 2, 11, 123]) {
  const position = {count, ...(rank === undefined ? {} : {rank})};
  formats.push({profile: profile({time: {'15': {english: position}}}), expected: context.format(position)});
}
verify();
if (emit) process.stdout.write(JSON.stringify({projections, formats}));
else console.log('pinned complete profile rank lookup/percentage passed (25 owned DAL projections, 24 formats; no MongoDB/Solid/JSX/DOM/HTTP)');
