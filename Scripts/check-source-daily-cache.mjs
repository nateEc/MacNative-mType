// QA only: execute the pinned complete daily service and real Redis scripts.
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
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
const serverExecutable = process.env.TYPEBAR_SOURCE_REDIS_SERVER ?? 'redis-server';
const cliExecutable = process.env.TYPEBAR_SOURCE_REDIS_CLI ?? 'redis-cli';
assert.match(execFileSync(serverExecutable,['--version'],{encoding:'utf8',timeout:5000}),/v=6\.2\.6\b/);
const directory = fs.mkdtempSync(path.join(os.tmpdir(),'typebar-daily-read-'));
const socket = path.join(directory,'redis.sock');
const server = spawn(serverExecutable,['--port','0','--unixsocket',socket,'--unixsocketperm','700',
  '--save','','--appendonly','no','--dir',directory],{stdio:['ignore','ignore','pipe']});
let spawnError, stderr = '';
server.on('error', error => { spawnError = error; });
server.stderr.on('data', value => { stderr += value; });
const cli = (...args) => JSON.parse(execFileSync(cliExecutable,['-s',socket,'--json',...args.map(String)],
  {encoding:'utf8',timeout:5000}));
try {
  for (let attempt=0; !fs.existsSync(socket); attempt++) {
    assert.ok(attempt < 100 && !spawnError && server.exitCode === null,spawnError?.message ?? stderr);
    await new Promise(resolve => setTimeout(resolve,20));
  }
  assert.equal(cli('PING'),'PONG');
  const redisVersion = execFileSync(cliExecutable,['-s',socket,'--raw','INFO','server'],
    {encoding:'utf8',timeout:5000}).match(/redis_version:([^\r\n]+)/)[1];
  assert.equal(redisVersion,'6.2.6');
  const read = file => fs.readFileSync(path.join(root,file),'utf8');
  const scripts = Object.fromEntries(['add-result','get-results','get-rank','purge-results']
    .map(name => [name,read('backend/redis-scripts/'+name+'.lua')]));
  const connection = Object.fromEntries([['addResult','add-result'],['getResults','get-results'],
    ['getRank','get-rank'],['purgeResults','purge-results']].map(([method,script]) =>
      [method,(...args) => cli('EVAL',scripts[script],...args)]));
  let clockMilliseconds = Date.UTC(2030,9,7,12), scheduled = 0;
  const clock = new Proxy(Date,{get:(target,key) => key === 'now' ? () => clockMilliseconds : Reflect.get(target,key)});
  const context = vm.createContext({Date:clock});
  const load = source => new vm.SourceTextModule(stripTypeScriptTypes(source,{mode:'transform'}),{context});
  const dates = load(read('packages/util/src/date-and-time.ts'));
  await dates.link(() => { throw new Error('Unexpected date import'); }); await dates.evaluate();
  const miscSource = read('backend/src/utils/misc.ts');
  const extract = name => {
    const start = miscSource.indexOf('export function '+name);
    assert.ok(start >= 0); const end = miscSource.indexOf('\nexport ',start+1);
    assert.ok(end > start); return miscSource.slice(start,end);
  };
  const misc = load('const MILLISECONDS_IN_DAY = 86400000;\n'+
    ['kogascore','matchesAPattern','omit'].map(extract).join('\n'));
  await misc.link(() => { throw new Error('Unexpected selected misc import'); }); await misc.evaluate();
  const daily = load(read('backend/src/utils/daily-leaderboards.ts'));
  const adapters = {
    '../init/redis':{getConnection:() => connection},
    '../queues/later-queue':{default:{scheduleForTomorrow:async () => { scheduled++; }}},
    './misc':{kogascore:misc.namespace.kogascore,matchesAPattern:misc.namespace.matchesAPattern,omit:misc.namespace.omit},
    '@monkeytype/util/json':{parseWithSchema:value => JSON.parse(value)},
    '@monkeytype/schemas/configuration':{Configuration:undefined,ValidModeRule:undefined},
    '@monkeytype/schemas/leaderboards':{LeaderboardEntry:undefined,RedisDailyLeaderboardEntry:undefined,
      RedisDailyLeaderboardEntrySchema:{parse:value => value}},
    './error':{default:Error},'@monkeytype/schemas/shared':{Mode:undefined,Mode2:undefined},
    '@monkeytype/util/date-and-time':{getCurrentDayTimestamp:dates.namespace.getCurrentDayTimestamp},
  };
  await daily.link(id => {
    const values = adapters[id]; assert.ok(values,'Unexpected daily import '+id);
    return new vm.SyntheticModule(Object.keys(values),function() {
      for (const [key,value] of Object.entries(values)) this.setExport(key,value);
    },{context});
  }); await daily.evaluate();
  const scoreFixtures = [];
  for (const wpm of [0,1.005,59.995,60,600]) for (const acc of [0,98.994,99.995,100]) {
    for (const timestamp of [0,999,1000,86_399_999,86_400_000,Date.UTC(2030,9,7,12)]) {
      scoreFixtures.push({wpm,acc,timestamp,score:misc.namespace.kogascore(wpm,acc,timestamp)});
    }
  }
  const ruleFixtures = [];
  for (const pattern of ['english','.*','english|code','(english|code)','english.*','[a-z]+']) {
    for (const text of ['english','english1k','code','codeEnglish','xenglish','ENGLISH']) {
      ruleFixtures.push({pattern,text,matches:misc.namespace.matchesAPattern(text,pattern)});
    }
  }
  const rules = [{language:'english',mode:'words',mode2:'25'}];
  const configuration = {enabled:true,maxResults:3,leaderboardExpirationTimeInDays:2,
    validModeRules:rules,scheduleRewardsModeRules:rules};
  assert.equal(daily.namespace.getDailyLeaderboard('english','time','60',configuration),null);
  assert.equal(daily.namespace.getDailyLeaderboard('english','words','25',{...configuration,enabled:false}),null);
  const ids = ['00000000-0000-0000-0000-00000000000A','00000000-0000-0000-0000-00000000000B',
    '00000000-0000-0000-0000-00000000000C'];
  const operation = (uid,wpm,name,days=2,capacity=3,enabled=true) =>
    ({action:'add',uid,wpm,name,days,capacity,enabled});
  const scenarios = [
    {label:'GT snapshots singleton expiry capacity reduction and purge',timestamp:Date.UTC(2030,9,7,12),operations:[
      operation(ids[0],80,'First'),operation(ids[0],80,'Not overwritten',4),
      operation(ids[0],81,'Improved',5),operation(ids[1],80,'Second',10),operation(ids[2],79,'Third',12),
      operation(ids[2],79,'Unchanged shrinks one',20,1),operation(ids[0],81,'Still unchanged',20,1),
      {action:'purge',uid:ids[0],enabled:false},{action:'purge',uid:ids[0],enabled:true},
      operation(ids[0],60,'Recreated',2),operation(ids[1],70,'Disabled',2,3,false),
    ]},
    {label:'immediate expiry',timestamp:Date.now(),operations:[operation(ids[0],60,'Expired',0)]},
    {label:'zero capacity',timestamp:Date.UTC(2030,9,7,12),operations:[operation(ids[0],60,'Evicted',2,0)]},
    {label:'same second reverse member tie and eviction',timestamp:Date.UTC(2030,9,7,12),step:100,operations:[
      operation(ids[0],60,'Lower ID',2,1),operation(ids[1],60,'Higher ID',2,1),
      operation(ids[0],60,'Evicted equal score',2,1)]},
  ];
  const fixtures = [];
  const deadline = scoresKey => {
    const [seconds,micros,ttl] = cli('EVAL','local t=redis.call("TIME"); return {t[1],t[2],redis.call("PTTL",KEYS[1])}',1,scoresKey);
    assert.ok(ttl >= 0 || ttl === -2);
    return ttl === -2 ? null : Math.round((Number(seconds)*1000+Number(micros)/1000+ttl)/1000)*1000;
  };
  for (const scenario of scenarios) {
    cli('FLUSHDB'); // Owned isolated child only, no TCP or persistence.
    clockMilliseconds = scenario.timestamp;
    const key = dates.namespace.getCurrentDayTimestamp();
    const board = daily.namespace.getDailyLeaderboard('english','words','25',configuration);
    const scoresKey = 'monkeytype:dailyleaderboard:scores:english:words:25:'+key;
    const resultsKey = 'monkeytype:dailyleaderboard:results:english:words:25:'+key;
    const operations = [];
    for (const [index,op] of scenario.operations.entries()) {
      clockMilliseconds = scenario.timestamp + index*(scenario.step ?? 1000);
      const config = {...configuration,enabled:op.enabled,maxResults:op.capacity ?? 3,
        leaderboardExpirationTimeInDays:op.days ?? 2};
      let rank = null;
      const timestamp = Math.floor(clockMilliseconds/1000)*1000;
      if (op.action === 'add') rank = await board.addResult({uid:op.uid,name:op.name,wpm:op.wpm,
        raw:op.wpm,acc:100,consistency:0,timestamp,isPremium:true},config);
      else await daily.namespace.purgeUserFromDailyLeaderboards(op.uid,config);
      const page = await board.getResults(0,10,configuration,false);
      if (scenario === scenarios[0] && index === 3) {
        const friends = await board.getResults(0,1,configuration,false,[ids[1]]);
        const personal = await board.getRank(ids[1],configuration,[ids[1]]);
        assert.equal(friends.entries[0].rank,2); assert.equal(friends.entries[0].friendsRank,1);
        assert.equal(personal.rank,2); assert.equal(personal.friendsRank,1);
      }
      const entries = Array.from(page.entries,entry => ({uid:entry.uid,name:entry.name,wpm:entry.wpm,
        timestamp:entry.timestamp,score:Number(cli('ZSCORE',scoresKey,entry.uid))}));
      assert.ok(page.entries.every(entry => entry.isPremium === undefined));
      const expiresAtMilliseconds = deadline(scoresKey); assert.equal(deadline(resultsKey),expiresAtMilliseconds);
      operations.push({...op,acceptedMilliseconds:clockMilliseconds,timestamp,rank:rank === -1 ? null : rank,
        entries,expiresAtMilliseconds});
    }
    fixtures.push({label:scenario.label,key,operations});
  }
  const ops = fixtures[0].operations;
  assert.equal(ops[1].rank,null); assert.equal(ops[1].entries[0].name,'First');
  assert.equal(ops[1].expiresAtMilliseconds,fixtures[0].key+4*86_400_000);
  assert.equal(ops[4].expiresAtMilliseconds,fixtures[0].key+5*86_400_000);
  assert.equal(ops[5].entries.length,2); assert.equal(ops[6].entries.length,1);
  assert.equal(ops[6].expiresAtMilliseconds,ops[4].expiresAtMilliseconds);
  assert.equal(ops[7].entries.length,1); assert.equal(ops[8].entries.length,0);
  for (const fixture of fixtures.slice(1,3)) {
    assert.equal(fixture.operations[0].rank,null); assert.equal(fixture.operations[0].entries.length,0);
  }
  assert.equal(fixtures[3].operations[1].entries[0].uid,ids[1]);
  assert.equal(fixtures[3].operations[2].rank,null);
  assert.equal(scheduled,13,'Enabled unchanged/evicted/expired attempts still schedule in the original service');
  // Execute the entire selected frontend function; no implementation copied
  // into the app. Synthetic IDs are QA-only, not upstream catalogue assets.
  const frontend = read('frontend/src/ts/utils/misc.ts');
  const mode2Start = frontend.indexOf('export function getMode2<');
  const mode2End = frontend.indexOf('\nexport async function downloadResultsCSV',mode2Start);
  assert.ok(mode2Start >= 0 && mode2End > mode2Start);
  const mode2Module = load(frontend.slice(mode2Start,mode2End));
  await mode2Module.link(() => { throw new Error('Unexpected mode2 import'); }); await mode2Module.evaluate();
  const mode2Fixtures = [];
  for (const mode of ['time','words','custom','zen','quote']) {
    for (const variant of [0,1,2]) {
      const config = {mode,time:[15,30,60][variant],words:[10,25,50][variant],
        customText:{mode:['none','time','word'][variant],limit:variant*15}};
      const quote = mode === 'quote' && variant !== 2 ? {id:100+variant} : null;
      const sourceMode2 = mode2Module.namespace.getMode2(config,quote);
      const nativeMode2 = mode === 'quote' ? (quote ? 'typebar:owned-'+quote.id : null) : sourceMode2;
      assert.equal(sourceMode2, mode === 'time' ? String(config.time) : mode === 'words'
        ? String(config.words) : mode === 'quote' ? String(quote?.id ?? -1) : mode);
      mode2Fixtures.push({mode,duration:mode === 'time' ? config.time : null,
        words:mode === 'words' ? config.words : null,sourceMode2,nativeMode2});
    }
  }
  // Same member can win each separate source partition. The schema adapter
  // remains explicit; numeric upstream quote keys map to owned native keys.
  cli('FLUSHDB'); clockMilliseconds = Date.UTC(2030,9,7,12);
  const partitionConfiguration = {...configuration,
    validModeRules:[{language:'.*',mode:'.*',mode2:'.*'}],scheduleRewardsModeRules:[]};
  const partitions = mode2Fixtures.filter(f => f.nativeMode2 !== null &&
    (['custom','zen'].includes(f.mode) || f.mode === 'quote' || f === mode2Fixtures[0] || f === mode2Fixtures[3]));
  const partitionFixtures = [];
  for (const fixture of partitions) {
    const board = daily.namespace.getDailyLeaderboard('english',fixture.mode,fixture.sourceMode2,partitionConfiguration);
    assert.ok(board);
    const rank = await board.addResult({uid:ids[0],name:'Owned '+fixture.mode,wpm:60,raw:60,
      acc:100,consistency:0,timestamp:clockMilliseconds},partitionConfiguration);
    const page = await board.getResults(0,10,partitionConfiguration,false);
    partitionFixtures.push({...fixture,rank:rank === -1 ? null : rank,total:page.entries.length});
  }
  assert.equal(new Set(partitionFixtures.map(f => f.mode+'/'+f.sourceMode2)).size,6);
  assert.ok(partitionFixtures.every(f => f.total === 1));
  cli('FLUSHDB'); clockMilliseconds = Date.UTC(2030,9,7,12);
  const minimumBoard = daily.namespace.getDailyLeaderboard('english','words','25',configuration);
  for (const [index,wpm] of [80,60,40].entries()) {
    await minimumBoard.addResult({uid:ids[index],name:'Owned minimum '+index,wpm,raw:wpm,
      acc:100,consistency:0,timestamp:clockMilliseconds},configuration);
  }
  const minimumFixtures = [];
  const captureMinimum = async (page,pageSize,userIds=null,purgedIds=[]) => {
    const result = await minimumBoard.getResults(page,pageSize,configuration,false,userIds ?? undefined);
    minimumFixtures.push({page,pageSize,userIds,purgedIds,minWpm:result.minWpm,count:result.count,
      entryIds:Array.from(result.entries,entry => entry.uid)});
  };
  await captureMinimum(0,1); await captureMinimum(1,1); await captureMinimum(9,1);
  await captureMinimum(0,1,[ids[0],ids[1]]); await captureMinimum(0,1,[ids[0]]);
  await captureMinimum(0,1,['00000000-0000-0000-0000-00000000000D']); await captureMinimum(0,1,[]);
  await daily.namespace.purgeUserFromDailyLeaderboards(ids[2],configuration);
  await captureMinimum(0,1,null,[ids[2]]);
  for (const id of ids.slice(0,2)) await daily.namespace.purgeUserFromDailyLeaderboards(id,configuration);
  await captureMinimum(0,1,null,ids);
  assert.deepEqual(minimumFixtures.map(f => f.minWpm),[40,40,40,60,80,0,0,60,0]);
  cli('FLUSHDB');
  await minimumBoard.addResult({uid:ids[0],name:'Owned fractional tail',wpm:59.995,raw:59.995,
    acc:100,consistency:0,timestamp:clockMilliseconds},configuration);
  const fractionalMinimum = await minimumBoard.getResults(0,1,configuration,false);
  assert.equal(fractionalMinimum.minWpm,60,'Source unpacks rounded score, not the unrounded entry WPM');
  assert.equal(fractionalMinimum.entries[0].wpm,59.995);
  verify();
  process.stdout.write(emit ? JSON.stringify({referenceCommit:pin,redisVersion,scoreFixtures,ruleFixtures,fixtures,mode2Fixtures,partitionFixtures,minimumFixtures})
    : `Daily cache source passed (${scoreFixtures.length} packed scores, ${ruleFixtures.length} patterns, ${fixtures.reduce((sum,f)=>sum+f.operations.length,0)} lifecycle operations, ${mode2Fixtures.length} getMode2 fixtures, ${partitionFixtures.length} writes across 6 source partitions, ${minimumFixtures.length} minimum reads and one fractional packed tail; complete service, QA schema/queue adapters; no GUI)\n`);
} finally {
  if (server.pid && !spawnError && server.exitCode === null && server.signalCode === null) {
    try { cli('SHUTDOWN','NOSAVE'); } catch { server.kill('SIGTERM'); }
    await new Promise(resolve => {
      if (server.exitCode !== null || server.signalCode !== null) resolve(); else server.once('exit',resolve);
    });
  }
  fs.rmSync(directory,{recursive:true,force:true});
}
