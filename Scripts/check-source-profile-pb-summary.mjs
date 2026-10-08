// QA only: the complete pinned summary memo and formatting modules on owned data.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const root = path.resolve(process.argv[2] ?? '');
const emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
function read(file) { return fs.readFileSync(path.join(root, file), 'utf8'); }
function between(source, start, end) {
  assert.equal(source.split(start).length, 2);
  const offset = source.indexOf(start), finish = source.indexOf(end, offset);
  assert.ok(finish > offset);
  return source.slice(offset, finish);
}
function run(code, context) {
  new vm.Script(stripTypeScriptTypes(code.replace(/^export /gm, ''), {mode: 'transform'}))
    .runInContext(context, {timeout: 1000});
}
verify();
const component = read('frontend/src/ts/components/pages/profile/UserProfile.tsx');
const memo = between(component, '  const bests = createMemo(() =>', '\n\n  return (');
const summaryContext = vm.createContext({createMemo: callback => callback()});
const fixtures = [];
for (const flavor of ['ledger', 'legacy', 'legacyWithoutMode2']) {
  for (const size of [0, 1, 8, 25, 80]) {
    const rows = Array.from({length: size}, (_, i) => {
      const mode = ['time', 'words', 'time', 'words', 'custom', 'zen'][i % 6];
      const parameter = (mode === 'time' ? [15, 30, 60, 120, 45] : [10, 25, 50, 100, 200])[Math.floor(i / 6) % 5];
      const speed = [0, 0.01, 60.48, 60.49, 80.5, 80.5][i % 6];
      return {id: `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`, mode,
        mode2: ['time', 'words'].includes(mode) ? String(parameter) : mode,
        ...(mode === 'time' ? {durationSeconds: parameter} : mode === 'words' ? {wordLimit: parameter} : {}),
        language: `owned_${i}`, wpm: Math.round(speed), preciseWpm: speed, rawWpm: 120, preciseRawWpm: 120,
        accuracy: 99, preciseAccuracy: 98.75, consistency: 80.25, finishedAt: 100 + i,
        acceptedAtMilliseconds: 1800000000875 + i, personalBestOrigin: 'accepted',
        personalBestConfiguration: {version: 1, difficulty: 'normal', punctuation: !!(i % 2), numbers: false, lazyMode: false}};
    });
    const expected = [];
    for (const mode of ['time', 'words']) {
      const pbs = {};
      for (const row of rows.filter(row => row.mode === mode)) {
        (pbs[row.mode2] ??= []).push({...row, wpm: row.preciseWpm});
      }
      summaryContext.props = {mode, mode2: mode === 'time' ? ['15', '30', '60', '120'] : ['10', '25', '50', '100'], pbs};
      // A fresh lexical scope allows the same complete const declaration per mode.
      run(`{ ${memo}\nglobalThis.summary = bests; }`, summaryContext);
      expected.push(...summaryContext.summary.map(item => ({id: `${mode}/${item.mode2}`, bestID: item.pb?.id ?? null})));
    }
    if (flavor !== 'ledger') for (const row of rows) {
      for (const key of ['rawWpm', 'preciseRawWpm', 'personalBestConfiguration', 'acceptedAtMilliseconds', 'personalBestOrigin']) delete row[key];
      if (flavor === 'legacyWithoutMode2') delete row.mode2;
    }
    const profile = {id: '11111111-1111-4111-8111-111111111111', displayName: 'Owned profile', joinedAt: 0,
      completedResultCount: 0, bestWPM: 0, personalBests: rows};
    if (flavor === 'ledger') Object.assign(profile, {personalBests: [], personalBestLedgerVersion: 1,
      personalBestHistoryComplete: true, personalBestSnapshots: rows});
    fixtures.push({profile, expected});
  }
}
const stale = fixtures.find(item => item.profile.personalBestSnapshots?.length === 25).profile.personalBestSnapshots;
fixtures.push({profile: {...fixtures[0].profile, personalBests: stale}, expected: fixtures[0].expected});

const formatContext = vm.createContext({});
const numbers = read('packages/util/src/numbers.ts');
const round = between(numbers, 'export function roundTo2(', '\n}\n') + '\n}';
run(`${round}\nglobalThis.Numbers = {roundTo2};`, formatContext);
const units = read('frontend/src/ts/utils/typing-speed-units.ts');
run(units.slice(units.indexOf('export type TypingSpeedUnitSettings')) + '\nglobalThis.getTypingSpeedUnit = get;', formatContext);
const formatting = read('frontend/src/ts/utils/format.ts');
run(formatting.slice(formatting.indexOf('export type FormatOptions')) + '\nglobalThis.Formatting = Formatting;', formatContext);
const formats = [];
for (const unit of ['wpm', 'cpm', 'wps', 'cps', 'wph']) for (const decimals of [false, true]) {
  for (const value of [null, 0, 0.01, 1.005, 24.18, 24.66, 60.49, 98.75, 99.995, 100]) {
    const format = new formatContext.Formatting({typingSpeedUnit: unit, alwaysShowDecimalPlaces: decimals});
    formats.push({unit, decimals, value,
      speed: format.typingSpeed(value, {fallback: '—'}),
      percentage: format.percentage(value, {fallback: '—'}),
      accuracy: format.accuracy(value, {fallback: '—'})});
  }
}
const sweeps = [];
for (const unit of ['wpm', 'cpm', 'wps', 'cps', 'wph']) {
  const maximumHundredths = 42000, hash = createHash('sha256');
  const format = new formatContext.Formatting({typingSpeedUnit: unit, alwaysShowDecimalPlaces: false});
  for (let i = 0; i <= maximumHundredths; i++) {
    const value = i / 100;
    hash.update(`${i}|${format.typingSpeed(value, {showDecimalPlaces: false})}|${format.typingSpeed(value, {showDecimalPlaces: true})}\n`);
  }
  sweeps.push({unit, maximumHundredths, expectedDigest: hash.digest('hex')});
}
verify();
if (emit) process.stdout.write(JSON.stringify({referenceCommit: pin, fixtures, formats, sweeps}));
else console.log(`pinned complete profile summary memo passed (${fixtures.length} owned profiles, ${formats.length} format cases, 210005 canonical value/unit pairs with integer/two-decimal digests; complete Formatting/units/roundTo2, no Solid/JSX/DOM/HTTP)`);
