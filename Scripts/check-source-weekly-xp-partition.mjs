// Execute the complete pinned date utility and the controller's week selector.
// Only this Node process's TZ and VM-local clock change; no host clock/settings.
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
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
};
verify();
let now = 0;
const clock = new Proxy(Date, {
  get: (target,key) => key === 'now' ? () => now : Reflect.get(target,key),
});
const context = vm.createContext({Date:clock});
const dates = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(
  path.join(root,'packages/util/src/date-and-time.ts'),'utf8'),{mode:'transform'}),{context});
await dates.link(() => { throw new Error('Unexpected date utility dependency'); });
await dates.evaluate();
Object.assign(context,{getCurrentWeekTimestamp:dates.namespace.getCurrentWeekTimestamp,
  MILLISECONDS_IN_DAY:dates.namespace.MILLISECONDS_IN_DAY,MonkeyError:Error,
  WeeklyXpLeaderboard:{get:(_,timestamp) => ({timestamp})}});
const controller = fs.readFileSync(path.join(root,'backend/src/api/controllers/leaderboard.ts'),'utf8');
const begin = controller.indexOf('function getWeeklyXpLeaderboardWithError(');
const end = controller.indexOf('\nexport ',begin);
assert.ok(begin >= 0 && end > begin);
new vm.Script(stripTypeScriptTypes(controller.slice(begin,end),{mode:'transform'})
  + '\nglobalThis.selectWeek = getWeeklyXpLeaderboardWithError;').runInContext(context);
const timestamps = new Set([-86_400_001,-86_400_000,-86_399_999,-1,0,1,86_399_999,86_400_000]);
for (let day = 0; day < 365; day++) for (const hour of [0,7,12,23]) {
  timestamps.add(Date.UTC(2026,0,1+day,hour));
}
for (const year of [1900,1919,1945,1970,2000,2011,2027]) for (let month=0;month<12;month++) {
  for (const day of [1,15,28]) timestamps.add(Date.UTC(year,month,day));
}
for (const boundary of [Date.UTC(2026,9,5),Date.UTC(2011,11,30)]) {
  for (const delta of [-1,0,1,3_600_000,86_400_000]) timestamps.add(boundary+delta);
}
const zones = ['UTC','Asia/Shanghai','America/Los_Angeles','America/New_York','Europe/London',
  'Europe/Berlin','Australia/Lord_Howe','Asia/Kathmandu','Pacific/Chatham','Pacific/Auckland',
  'Pacific/Apia','America/Havana'];
const previousTZ = process.env.TZ;
const fixtures = [];
let subtractionDifferences = 0;
try {
  for (const zone of zones) {
    process.env.TZ = zone;
    for (const timestamp of timestamps) {
      now = timestamp;
      const currentKey = dates.namespace.getStartOfWeekTimestamp(timestamp);
      assert.equal(dates.namespace.getCurrentWeekTimestamp(),currentKey);
      assert.equal(context.selectWeek({enabled:true}).timestamp,-1);
      const previousKey = context.selectWeek({enabled:true},1).timestamp;
      assert.equal(previousKey,currentKey - 604_800_000);
      if (previousKey !== dates.namespace.getLastWeekTimestamp()) subtractionDifferences++;
      fixtures.push({zone,timestamp,currentKey,previousKey});
    }
  }
} finally {
  if (previousTZ === undefined) delete process.env.TZ; else process.env.TZ = previousTZ;
}
assert.ok(subtractionDifferences > 0,'Fixtures must distinguish subtraction from recomputing last week');
verify();
process.stdout.write(emit ? JSON.stringify({referenceCommit:pin,fixtures,subtractionDifferences})
  : `Weekly XP partition source passed (${fixtures.length} date/controller fixtures, ${zones.length} zones; ${subtractionDifferences} previous-week distinctions; no host changes)\n`);
