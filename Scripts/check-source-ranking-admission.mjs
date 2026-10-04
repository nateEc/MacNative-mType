// Execute actual pinned PB helpers and controller criteria read-only. This is
// not a full controller, MongoDB, Redis, spacing or anti-cheat acceptance test.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? '');
const emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit), 'Pinned checkout and optional --emit-fixtures required');
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
const verify = () => {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
};
verify();
const context = vm.createContext({process: {env: {MODE: 'production'}}});
let funboxes;
const load = async relative => {
  const module = new vm.SourceTextModule(stripTypeScriptTypes(fs.readFileSync(path.join(root, relative), 'utf8'),
    {mode:'transform'}), {context, identifier:relative});
  await module.link(id => {
    const names = id === '@monkeytype/schemas/configs' ? ['FunboxName'] : id === './types' ? ['FunboxMetadata']
      : id === '@monkeytype/schemas/shared' ? ['Mode','PersonalBest','PersonalBests']
      : id === '@monkeytype/schemas/results' ? ['Result'] : id === '@monkeytype/funbox' ? ['getFunbox'] : null;
    assert.ok(names, 'Unexpected dependency '+id);
    return new vm.SyntheticModule(names, function() {
      for (const name of names) this.setExport(name, name === 'getFunbox' ? funboxes.getFunbox : undefined);
    }, {context});
  });
  await module.evaluate(); return module.namespace;
};
funboxes = await load('packages/funbox/src/list.ts');
const pb = await load('backend/src/utils/pb.ts');
Object.assign(context, {canFunboxGetPb:pb.canFunboxGetPb, checkAndUpdatePb:pb.checkAndUpdatePb,
  getUsersCollection:() => ({updateOne:async () => ({})}),
  getCachedConfiguration:async () => ({leaderboards:{minTimeTyping:15}})});
const unit = (relative, beginAnchor, endAnchor) => {
  const source = fs.readFileSync(path.join(root, relative), 'utf8');
  const begin = source.indexOf(beginAnchor), end = source.indexOf(endAnchor, begin+beginAnchor.length);
  assert.ok(begin >= 0 && end > begin && source.indexOf(beginAnchor, begin+1) === -1, 'Pinned unit identity changed');
  return stripTypeScriptTypes(source.slice(begin,end), {mode:'transform'});
};
new vm.Script(unit('backend/src/dal/user.ts', 'export async function checkIfPb(', 'export async function checkIfTagPb(')
  .replace('export async function', 'async function')+'\nglobalThis.ownedCheckPb=checkIfPb;').runInContext(context);
new vm.Script(unit('backend/src/utils/misc.ts', 'export function isDevEnvironment()', 'export function getFrontendUrl()')
  .replace('export function', 'function')).runInContext(context);
const criteria = unit('backend/src/api/controllers/result.ts', '  const stopOnLetterTriggered =', '  const selectedBadgeId =');
new vm.Script('globalThis.ownedCriteria=async function(completedEvent,user){'+criteria
  +'return {speedEligible:validResultCriteria,weeklyExperienceEligible:userEligibleForLeaderboard};}').runInContext(context);
const catalog = funboxes.getFunboxNames().map(name => ({name, allowsPersonalBest:funboxes.getFunbox(name).canGetPb}));
const fixtures = [];
for (const names of [[], ...catalog.map(item => [item.name]), ['mirror','ALL_CAPS'], ['mirror','crt']]) {
  for (const mode of ['time','words','quote','custom','zen']) for (const accuracy of [99.9,100]) {
    for (const stopOnLetter of [false,true]) for (const bailedOut of [false,true]) {
      const result = {mode,mode2:mode==='time'?'15':'25',acc:accuracy,stopOnLetter,bailedOut,funbox:names,
        difficulty:'normal',language:'english',punctuation:false,lazyMode:false,numbers:false,
        consistency:100,wpm:60,rawWpm:60};
      // Fresh PB containers test admission, not replacement/tie/group semantics.
      const pbEligible = !bailedOut && await context.ownedCheckPb('owned', {}, result);
      for (const [previousTypingSeconds,environment,accountExcluded] of [
        [0,'production',false],[15,'production',false],[15.000001,'production',false],
        [0,'development',false],[30,'development',true],[30,'production',true]]) {
        context.process.env.MODE = environment==='development'?'dev':'production';
        const decision = await context.ownedCriteria(result, {timeTyping:previousTypingSeconds,
          banned:accountExcluded,lbOptOut:false});
        fixtures.push({input:{mode,accuracy,bailedOut,modifiers:names,stopOnLetter},
          context:{previousTypingSeconds,minimumTypingSeconds:15,environment,accountExcluded},
          decision:{personalBestEligible:pbEligible,...decision}});
      }
    }
  }
}
assert.throws(() => pb.canFunboxGetPb({funbox:['owned-unknown']}), /One of the funboxes is invalid/);
context.process.env.MODE = 'production';
assert.equal((await context.ownedCriteria({funbox:[],acc:100}, {timeTyping:100,lbOptOut:true})).speedEligible,false);
verify();
process.stdout.write(emit ? JSON.stringify({referenceCommit:pin,catalog,fixtures})
  : `Ranking source probe passed (${fixtures.length} owned fixtures, ${catalog.length} actual Funbox PB flags; no controller/network/GUI)\n`);
