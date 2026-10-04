// Execute the complete pinned weekly service and its Lua queries read-only.
// Isolated Unix-socket Redis only; schema, queue and connection adapters are QA boundaries.
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
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
};
verify();
const serverExecutable = process.env.TYPEBAR_SOURCE_REDIS_SERVER ?? 'redis-server';
const cliExecutable = process.env.TYPEBAR_SOURCE_REDIS_CLI ?? 'redis-cli';
assert.match(execFileSync(serverExecutable,['--version'],{encoding:'utf8',timeout:5000}),/v=6\.2\.6\b/,
  'Provide TYPEBAR_SOURCE_REDIS_SERVER matching the pinned compose server');
assert.ok(execFileSync(cliExecutable,['--help'],{encoding:'utf8',timeout:5000}).includes('--json'),
  'The QA transport requires a redis-cli with --json support (not the old 6.2.6 CLI)');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'typebar-weekly-read-'));
const socket = path.join(directory, 'redis.sock');
const server = spawn(serverExecutable,
  ['--port','0','--unixsocket',socket,'--unixsocketperm','700','--save','','--appendonly','no',
    '--dir',directory], {stdio:['ignore','ignore','pipe']});
let serverError = '', spawnError;
server.on('error', error => { spawnError = error; });
server.stderr.on('data', value => { serverError += value; });
const cli = (...args) => JSON.parse(execFileSync(cliExecutable,
  ['-s',socket,'--json',...args.map(String)], {encoding:'utf8',timeout:5000}));
try {
  for (let attempt=0; !fs.existsSync(socket); attempt++) {
    assert.ok(attempt < 100 && !spawnError && server.exitCode === null,
      'Isolated Redis failed: '+(spawnError?.message ?? serverError));
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  assert.equal(cli('PING'), 'PONG');
  const redisVersion = execFileSync(cliExecutable,
    ['-s',socket,'--raw','INFO','server'], {encoding:'utf8',timeout:5000})
    .match(/redis_version:([^\r\n]+)/)[1];
  assert.equal(redisVersion,'6.2.6','Use the server version pinned in the reference compose files');
  const lua = name => fs.readFileSync(path.join(root,'backend/redis-scripts',name+'.lua'),'utf8');
  const scripts = Object.fromEntries(['get-results','get-rank','add-result-increment','purge-results'].map(name => [name,lua(name)]));
  const connection = {
    hget:(...args) => cli('HGET',...args),
    addResultIncrement:(...args) => cli('EVAL',scripts['add-result-increment'],...args),
    getResults:(...args) => cli('EVAL',scripts['get-results'],...args),
    getRank:(...args) => cli('EVAL',scripts['get-rank'],...args),
    purgeResults:(...args) => cli('EVAL',scripts['purge-results'],...args),
  };
  let clockMilliseconds = Date.now();
  const clock = new Proxy(Date, {
    get: (target,key) => key === 'now' ? () => clockMilliseconds : Reflect.get(target,key),
  });
  const context = vm.createContext({Date:clock});
  const dates = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(
    path.join(root,'packages/util/src/date-and-time.ts'),'utf8'), {mode:'transform'}), {context});
  await dates.link(() => { throw new Error('Unexpected source date dependency'); });
  await dates.evaluate();
  const module = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(
    path.join(root,'backend/src/services/weekly-xp-leaderboard.ts'),'utf8'), {mode:'transform'}), {context});
  const exports = {
    '@monkeytype/schemas/configuration':{Configuration:undefined},
    '../init/redis':{getConnection:() => connection},
    '../queues/later-queue':{default:{scheduleForNextWeek:async () => {}}},
    '@monkeytype/schemas/leaderboards':{RedisXpLeaderboardEntry:undefined,RedisXpLeaderboardScore:undefined,
      XpLeaderboardEntry:undefined,RedisXpLeaderboardEntrySchema:{parse:value => value}},
    '@monkeytype/util/date-and-time':{getCurrentWeekTimestamp:dates.namespace.getCurrentWeekTimestamp},
    '../utils/error':{default:Error},
    '@monkeytype/util/json':{parseWithSchema:value => JSON.parse(value)},
    '../utils/misc':{omit:(value,keys) => Object.fromEntries(Object.entries(value).filter(([key]) => !keys.includes(key)))},
  };
  await module.link(id => {
    const values = exports[id]; assert.ok(values,'Unexpected source import '+id);
    return new vm.SyntheticModule(Object.keys(values),function() {
      for (const [key,value] of Object.entries(values)) this.setExport(key,value);
    }, {context});
  });
  await module.evaluate();
  const configuration = {enabled:true,expirationTimeInDays:14};
  const week = Date.now(); // Future expiry without changing host clock; date partition is not under test.
  const board = new module.namespace.WeeklyXpLeaderboard(week);
  const fixtures = [];
  for (const score of [0,Number.MIN_VALUE,1e-100,0.001,0.00001,0.000001,0.0000001,1.23456789e-7,
    0.25,0.9999999999999999,1,1.0000000000000002,52.5,52.99999999999999,1_234.875,
    4_294_967_297.75,99_999_999_999_999.5,100_000_000_000_000,9_007_199_254_740_991]) {
    cli('FLUSHDB'); // Only this owned, non-networked, nonpersistent Redis instance.
    await board.addResult(configuration,{entry:{uid:'owned',name:'Owned',timeTypedSeconds:15,
      lastActivityTimestamp:week,isPremium:true},xpGained:score});
    const global = await board.getResults(0,10,configuration,false);
    const friends = await board.getResults(0,10,configuration,true,['owned']);
    const rank = await board.getRank('owned',configuration,['owned']);
    assert.equal(global.entries[0].isPremium,undefined); assert.equal(friends.entries[0].isPremium,true);
    assert.equal(global.entries[0].rank,1); assert.equal(friends.entries[0].friendsRank,1);
    fixtures.push({score,globalScore:global.entries[0].totalXp,friendsScore:friends.entries[0].totalXp,
      rankScore:rank.totalXp});
  }
  cli('FLUSHDB');
  for (const [uid,score] of [['a',52.1],['z',52.9],['m',53],['t',53]]) {
    await board.addResult(configuration,{entry:{uid,name:uid,timeTypedSeconds:15,lastActivityTimestamp:week},xpGained:score});
  }
  const global = await board.getResults(0,10,configuration,false);
  const friends = await board.getResults(0,1,configuration,false,['a','m']);
  const friendsSecondPage = await board.getResults(1,1,configuration,false,['a','m']);
  const rank = await board.getRank('a',configuration,['a','m']);
  assert.deepEqual(Array.from(global.entries,entry => entry.uid),['t','m','z','a']);
  assert.equal(friends.entries[0].rank,2); assert.equal(friends.entries[0].friendsRank,1);
  assert.equal(friendsSecondPage.entries[0].rank,4); assert.equal(friendsSecondPage.entries[0].friendsRank,2);
  assert.equal(rank.rank,4); assert.equal(rank.friendsRank,2);
  assert.equal((await board.getResults(0,10,configuration,false,[])).count,0);
  assert.equal(await board.getRank('a',configuration,[]),null);
  assert.equal(await board.getResults(0,10,{enabled:false},false),null);
  await assert.rejects(() => board.getResults(-1,10,configuration,false));
  // Exercise the complete default-constructor write/read path, not merely a
  // replacement week arithmetic function. Future clock fixtures avoid expiry.
  const previousTZ = process.env.TZ;
  const partitionFixtures = [];
  try {
    for (const zone of ['Asia/Shanghai','America/Los_Angeles','America/New_York','Pacific/Chatham']) {
      process.env.TZ = zone;
      for (const delta of [-1,0,12 * 3_600_000]) {
        cli('FLUSHDB');
        clockMilliseconds = Date.UTC(2030,9,7) + delta;
        const currentKey = dates.namespace.getCurrentWeekTimestamp();
        const current = new module.namespace.WeeklyXpLeaderboard();
        await current.addResult(configuration,{entry:{uid:'partition',name:'Partition',timeTypedSeconds:15,
          lastActivityTimestamp:clockMilliseconds},xpGained:52.75});
        assert.deepEqual(cli('KEYS','monkeytype:weekly-xp-leaderboard:scores:*'),
          ['monkeytype:weekly-xp-leaderboard:scores:'+currentKey]);
        assert.equal((await current.getResults(0,10,configuration,false)).count,1);
        const previous = new module.namespace.WeeklyXpLeaderboard(currentKey - 604_800_000);
        assert.equal((await previous.getResults(0,10,configuration,false)).count,0);
        partitionFixtures.push({zone,timestamp:clockMilliseconds,currentKey});
      }
    }
  } finally {
    if (previousTZ === undefined) delete process.env.TZ; else process.env.TZ = previousTZ;
  }
  const cacheFixtures = [];
  const firstID = '00000000-0000-0000-0000-00000000000A';
  const secondID = '00000000-0000-0000-0000-00000000000B';
  const scenarios = [
    {label:'singleton/multi/purge/disabled',timestamp:Date.UTC(2030,9,7,12),operations:[
      {action:'add',uid:firstID,xp:10,seconds:2.5,name:'Before',days:14,enabled:true},
      {action:'add',uid:firstID,xp:5,seconds:3,name:'Changed',days:20,enabled:true},
      {action:'add',uid:secondID,xp:3,seconds:4,name:'Second',days:10,enabled:true},
      {action:'add',uid:secondID,xp:7,seconds:5,name:'Second',days:1,enabled:true},
      {action:'add',uid:firstID,xp:100,seconds:100,name:'Not cached',days:30,enabled:false},
      {action:'purge',uid:firstID,days:20,enabled:false},
      {action:'purge',uid:firstID,days:20,enabled:true},
      {action:'add',uid:secondID,xp:2,seconds:1,name:'Remaining',days:3,enabled:true},
      {action:'purge',uid:secondID,days:3,enabled:true},
      {action:'add',uid:firstID,xp:1,seconds:0.75,name:'Recreated',days:15,enabled:true},
    ]},
    {label:'immediate-expiry',timestamp:Math.floor(Date.now()/86_400_000)*86_400_000+3_600_000,operations:[
      {action:'add',uid:firstID,xp:10,seconds:2,name:'Expired',days:0,enabled:true},
      {action:'add',uid:secondID,xp:20,seconds:3,name:'Expired too',days:0,enabled:true},
    ]},
  ];
  try {
    process.env.TZ = 'UTC';
    for (const scenario of scenarios) {
      cli('FLUSHDB');
      clockMilliseconds = scenario.timestamp;
      const key = dates.namespace.getCurrentWeekTimestamp();
      const cachedBoard = new module.namespace.WeeklyXpLeaderboard(key);
      const scoresKey = 'monkeytype:weekly-xp-leaderboard:scores:'+key;
      const resultsKey = 'monkeytype:weekly-xp-leaderboard:results:'+key;
      const operations = [];
      for (const [index,operation] of scenario.operations.entries()) {
        clockMilliseconds = scenario.timestamp + index * 1_000;
        const config = {enabled:operation.enabled,expirationTimeInDays:operation.days};
        let rank = null;
        if (operation.action === 'add') {
          rank = await cachedBoard.addResult(config,{entry:{uid:operation.uid,name:operation.name,
            timeTypedSeconds:operation.seconds,lastActivityTimestamp:clockMilliseconds},xpGained:operation.xp});
        } else await module.namespace.purgeUserFromXpLeaderboards(operation.uid,config);
        const entries = (await cachedBoard.getResults(0,10,{enabled:true},false)).entries;
        const readDeadline = cacheKey => {
          const [seconds,microseconds,ttl] = cli('EVAL',
            'local t=redis.call("TIME"); return {t[1],t[2],redis.call("PTTL",KEYS[1])}',1,cacheKey);
          assert.ok(ttl >= 0 || ttl === -2,'All owned cache keys must have an expiry');
          return ttl === -2 ? null : Math.round((Number(seconds)*1_000+Number(microseconds)/1_000+ttl)/1_000)*1_000;
        };
        const expiresAtMilliseconds = readDeadline(scoresKey);
        assert.equal(readDeadline(resultsKey),expiresAtMilliseconds);
        const observed = Array.from(entries,entry => ({uid:entry.uid,name:entry.name,
          timeTypedSeconds:entry.timeTypedSeconds,lastActivityMilliseconds:entry.lastActivityTimestamp,
          score:Number(cli('ZSCORE',scoresKey,entry.uid))}));
        operations.push({...operation,timestamp:clockMilliseconds,rank,expiresAtMilliseconds,entries:observed});
      }
      cacheFixtures.push({label:scenario.label,key,operations});
    }
  } finally {
    if (previousTZ === undefined) delete process.env.TZ; else process.env.TZ = previousTZ;
  }
  const operations = cacheFixtures[0].operations;
  assert.equal(operations[1].expiresAtMilliseconds,cacheFixtures[0].key + 20 * 86_400_000);
  assert.equal(operations[3].expiresAtMilliseconds,operations[1].expiresAtMilliseconds);
  assert.equal(operations[4].rank,-1); assert.equal(operations[5].entries.length,2);
  assert.equal(operations[7].expiresAtMilliseconds,cacheFixtures[0].key + 3 * 86_400_000);
  assert.equal(operations[8].entries.length,0);
  for (const operation of cacheFixtures[1].operations) {
    assert.equal(operation.rank,1); assert.equal(operation.entries.length,0);
    assert.equal(operation.expiresAtMilliseconds,null);
  }
  verify();
  process.stdout.write(emit ? JSON.stringify({referenceCommit:pin,redisVersion,fixtures,
    global:global.entries,friends:friends.entries,friendsSecondPage:friendsSecondPage.entries,rank,partitionFixtures,cacheFixtures})
    : `Weekly XP read source passed (${fixtures.length} numeric, ${partitionFixtures.length} default-clock, ${cacheFixtures.reduce((sum,item)=>sum+item.operations.length,0)} cache lifecycle operations; real Lua/global/friends/rank/pagination; Redis ${redisVersion}; isolated socket, no GUI)\n`);
} finally {
  if (server.pid && !spawnError && server.exitCode === null && server.signalCode === null) {
    try { cli('SHUTDOWN','NOSAVE'); } catch { server.kill('SIGTERM'); }
    await new Promise(resolve => {
      if (server.exitCode !== null || server.signalCode !== null) resolve();
      else server.once('exit',resolve);
    });
  }
  fs.rmSync(directory,{recursive:true,force:true});
}
