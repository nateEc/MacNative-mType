// QA only: actual full level/date functions and complete owner streak callback.
// Owned props/snapshot/clock; real pinned date-fns; no Solid/DOM/browser/HTTP.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??''), emit=process.argv[3]==='--emit-fixtures';
assert.ok(process.argv[2]&&(!process.argv[3]||emit));
const pin='91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const deps=process.env.TYPEBAR_PRACTICE_SOURCE_DEPENDENCIES;
assert.ok(deps,'Readiness supplies pinned date dependencies');
const modules=path.join(deps,'node_modules');
assert.equal(JSON.parse(fs.readFileSync(path.join(modules,'date-fns/package.json'))).version,'3.6.0');
let now=Date.UTC(2027,0,15,6), last;
const clock=new Proxy(Date,{
  construct(target,args,newTarget){return Reflect.construct(target,args.length?args:[now],newTarget);},
  get(target,key){return key==='now'?()=>now:Reflect.get(target,key);}
});
const context=vm.createContext({Date:clock,props:{profile:{},isAccountPage:true},getLastResult:()=>last});
const read=file=>fs.readFileSync(path.join(root,file),'utf8');
function run(source) {return new vm.Script(stripTypeScriptTypes(source,{mode:'transform'})).runInContext(context);}
function expose(file,name) {
  const source=read(file), marker='export function '+name+'(';
  assert.equal(source.split(marker).length,2);
  const start=source.indexOf(marker), next=source.indexOf('\n/**',start);
  run(source.slice(start,next<0?undefined:next).replace('export ',''));
}
expose('frontend/src/ts/utils/numbers.ts','abbreviateNumber');
expose('packages/util/src/numbers.ts','isSafeNumber');
run(read('frontend/src/ts/utils/levels.ts').replace(/^import .*;\r?\n/gm,'').replaceAll('export ',''));
run(read('packages/util/src/date-and-time.ts').replaceAll('export ',''));
context.dateIsToday=context.isToday;context.dateIsYesterday=context.isYesterday;
const cache=new Map();
function moduleAt(file) {
  file=path.resolve(file);
  if(cache.has(file))return cache.get(file);
  const value=new vm.SourceTextModule(fs.readFileSync(file,'utf8'),{context,identifier:file});cache.set(file,value);return value;
}
const distance=moduleAt(path.join(modules,'date-fns/formatDistanceToNowStrict.mjs'));
await distance.link((id,parent)=>{assert.ok(id.startsWith('.'));return moduleAt(path.resolve(path.dirname(parent.identifier),id));});
await distance.evaluate();context.formatDistanceToNowStrict=distance.namespace.formatDistanceToNowStrict;
const details=read('frontend/src/ts/components/pages/profile/UserDetails.tsx');
const marker='  const extraStreakText = () => {';assert.equal(details.split(marker).length,2);
const start=details.indexOf(marker), end=details.indexOf('\n  const balloonPosition',start);assert.ok(end>start);
run(details.slice(start,end)+'\nglobalThis.extraStreakText=extraStreakText;');
const levelFixtures=[], levelDefects=[];
function threshold(level) {const steps=BigInt(level-1);return steps*100n+49n*steps*(steps-1n)/2n;}
const xpValues=new Set([0,1,99,100,101,248,249,250,999,1000,999999,Number.MAX_SAFE_INTEGER]);
for(const level of [2,3,10,100,1000,10000,1000000,10000000,19000000]) {
  for(const delta of [-1n,0n,1n])xpValues.add(Number(threshold(level)+delta));
}
for(const xp of xpValues) {
  let lower=1,upper=20000000;
  while(upper-lower>1){const mid=Math.floor((upper+lower)/2);if(threshold(mid)<=BigInt(xp))lower=mid;else upper=mid;}
  const actual=JSON.parse(JSON.stringify(context.getXpDetails(xp))), expected={level:lower,
    earnedXP:xp-Number(threshold(lower)),requiredXP:100+49*(lower-1)};
  const fixture={xp,actual,expected,totalText:context.formatXp(xp),earnedText:context.formatXp(expected.earnedXP),requiredText:context.formatXp(expected.requiredXP)};
  levelFixtures.push(fixture);
  if(actual.level!==expected.level||actual.levelCurrentXp!==expected.earnedXP||actual.levelMaxXp!==expected.requiredXP)levelDefects.push(fixture);
}
assert.ok(levelDefects.some(it=>it.actual.levelCurrentXp<0),'Keep a real premature-level floating-point counterexample');
const streakFixtures=[], day=86400000, base=Date.UTC(2027,0,15);
for(const offset of [undefined,-11,-0.5,0,0.5,12])for(const edge of [-1,0,1])for(const delta of [-2*day,-day,0,day])for(const owner of [false,true]) {
  now=base+(offset??0)*3600000+edge;last={timestamp:now+delta};
  context.props.profile={streakHourOffset:offset};context.props.isAccountPage=owner;
  const text=context.extraStreakText();
  const state=!owner?'hidden':text.includes('Claimed today: yes')?'claimed':text.includes('Claimed today: no')?'available':'expired';
  const boundary=context.getCurrentDayTimestamp(offset)+day;
  streakFixtures.push({now,last: last.timestamp,offset:offset??null,owner,state,boundary,text});
  if(!owner)assert.equal(text,'');
}
assert.equal(streakFixtures.length,144);
now=base+6*3600000;last={timestamp:now-2*day};context.props={profile:{streakHourOffset:0},isAccountPage:true};
const lostText=context.extraStreakText();assert.ok(lostText.includes('Streak lost 18 hours'));
const expiredDefect={now,last:last.timestamp,actualText:lostText,trueExpiredMilliseconds:6*3600000};
last=undefined;assert.equal(context.extraStreakText(),'');
verify();
if(emit)process.stdout.write(JSON.stringify({referenceCommit:pin,levelFixtures,levelDefects,streakFixtures,expiredDefect}));
else console.log(`Profile progress source passed (${levelFixtures.length} complete level/format fixtures, ${levelDefects.length} numeric counterexamples including premature-level rounding; 144 complete streak callbacks, actual date-fns and expired-time counterexample; owned clock/props/snapshot, no Solid/browser/HTTP)`);
