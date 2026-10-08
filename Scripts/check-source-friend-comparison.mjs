// QA only. Actual pinned DAL produces the expression; a bounded owned adapter
// interprets its PB reducer. This is NOT MongoDB, TanStack sorting or Solid UI.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(), '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function between(source, start, end) {
  assert.equal(source.split(start).length, 2);
  const offset = source.indexOf(start), finish = source.indexOf(end, offset);
  assert.ok(finish > offset); return source.slice(offset, finish);
}
const context = vm.createContext({aggregateWithAcceptedConnections: (options, pipeline) => {
  context.options = options; context.pipeline = pipeline; return [];
}, isSafeNumber: value => typeof value === 'number' && Number.isFinite(value)});
function run(code) {
  new vm.Script(stripTypeScriptTypes(code.replace(/^export /gm, ''), {mode:'transform'}))
    .runInContext(context, {timeout:1000});
}
run(between(read('backend/src/dal/user.ts'), 'export async function getFriends(', '\nfunction migrateUser<') + '\nglobalThis.getFriends = getFriends;');
await context.getFriends('owned-user');
assert.equal(context.options.includeMetaData, true);
assert.equal(context.options.collectionName, 'users');
const expressions = context.pipeline[1].$addFields;
// Fail closed if the actual projection gains any unimplemented operator.
function evaluate(expression, document, variables = {}) {
  if (typeof expression === 'string' && expression.startsWith('$')) {
    const variable = expression.startsWith('$$'), segments = expression.slice(variable ? 2 : 1).split('.');
    return segments.reduce((value, segment) => value?.[segment], variable ? variables : document);
  }
  if (expression === null || typeof expression !== 'object') return expression;
  if (Array.isArray(expression)) return expression.map(value => evaluate(value, document, variables));
  const entries = Object.entries(expression);
  if (entries.length === 0) return {};
  assert.equal(entries.length, 1);
  const [operator, value] = entries[0];
  if (operator === '$reduce') {
    const input = evaluate(value.input, document, variables);
    if (input == null) return null;
    return input.reduce((selected, item) => evaluate(value.in, document, {...variables, this:item, value:selected}), evaluate(value.initialValue, document, variables));
  }
  if (operator === '$cond') {
    assert.ok(Array.isArray(value));
    return evaluate(value[evaluate(value[0], document, variables) ? 1 : 2], document, variables);
  }
  if (operator === '$gte') {
    const [left, right] = evaluate(value, document, variables);
    // Owned fixtures contain only finite numeric WPM; missing initial WPM is
    // lower than a numeric value. No claim about general BSON comparison order.
    assert.ok(typeof left === 'number' && Number.isFinite(left));
    assert.ok(right === undefined || (typeof right === 'number' && Number.isFinite(right)));
    return right === undefined || left >= right;
  }
  assert.fail(`Unsupported reducer operator ${operator}`);
}
const fixtures = [];
for (const legacy of [false, true, 'withoutMode2']) for (const count of [0, 1, 2, 8, 25, 80]) {
  const rows = Array.from({length:count}, (_, index) => {
    const speed = [0, 0.01, 60.49, 60.49, 80.5][index % 5], seconds = index % 3 === 0 ? 60 : 15;
    return {id:`00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`, mode:'time', mode2:String(seconds),
      durationSeconds:seconds, language:`owned_${index}`, wpm:Math.round(speed), preciseWpm:speed,
      accuracy:99, preciseAccuracy:98.75, consistency:80.25, finishedAt:index,
      rawWpm:120, preciseRawWpm:120, acceptedAtMilliseconds:1800000000000+index, personalBestOrigin:'accepted',
      personalBestConfiguration:{version:1,difficulty:'normal',punctuation:false,numbers:false,lazyMode:false}};
  });
  const document = {personalBests:{time:{}}};
  for (const seconds of [15, 60]) document.personalBests.time[seconds] = rows.filter(row => row.durationSeconds === seconds).map(row => ({...row,wpm:row.preciseWpm}));
  const top15 = evaluate(expressions.top15, document)?.id ?? null, top60 = evaluate(expressions.top60, document)?.id ?? null;
  if (legacy) for (const row of rows) {
    for (const key of ['rawWpm','preciseRawWpm','acceptedAtMilliseconds','personalBestOrigin','personalBestConfiguration']) delete row[key];
    if (legacy === 'withoutMode2') delete row.mode2;
  }
  const profile = {id:'11111111-1111-4111-8111-111111111111',displayName:'Owned friend',joinedAt:0,completedResultCount:0,bestWPM:0,personalBests:rows};
  if (!legacy) Object.assign(profile,{personalBests:[],personalBestLedgerVersion:1,personalBestHistoryComplete:true,personalBestSnapshots:rows});
  fixtures.push({profile,top15,top60});
}
run(between(read('frontend/src/ts/components/pages/connections/FriendsList.tsx'), 'function formatStreak(', '\nfunction formatPb(') + '\nglobalThis.formatStreak = formatStreak;');
for (const [days, expected] of [[undefined,'-'],[0,'0 days'],[1,'-'],[2,'2 days'],[12,'12 days']]) assert.equal(context.formatStreak(days), expected);
run(between(read('frontend/src/ts/utils/misc.ts'), 'export function formatTypingStatsRatio(', '\nexport function addToGlobal(') + '\nglobalThis.ratio = formatTypingStatsRatio;');
assert.equal(context.ratio({startedTests:3,completedTests:2}).restartRatio, '0.5');
assert.equal(context.ratio({startedTests:3,completedTests:2}).completedPercentage, '66');
assert.equal(context.ratio({startedTests:3,completedTests:0}).restartRatio, 'Infinity');
verify();
if (emit) process.stdout.write(JSON.stringify(fixtures));
else console.log('Friend comparison source passed (18 actual DAL PB-expression fixtures; full actual streak/ratio helpers; bounded owned expression adapter, not MongoDB/TanStack/Solid/HTTP)');
