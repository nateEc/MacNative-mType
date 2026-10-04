// Read-only complete pinned worker/queue/service modules and inbox insertion function.
// Real Redis 6.2.6 Lua and LRU 11.5.1; BullMQ and Mongo are observation adapters,
// not evidence of durable scheduling, delivery, partial failures or XP claiming.
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {pathToFileURL} from 'node:url';

const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
const verify = () => {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
};
verify();
const dependencies = process.env.TYPEBAR_WEEKLY_REWARD_SOURCE_DEPENDENCIES;
assert.ok(dependencies,'Readiness must supply the isolated pinned LRU runtime');
const lruDirectory = path.join(dependencies,'node_modules/lru-cache');
const lruVersion = JSON.parse(fs.readFileSync(path.join(lruDirectory,'package.json'))).version;
assert.equal(lruVersion,'11.5.1');
assert.equal(JSON.parse(fs.readFileSync(path.join(root,'backend/package.json'))).dependencies['lru-cache'],lruVersion);
const {LRUCache} = await import(pathToFileURL(path.join(lruDirectory,'dist/esm/index.min.js')).href);
const serverExecutable = process.env.TYPEBAR_SOURCE_REDIS_SERVER ?? 'redis-server';
const cliExecutable = process.env.TYPEBAR_SOURCE_REDIS_CLI ?? 'redis-cli';
assert.match(execFileSync(serverExecutable,['--version'],{encoding:'utf8',timeout:5000}),/v=6\.2\.6\b/);
assert.ok(execFileSync(cliExecutable,['--help'],{encoding:'utf8',timeout:5000}).includes('--json'));
const directory = fs.mkdtempSync(path.join(os.tmpdir(),'typebar-weekly-rewards-'));
const socket = path.join(directory,'redis.sock');
const server = spawn(serverExecutable,['--port','0','--unixsocket',socket,'--unixsocketperm','700',
  '--save','','--appendonly','no','--dir',directory],{stdio:['ignore','ignore','pipe']});
let spawnError, serverError = '';
server.on('error',error => { spawnError = error; });
server.stderr.on('data',value => { serverError += value; });
const cli = (...args) => JSON.parse(execFileSync(cliExecutable,['-s',socket,'--json',...args.map(String)],
  {encoding:'utf8',timeout:5000}));
const previousTZ = process.env.TZ;
try {
  for (let attempt=0; !fs.existsSync(socket); attempt++) {
    assert.ok(attempt < 100 && !spawnError && server.exitCode === null && server.signalCode === null,
      'Owned Redis failed: '+(spawnError?.message ?? serverError));
    await new Promise(resolve => setTimeout(resolve,20));
  }
  assert.equal(cli('PING'),'PONG');
  const redisVersion = execFileSync(cliExecutable,['-s',socket,'--raw','INFO','server'],{encoding:'utf8'})
    .match(/redis_version:([^\r\n]+)/)[1];
  assert.equal(redisVersion,'6.2.6');
  let milliseconds = Date.UTC(2030,9,7,12), configuration, mailCounter = 0;
  const clock = new Proxy(Date,{get:(target,key) => key === 'now' ? () => milliseconds : Reflect.get(target,key)});
  const context = vm.createContext({Date:clock,performance});
  const read = relative => fs.readFileSync(path.join(root,relative),'utf8');
  const source = relative => new vm.SourceTextModule(stripTypeScriptTypes(read(relative),{mode:'transform'}),{context});
  const synthetic = values => new vm.SyntheticModule(Object.keys(values),function() {
    for (const [key,value] of Object.entries(values)) this.setExport(key,value);
  },{context});
  // Node preserves non-type imports used only in annotations in the original.
  const typeImports = {
    'ioredis':synthetic({default:undefined}),
    '@monkeytype/schemas/configuration':synthetic({Configuration:undefined,ValidModeRule:undefined,RewardBracket:undefined}),
    '@monkeytype/schemas/users':synthetic({MonkeyMail:undefined}),
  };
  const load = async (module,imports = {}) => {
    await module.link(id => {
      const dependency = imports[id] ?? typeImports[id];
      assert.ok(dependency,'Unexpected pinned dependency '+id); return dependency;
    });
    await module.evaluate(); return module;
  };
  const numbers = await load(source('packages/util/src/numbers.ts'));
  const dates = await load(source('packages/util/src/date-and-time.ts'));
  const jobs = [], queueOptions = [];
  class Queue {
    constructor(name,options) { queueOptions.push({name,options}); }
    async add(name,data,options) { jobs.push({name,data,options}); }
  }
  class Worker {
    constructor(name,handler,options) { this.handler = handler; this.options = options; }
    on() {}
  }
  const bullmq = synthetic({Queue,QueueScheduler:class {},Worker,Job:undefined});
  const logger = synthetic({default:{info() {},success() {},error() {}}});
  const monkeyQueue = await load(source('backend/src/queues/monkey-queue.ts'),{'bullmq':bullmq});
  const makeQueue = () => load(source('backend/src/queues/later-queue.ts'),{
    'lru-cache':synthetic({LRUCache}),'../utils/logger':logger,'./monkey-queue':monkeyQueue,
    '@monkeytype/util/date-and-time':dates,
  });
  const queue = (await makeQueue()).namespace.default;
  queue.init({});
  assert.equal(queueOptions[0].options.defaultJobOptions.removeOnComplete,true);
  assert.equal(queueOptions[0].options.defaultJobOptions.removeOnFail,true);
  const queueFixtures = [];
  for (const zone of ['UTC','Asia/Shanghai','America/New_York','Pacific/Apia']) {
    process.env.TZ = zone;
    for (const delta of [-1,0,12*3_600_000]) {
      milliseconds = Date.UTC(2030,9,7)+delta;
      const before = jobs.length, taskID = zone+':'+delta;
      await queue.scheduleForNextWeek('weekly-xp-leaderboard-results',taskID);
      await queue.scheduleForNextWeek('weekly-xp-leaderboard-results',taskID);
      assert.equal(jobs.length,before+1,'Actual LRU suppresses the duplicate');
      const job = jobs.at(-1);
      assert.equal(job.options.attempts,23); assert.equal(job.options.backoff,3_600_000);
      queueFixtures.push({zone,timestamp:milliseconds,key:job.data.ctx.lastWeekTimestamp,
        delay:job.options.delay,attempts:job.options.attempts,backoff:job.options.backoff});
    }
  }
  process.env.TZ = 'UTC'; milliseconds = Date.UTC(2030,9,7,12);
  const uninitialized = (await makeQueue()).namespace.default;
  const beforeMissing = jobs.length;
  await uninitialized.scheduleForNextWeek('weekly-xp-leaderboard-results','missing');
  uninitialized.init({});
  await uninitialized.scheduleForNextWeek('weekly-xp-leaderboard-results','missing');
  assert.equal(jobs.length,beforeMissing,'Source caches even an uninitialized queue no-op');
  const evictionQueue = (await makeQueue()).namespace.default; evictionQueue.init({});
  const beforeEviction = jobs.length;
  for (let index=0; index<101; index++) await evictionQueue.scheduleForNextWeek('weekly-xp-leaderboard-results','evict-'+index);
  await evictionQueue.scheduleForNextWeek('weekly-xp-leaderboard-results','evict-0');
  assert.equal(jobs.length,beforeEviction+102);
  const lua = fs.readFileSync(path.join(root,'backend/redis-scripts/get-results.lua'),'utf8');
  const connection = {getResults:(...args) => cli('EVAL',lua,...args)};
  const misc = synthetic({omit:(value,keys) => Object.fromEntries(Object.entries(value).filter(([key]) => !keys.includes(key))),
    formatSeconds:() => 'QA duration',getOrdinalNumberString:rank => String(rank)});
  const weekly = await load(source('backend/src/services/weekly-xp-leaderboard.ts'),{
    '../init/redis':synthetic({getConnection:() => connection}),'../queues/later-queue':synthetic({default:queue}),
    '@monkeytype/util/date-and-time':dates,'../utils/error':synthetic({default:Error}),
    '@monkeytype/util/json':synthetic({parseWithSchema:value => JSON.parse(value)}),'../utils/misc':misc,
    '@monkeytype/schemas/leaderboards':synthetic({RedisXpLeaderboardEntrySchema:{parse:value => value},
      RedisXpLeaderboardEntry:undefined,RedisXpLeaderboardScore:undefined,XpLeaderboardEntry:undefined}),
  });
  let pushes = [], executions = 0;
  const dalSource = read('backend/src/dal/user.ts');
  const start = dalSource.indexOf('export async function addToInboxBulk(');
  const end = dalSource.indexOf('\nexport async function ',start+1);
  assert.ok(start >= 0 && end > start);
  context.getUsersCollection = () => ({initializeUnorderedBulkOp:() => ({
    find:filter => ({updateOne:operation => pushes.push({uid:filter.uid,operation})}),
    execute:async () => { executions++; },
  })});
  new vm.Script(stripTypeScriptTypes(dalSource.slice(start,end).replace('export async','async'),{mode:'transform'}))
    .runInContext(context);
  const mail = await load(source('backend/src/utils/monkey-mail.ts'),{'uuid':synthetic({v4:() => 'qa-mail-'+(++mailCounter)})});
  const worker = await load(source('backend/src/workers/later-worker.ts'),{
    'bullmq':bullmq,'../utils/logger':logger,'../dal/user':synthetic({addToInboxBulk:context.addToInboxBulk}),
    '../queues/george-queue':synthetic({default:{}}),'../utils/monkey-mail':mail,
    '../utils/daily-leaderboards':synthetic({DailyLeaderboard:class {}}),
    '../init/configuration':synthetic({getCachedConfiguration:async () => configuration}),
    '../utils/misc':misc,'../queues/later-queue':synthetic({default:queue}),
    '../utils/prometheus':synthetic({recordTimeToCompleteJob() {}}),
    '../services/weekly-xp-leaderboard':weekly,'@monkeytype/util/numbers':numbers,
  });
  const handler = worker.namespace.default({}); assert.equal(handler.options.autorun,false);
  const bracket = (minRank,maxRank,minReward,maxReward) => ({minRank,maxRank,minReward,maxReward});
  const bracketGroups = [[bracket(1,3,50,101)],[bracket(1,3,50,101),bracket(2,2,1,80)],
    [bracket(1,3,100,50)],[bracket(3,1,50,100)],[bracket(2,2,0,0)],
    [bracket(0,0,1,100)],[bracket(1,5,0,1)],[]];
  const rewardFixtures = bracketGroups.flatMap(brackets => [0,1,2,3,4,5,6].map(rank => ({rank,brackets,
    reward:worker.namespace.__testing.calculateXpReward(brackets,rank) ?? null})));
  const key = dates.namespace.getCurrentWeekTimestamp();
  const entries = [
    {uid:'00000000-0000-0000-0000-00000000000A',score:10.75,seconds:15.25},
    {uid:'00000000-0000-0000-0000-00000000000B',score:10.75,seconds:45.75},
    {uid:'00000000-0000-0000-0000-00000000000C',score:1.25,seconds:0.5},
  ];
  for (const entry of entries) {
    cli('ZADD','monkeytype:weekly-xp-leaderboard:scores:'+key,entry.score,entry.uid);
    cli('HSET','monkeytype:weekly-xp-leaderboard:results:'+key,entry.uid,JSON.stringify({uid:entry.uid,
      name:'QA',timeTypedSeconds:entry.seconds,lastActivityTimestamp:milliseconds}));
  }
  const workerFixtures = [];
  for (const [index,brackets] of bracketGroups.entries()) {
    for (const inboxEnabled of [true,false]) {
      configuration = {leaderboards:{weeklyXp:{enabled:true,expirationTimeInDays:15,xpRewardBrackets:brackets}},
        users:{inbox:{enabled:inboxEnabled,maxMail:index === 0 ? 0 : 2}}};
      pushes = []; executions = 0;
      let failed = false;
      try { await handler.handler({data:{taskName:'weekly-xp-leaderboard-results',ctx:{lastWeekTimestamp:key}}}); }
      catch (error) { assert.match(error.message,/500/); failed = true; }
      assert.equal(failed,brackets.length === 0);
      if (!inboxEnabled) assert.equal(pushes.length,0);
      const mails = pushes.map(({uid,operation}) => {
        const policy = operation.$push.inbox;
        assert.equal(policy.$position,0); assert.equal(policy.$slice,configuration.users.inbox.maxMail);
        assert.equal(policy.$each.length,1);
        const value = policy.$each[0]; assert.equal(value.read,false); assert.equal(value.timestamp,milliseconds);
        assert.equal(value.rewards[0].type,'xp');
        return {uid,reward:value.rewards[0].item};
      });
      workerFixtures.push({brackets,inboxEnabled,failed,executions,maxMail:configuration.users.inbox.maxMail,mails});
    }
  }
  configuration.leaderboards.weeklyXp.enabled = false; pushes = [];
  await handler.handler({data:{taskName:'weekly-xp-leaderboard-results',ctx:{lastWeekTimestamp:key}}});
  assert.equal(pushes.length,0);
  verify();
  process.stdout.write(emit ? JSON.stringify({referenceCommit:pin,lruVersion,redisVersion,queueFixtures,rewardFixtures,entries,workerFixtures,
    uninitializedQueueCached:true,evictionEnqueues:102})
    : `Weekly XP reward source passed (${queueFixtures.length} queue clocks, ${rewardFixtures.length} arithmetic, ${workerFixtures.length} worker cases; Redis ${redisVersion}, LRU ${lruVersion}; BullMQ/Mongo observation only; no GUI)\n`);
} finally {
  if (previousTZ === undefined) delete process.env.TZ; else process.env.TZ = previousTZ;
  if (server.pid && !spawnError && server.exitCode === null && server.signalCode === null) {
    try { cli('SHUTDOWN','NOSAVE'); } catch { server.kill('SIGTERM'); }
    await new Promise(resolve => {
      if (server.exitCode !== null || server.signalCode !== null) resolve(); else server.once('exit',resolve);
    });
  }
  fs.rmSync(directory,{recursive:true,force:true});
}
