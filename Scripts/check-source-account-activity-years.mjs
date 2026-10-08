// QA only. Complete pinned calendar / DB getter, with owned clock/auth/HTTP boundaries.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
assert.equal(process.env.TZ, 'UTC', 'Run this isolated source probe with TZ=UTC');
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
assert.ok(process.env.TYPEBAR_PRACTICE_SOURCE_DEPENDENCIES, 'Readiness supplies verified date dependencies');
const modules = path.join(process.env.TYPEBAR_PRACTICE_SOURCE_DEPENDENCIES, 'node_modules');
for (const [name, version] of [['date-fns','3.6.0'], ['@date-fns/utc','1.2.0']]) {
  assert.equal(JSON.parse(fs.readFileSync(path.join(modules,name,'package.json'))).version,version);
  assert.ok(fs.readFileSync(path.join(root,'frontend/package.json'),'utf8').includes(`"${name}": "${version}"`));
}
let now = Date.UTC(2026,5,15), authenticated = true, calls = 0, payload = {};
const clock = new Proxy(Date, {
  construct(target,args,newTarget) { return Reflect.construct(target,args.length ? args : [now],newTarget); },
  get(target,key) { return key === 'now' ? () => now : Reflect.get(target,key); },
});
const context = vm.createContext({Date:clock}), cache = new Map();
function moduleAt(file) {
  file = path.resolve(file);
  if (!cache.has(file)) cache.set(file,new vm.SourceTextModule(fs.readFileSync(file,'utf8'),{context,identifier:file}));
  return cache.get(file);
}
async function dependency(file) {
  const module = moduleAt(file);
  if (module.status === 'unlinked') await module.link((id,parent) => {
    assert.ok(id.startsWith('.')); return moduleAt(path.resolve(path.dirname(parent.identifier),id));
  });
  if (module.status !== 'evaluated') await module.evaluate();
  return module.namespace;
}
const Dates = {};
for (const name of ['format','endOfMonth','addDays','differenceInDays','eachMonthOfInterval','isSameDay','isBefore',
  'endOfYear','startOfYear','differenceInWeeks','startOfMonth','subWeeks','toDate','previousDay','nextDay']) {
  Dates[name] = (await dependency(path.join(modules,'date-fns',name+'.mjs')))[name];
}
Object.assign(context,Dates,{Dates,UTCDateMini:(await dependency(path.join(modules,'@date-fns/utc/date/mini.mjs'))).UTCDateMini,
  isAuthenticated:() => authenticated, firstDayOfTheWeek:0, showLoaderBar:() => {}, hideLoaderBar:() => {},
  showErrorNotification:() => {}, Ape:{users:{getTestActivity:async () => { calls++; return {status:200,body:{data:structuredClone(payload)}}; }}}});
function execute(code) { new vm.Script(stripTypeScriptTypes(code,{mode:'transform'})).runInContext(context); }
execute(fs.readFileSync(path.join(root,'packages/util/src/numbers.ts'),'utf8').replace(/^export /gm,''));
execute(fs.readFileSync(path.join(root,'frontend/src/ts/elements/test-activity-calendar.ts'),'utf8')
  .replace(/^import[\s\S]*?from "[^"]+";\n/gm,'').replace(/^export /gm,'')
  + '\nglobalThis.CalendarClass=TestActivityCalendar; globalThis.ModifiableCalendar=ModifiableTestActivityCalendar;');
const db = fs.readFileSync(path.join(root,'frontend/src/ts/db.ts'),'utf8');
const marker = 'export async function getTestActivityCalendar(';
assert.equal(db.split(marker).length,2);
execute(db.slice(db.indexOf(marker)).replace(/^export /,'')+'\nglobalThis.getCalendar=getTestActivityCalendar;');
const fixtures = [];
for (const year of [2000,2024,2025,2026]) for (const length of [1,60,365,366]) {
  const days = (Date.UTC(year+1,0,1)-Date.UTC(year,0,1))/86400000;
  if (length > days) continue;
  const counts = Array(length).fill(null); counts[0]=3; counts[length-1]=7;
  for (const firstWeekday of [0,1,6]) {
    // Correct DAL day index: January 1 is index zero. Full class, not a reconstructed projection.
    const calendar = new context.CalendarClass(counts,new clock(Date.UTC(year,0,length)),firstWeekday,true);
    fixtures.push({year,counts,start:calendar.startDay.valueOf(),end:calendar.endDay.valueOf(),
      total:calendar.getTotalTests(),visible:Array.from({length:days},(_,i)=>calendar.data[i]??null),
      levels:calendar.getDays().filter(day=>day.level!=='filler').map(day=>Number(day.level))});
  }
}
for (const counts of [Array(9).fill(null), ...[9,10,11].map(n=>Array.from({length:n},(_,i)=>i===n-1?10000:i))]) {
  const calendar = new context.CalendarClass(counts,new clock(Date.UTC(2024,0,counts.length)),1,true);
  fixtures.push({year:2024,counts,start:calendar.startDay.valueOf(),end:calendar.endDay.valueOf(),
    total:calendar.getTotalTests(),visible:Array.from({length:366},(_,i)=>calendar.data[i]??null),
    levels:calendar.getDays().filter(day=>day.level!=='filler').map(day=>Number(day.level))});
}
const currentSnapshots = [];
for (const [lastDay, today] of [[Date.UTC(2023,11,31),Date.UTC(2024,0,15)],
  [Date.UTC(2024,0,1),Date.UTC(2024,0,15)], [Date.UTC(2024,1,29),Date.UTC(2024,5,15)],
  [Date.UTC(2024,11,31),Date.UTC(2024,11,31)]]) {
  now=today;
  const counts=Array(372).fill(null), ordinal=Math.floor((lastDay-Date.UTC(new Date(lastDay).getUTCFullYear(),0,1))/86400000)+1;
  counts[372-ordinal]=3; counts[371]=7;
  const calendar=new context.ModifiableCalendar(counts,new clock(lastDay),1).getFullYearCalendar();
  currentSnapshots.push({lastDay,counts,year:2024,visible:Array.from({length:366},(_,i)=>calendar.data[i]??null)});
}
now=Date.UTC(2026,5,15);
context.dbSnapshot = {testActivity:new context.ModifiableCalendar([3,null,7],new clock(Date.UTC(2026,0,3)),0)};
assert.equal(await context.getCalendar('current'),context.dbSnapshot.testActivity);
assert.equal(calls,0);
assert.equal((await context.getCalendar('2026')).getTotalTests(),10);
assert.equal(calls,0);
payload = {'2024':[3,null,7],'2025':Array(365).fill(null)}; payload['2025'][0]=4; payload['2025'][364]=9;
const historical = await context.getCalendar('2024');
assert.equal(calls,1); assert.equal(historical.data[0],undefined); assert.equal(historical.data[1],3);
// Actual pinned historical DB getter adds length, not length-1: a full year rolls
// into the following year and discards the prior year's earlier values.
const fullHistorical = await context.getCalendar('2025');
assert.equal(fullHistorical.startDay.valueOf(),Date.UTC(2026,0,1));
assert.equal(fullHistorical.getTotalTests(),9);
assert.equal(calls,1); assert.equal(await context.getCalendar('2023'),undefined);
authenticated=false; assert.equal(await context.getCalendar('2024'),undefined); assert.equal(calls,1);
verify();
if (emit) process.stdout.write(JSON.stringify({fixtures,currentSnapshots,historicalDayShift:true,historicalFullYearRollover:true}));
else console.log(`Annual calendar source passed (${fixtures.length} complete-class UTC projections, ${currentSnapshots.length} actual snapshot full-year calendars; full DB getter recent/current/cache/auth; historical day-shift and full-year rollover counterexamples recorded; no DOM/HTTP/native-equivalence claim)`);
