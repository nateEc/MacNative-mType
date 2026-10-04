// Read-only execution of pinned account functions, not the full result controller.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const root = path.resolve(process.argv[2] ?? '');
const emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
const verify = () => {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
};
verify();
const dependencies = process.env.TYPEBAR_PRACTICE_SOURCE_DEPENDENCIES;
assert.ok(dependencies, 'Pinned date dependencies required; readiness gate prepares an isolated runtime');
const modules = path.join(dependencies, 'node_modules');
for (const [name, version] of [['date-fns', '3.6.0'], ['@date-fns/utc', '1.2.0']]) {
  assert.equal(JSON.parse(fs.readFileSync(path.join(modules, name, 'package.json'))).version, version);
  assert.ok(fs.readFileSync(path.join(root, 'backend/package.json'), 'utf8').includes(`"${name}": "${version}"`));
}
let nowMilliseconds = 0, user = {}, captured = null;
// A VM-local clock only; preserve Date.prototype for UTCDateMini's actual method mapping.
const clock = new Proxy(Date, {
  construct(target, args, newTarget) { return Reflect.construct(target, args.length ? args : [nowMilliseconds], newTarget); },
  get(target, key) { return key === 'now' ? () => nowMilliseconds : Reflect.get(target, key); },
});
const context = vm.createContext({Date: clock});
const cache = new Map();
function moduleAt(file) {
  file = path.resolve(file);
  if (cache.has(file)) return cache.get(file);
  const module = new vm.SourceTextModule(fs.readFileSync(file, 'utf8'), {context, identifier: file});
  cache.set(file, module);
  return module;
}
async function dependency(file) {
  const module = moduleAt(file);
  if (module.status === 'unlinked') await module.link((id, parent) => {
    assert.ok(id.startsWith('.'), 'Unexpected external dependency ' + id);
    return moduleAt(path.resolve(path.dirname(parent.identifier), id));
  });
  if (module.status !== 'evaluated') await module.evaluate();
  return module.namespace;
}
const Dates = {};
for (const name of ['startOfYear', 'subYears', 'getDaysInYear', 'startOfDay', 'addDays']) {
  Dates[name] = (await dependency(path.join(modules, 'date-fns', name + '.mjs')))[name];
}
const {UTCDateMini} = await dependency(path.join(modules, '@date-fns/utc/date/mini.mjs'));
const utilities = new vm.SourceTextModule(stripTypeScriptTypes(
  fs.readFileSync(path.join(root, 'packages/util/src/date-and-time.ts'), 'utf8'), {mode: 'transform'}), {context});
await utilities.link(() => { throw new Error('Unexpected date utility dependency'); });
await utilities.evaluate();
Object.assign(context, {Dates, UTCDateMini, isYesterday: utilities.namespace.isYesterday,
  isToday: utilities.namespace.isToday, getPartialUser: async () => structuredClone(user),
  addImportantLog: async () => {}, getUsersCollection: () => ({updateOne: async (_, changes) => {
    captured = JSON.parse(JSON.stringify(changes));
  }})});
function expose(relative, name) {
  const source = fs.readFileSync(path.join(root, relative), 'utf8');
  const matches = [...source.matchAll(new RegExp(`export (?:async )?function ${name}\\(`, 'g'))];
  assert.equal(matches.length, 1);
  const begin = matches[0].index, end = source.indexOf('\nexport ', begin + 1);
  assert.ok(end > begin);
  new vm.Script(stripTypeScriptTypes(source.slice(begin, end).replace(/^export /, ''), {mode: 'transform'})
    + `\nglobalThis.${name} = ${name};`, {filename: 'read-only-account-function'}).runInContext(context);
}
for (const name of ['updateStreak', 'setStreakHourOffset', 'updateTypingStats']) expose('backend/src/dal/user.ts', name);
expose('backend/src/api/controllers/user.ts', 'generateCurrentTestActivity');
const streakFixtures = [], activityFixtures = [], typingFixtures = [], boundaryFixtures = [];
for (const offsetHours of [-11, -0.5, 0, 0.5, 12]) {
  for (const now of [0, 1, 86_399_999, 86_400_000, 172_800_000, Date.UTC(2027, 0, 15, 0, 15)]) {
    for (const delta of [-2 * 86_400_000, -86_400_000, -1, 0, 1, 86_400_000]) {
      for (const length of [0, 3]) {
        nowMilliseconds = now;
        const prior = {length, maxLength: 5, lastResultTimestamp: now + delta, hourOffset: offsetHours};
        user = {streak: prior};
        await context.updateStreak('owned-account', now);
        streakFixtures.push({label: `${offsetHours}/${now}/${delta}/${length}`, prior, nowMilliseconds: now, streak: captured.$set.streak});
      }
    }
  }
  nowMilliseconds = Date.UTC(2027, 0, 15);
  user = {streak: {length: 3, maxLength: 5, lastResultTimestamp: 0}};
  await context.setStreakHourOffset('owned-account', offsetHours);
  assert.deepEqual(captured, {$set: {'streak.hourOffset': offsetHours, 'streak.lastResultTimestamp': nowMilliseconds}});
  boundaryFixtures.push({offsetHours, nowMilliseconds, update: captured});
}
for (const restarts of [0, 1, 100, 10_000]) for (const seconds of [0, 0.00025, 12.75, 3_600_000]) {
  await context.updateTypingStats('owned-account', restarts, seconds);
  assert.deepEqual(captured, {$inc: {startedTests: restarts + 1, completedTests: 1, timeTyping: seconds}});
  typingFixtures.push({restarts, seconds, update: captured.$inc});
}
for (const year of [1971, 2000, 2001, 2024, 2025, 2027]) {
  for (const month of [0, 1, 11]) for (const kind of ['none', 'previous', 'first', 'middle', 'last', 'both', 'old-only']) {
    nowMilliseconds = Date.UTC(year, month, 15);
    const days = Math.round((Date.UTC(year + 1, 0, 1) - Date.UTC(year, 0, 1)) / 86_400_000);
    const activityByYear = {};
    if (['previous', 'both'].includes(kind)) activityByYear[year - 1] = [1, null, 2];
    if (['first', 'both'].includes(kind)) activityByYear[year] = [2];
    if (kind === 'middle') activityByYear[year] = [...Array(59).fill(null), 3];
    if (kind === 'last') activityByYear[year] = [...Array(days - 1).fill(null), 1];
    if (kind === 'old-only') activityByYear[year - 2] = [1];
    const activity = context.generateCurrentTestActivity(structuredClone(activityByYear));
    activityFixtures.push({label: `${year}/${month}/${kind}`, nowMilliseconds, activityByYear,
      activity: activity === undefined ? null : JSON.parse(JSON.stringify(activity))});
  }
}
verify();
if (emit) process.stdout.write(JSON.stringify({referenceCommit: pin, streakFixtures, activityFixtures, typingFixtures, boundaryFixtures}));
else console.log(`Pinned account source passed: ${streakFixtures.length} streak, ${activityFixtures.length} activity, ${typingFixtures.length} typing, ${boundaryFixtures.length} boundary fixtures`);
