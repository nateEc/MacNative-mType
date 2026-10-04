// Read-only execution of the actual private XP function and its numeric/date/
// funbox dependencies. This is not execution of the backend result controller.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const root = path.resolve(process.argv[2] ?? '');
const emit = process.argv[3] === '--emit-fixtures';
const emitCatalog = process.argv[3] === '--emit-catalog';
assert.ok(process.argv[2], 'Pinned reference checkout required');
assert.ok(!process.argv[3] || emit || emitCatalog, 'Only --emit-fixtures or --emit-catalog is supported');
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
const verify = () => {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
};
verify();
let nowMilliseconds = 172800000;
const context = vm.createContext({Date: class extends Date {
  static now() { return nowMilliseconds; }
}});
const load = async relative => {
  const file = path.join(root, relative);
  const module = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(file, 'utf8'),
    {mode: 'transform'}), {context, identifier: file});
  await module.link(id => {
    // These imports are types only in the complete funbox metadata module.
    const names = id === '@monkeytype/schemas/configs' ? ['FunboxName']
      : id === './types' ? ['FunboxMetadata'] : null;
    assert.ok(names, 'Unexpected runtime dependency: ' + id);
    return new vm.SyntheticModule(names, function () {
      for (const name of names) this.setExport(name, undefined);
    }, {context});
  });
  await module.evaluate();
  return module.namespace;
};
const numbers = await load('packages/util/src/numbers.ts');
const dates = await load('packages/util/src/date-and-time.ts');
const funboxes = await load('packages/funbox/src/list.ts');
if (emitCatalog) {
  const catalog = funboxes.getFunboxNames().map(name => ({name, difficulty: funboxes.getFunbox(name).difficultyLevel}));
  verify();
  process.stdout.write(JSON.stringify({referenceCommit: pin, catalog}));
  process.exit(0);
}
Object.assign(context, {mapRange: numbers.mapRange, isSafeNumber: numbers.isSafeNumber,
  getStartOfDayTimestamp: dates.getStartOfDayTimestamp, getCurrentDayTimestamp: dates.getCurrentDayTimestamp,
  getFunbox: funboxes.getFunbox});
const controller = fs.readFileSync(path.join(root, 'backend/src/api/controllers/result.ts'), 'utf8');
const anchor = 'async function calculateXp(';
const begin = controller.indexOf(anchor);
assert.ok(begin >= 0 && controller.indexOf(anchor, begin + 1) === -1, 'XP function identity changed');
// The pinned private function is the final declaration. Do not copy or persist
// its text into fixtures; only independently supplied inputs and outputs leave.
new vm.Script(stripTypeScriptTypes(controller.slice(begin), {mode: 'transform'})
  + '\nglobalThis.calculateOwnedFixture = calculateXp;', {filename: 'read-only-XP-function'}).runInContext(context);

const baselineInput = {mode: 'time', accuracy: 100, durationSeconds: 15, afkSeconds: 0,
  characterCounts: [100, 0, 0, 0], punctuation: false, numbers: false,
  incompleteSeconds: null, incompleteAttempts: null};
// Owned test configuration, not a claim about the production Monkeytype site.
const baselineConfig = {enabled: true, gainMultiplier: 1, funboxBonus: 0,
  minimumDailyBonus: 0, maximumDailyBonus: 0, streakEnabled: false,
  maximumStreakDays: 0, maximumStreakMultiplier: 0};
const baselineContext = {previousResultMilliseconds: null, nowMilliseconds: 172800000,
  currentTotalXP: 0, streakDays: 0};
const fixtures = [];
const add = async (label, input = {}, configuration = {}, account = {}, names = [], expected = null) => {
  const ownedInput = {...baselineInput, ...input,
    funboxDifficultyLevels: names.map(name => funboxes.getFunbox(name).difficultyLevel)};
  const ownedConfig = {...baselineConfig, ...configuration};
  const ownedContext = {...baselineContext, ...account};
  nowMilliseconds = ownedContext.nowMilliseconds;
  const result = {mode: ownedInput.mode, acc: ownedInput.accuracy, testDuration: ownedInput.durationSeconds,
    afkDuration: ownedInput.afkSeconds, charStats: ownedInput.characterCounts,
    punctuation: ownedInput.punctuation, numbers: ownedInput.numbers, funbox: names,
    incompleteTestSeconds: ownedInput.incompleteSeconds ?? undefined,
    incompleteTests: ownedInput.incompleteAttempts?.map(({accuracy, seconds}) => ({acc: accuracy, seconds}))};
  const config = {enabled: ownedConfig.enabled, gainMultiplier: ownedConfig.gainMultiplier,
    funboxBonus: ownedConfig.funboxBonus, minDailyBonus: ownedConfig.minimumDailyBonus,
    maxDailyBonus: ownedConfig.maximumDailyBonus, streak: {enabled: ownedConfig.streakEnabled,
      maxStreakDays: ownedConfig.maximumStreakDays, maxStreakMultiplier: ownedConfig.maximumStreakMultiplier}};
  const award = JSON.parse(JSON.stringify(await context.calculateOwnedFixture(result, config,
    ownedContext.previousResultMilliseconds, ownedContext.currentTotalXP, ownedContext.streakDays)));
  assert.ok(Number.isFinite(award.xp), label);
  if (expected !== null) assert.deepEqual(award, expected, label);
  fixtures.push({label, input: ownedInput, configuration: ownedConfig, context: ownedContext, award});
};
await add('baseline', {}, {}, {}, [], {xp: 45, dailyBonus: false,
  breakdown: {base: 30, fullAccuracy: 15, accPenalty: 0}});
await add('disabled', {}, {enabled: false}, {}, [], {xp: 0});
await add('zen', {mode: 'zen'}, {}, {}, [], {xp: 0});
await add('AFK', {afkSeconds: 2.5}, {}, {}, [], {xp: 38, dailyBonus: false,
  breakdown: {base: 25, fullAccuracy: 13, accPenalty: 0}});
await add('corrected', {accuracy: 75}, {}, {}, [], {xp: 19, dailyBonus: false,
  breakdown: {base: 30, corrected: 8, accPenalty: 19}});
await add('residual', {accuracy: 75, characterCounts: [99, 1, 0, 0]}, {}, {}, [],
  {xp: 15, dailyBonus: false, breakdown: {base: 30, accPenalty: 15}});
await add('quote-exclusion', {mode: 'quote', punctuation: true, numbers: true}, {}, {}, [],
  {xp: 60, dailyBonus: false, breakdown: {base: 30, fullAccuracy: 15, quote: 15, accPenalty: 0}});
await add('punctuation-numbers', {punctuation: true, numbers: true}, {}, {}, [],
  {xp: 60, dailyBonus: false, breakdown: {base: 30, fullAccuracy: 15, punctuation: 12, numbers: 3, accPenalty: 0}});
await add('prior-attempts', {accuracy: 75, characterCounts: [99, 1, 0, 0], incompleteSeconds: 900,
  incompleteAttempts: [{accuracy: 100, seconds: 1.5}, {accuracy: 75, seconds: 1.5},
    {accuracy: 49, seconds: 20}]}, {}, {}, [],
  {xp: 18, dailyBonus: false, breakdown: {base: 30, incomplete: 3, accPenalty: 15}});
await add('daily', {}, {minimumDailyBonus: 10, maximumDailyBonus: 100},
  {previousResultMilliseconds: 86400000, currentTotalXP: 1000}, [],
  {xp: 95, dailyBonus: true, breakdown: {base: 30, fullAccuracy: 15, daily: 50, accPenalty: 0}});
await add('fractional-daily', {}, {minimumDailyBonus: 0.25, maximumDailyBonus: 0.25},
  {previousResultMilliseconds: 86400000}, [],
  {xp: 45.25, dailyBonus: true, breakdown: {base: 30, fullAccuracy: 15, daily: 0.25, accPenalty: 0}});
await add('negative-multiplier-half', {accuracy: 50, incompleteSeconds: 1}, {gainMultiplier: -0.5}, {}, [],
  {xp: 0, dailyBonus: false, breakdown: {base: 30, corrected: 8, incomplete: 1, accPenalty: 38, configMultiplier: -0.5}});
await assert.rejects(() => add('unknown-funbox', {}, {funboxBonus: 1}, {}, ['owned-unknown']), /Invalid funbox name/);
for (const name of funboxes.getFunboxNames()) await add('catalog-' + name, {}, {funboxBonus: 0.13}, {}, [name]);
// Decimal half-neighbors distinguish exact binary toFixed(1) from multiply-and-round.
for (const value of [0, 0.05, 0.15, 0.25, 0.35, 0.45, 1.05, 1.15, 1.25, 1.35, 2.55, 2.65,
  0.14999999999999997, 0.15000000000000002, 1.1499999999999997, 1.1500000000000001]) {
  await add('streak-decimal-' + value, {durationSeconds: 100},
    {streakEnabled: true, maximumStreakDays: 1, maximumStreakMultiplier: value}, {streakDays: 1});
}
for (const duration of [0.24999999999999997, 0.25, 0.25000000000000006, 0.7499999999999999, 0.75, 0.7500000000000001]) {
  await add('base-half-' + duration, {durationSeconds: duration});
}
for (const value of [0.049999999999999996, 0.05000000000000001, 0.000001,
  562949953421312.1, 562949953421312.2, 2251799813685248.5, 4503599627370496]) {
  await add('streak-extreme-' + value, {durationSeconds: 0.25},
    {streakEnabled: true, maximumStreakDays: 1, maximumStreakMultiplier: value}, {streakDays: 1});
}
let seed = 0x51ceba11;
const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; };
const pick = list => list[Math.floor(random() * list.length)];
const catalog = funboxes.getFunboxNames();
for (let i = 0; i < 2048; i++) {
  const durationSeconds = random() * 3600;
  await add('owned-matrix-' + i, {mode: pick(['time', 'words', 'quote', 'custom', 'zen']),
    accuracy: pick([50, 50.01, 66.67, 75, 90, 99.99, 100]), durationSeconds,
    afkSeconds: random() * durationSeconds, characterCounts: [100, pick([0, 1]), pick([0, 1]), pick([0, 1])],
    punctuation: random() > 0.5, numbers: random() > 0.5,
    incompleteSeconds: pick([null, 0, 0.5, 8.75]),
    incompleteAttempts: pick([null, [], [{accuracy: 49, seconds: 7.5}, {accuracy: 72.13, seconds: 20.5},
      {accuracy: 100, seconds: 0.5}]])},
  {enabled: i % 53 !== 0, gainMultiplier: pick([0, 0.25, 0.5, 1, 1.125, 2]),
    funboxBonus: pick([-0.1, 0, 0.05, 0.13]), minimumDailyBonus: pick([0, 10, 0.25]),
    maximumDailyBonus: pick([0, 100, 500]), streakEnabled: random() > 0.5,
    maximumStreakDays: pick([0, 1, 7, 30, 365]), maximumStreakMultiplier: pick([-0.15, 0, 0.15, 1.15, 1.25, 2.65])},
  {previousResultMilliseconds: pick([null, 86400000, 172799999, 172800000, 259200000, -86400001]),
    nowMilliseconds: pick([172800000, 172800001, 259199999, -1]), currentTotalXP: pick([0, 1, 10, 1000, 1e6]),
    streakDays: pick([0, 1, 3, 7, 20, 365, 1000])}, pick([[], [pick(catalog)], [pick(catalog), pick(catalog)]]));
}
verify();
process.stdout.write(emit ? JSON.stringify({referenceCommit: pin, fixtures})
  : `XP source probe passed (${fixtures.length} owned fixtures; actual function, numbers, dates and funbox metadata; no controller/network/GUI)\n`);
