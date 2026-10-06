// QA only: three complete bounded functions; owned directory and UI adapters.
// Not evidence for browser animation, frontend history reconciliation or API.
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
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
function bounded(text,start,end) {
  assert.equal(text.split(start).length,2);
  const from = text.indexOf(start), to = text.indexOf(end,from + start.length);
  assert.ok(to > from);
  return text.slice(from,to).replace(/^export /,'');
}
verify();
const tagsSource = fs.readFileSync(path.join(root,'frontend/src/ts/collections/tags.ts'),'utf8');
const paceSource = fs.readFileSync(path.join(root,'frontend/src/ts/test/pace-caret.ts'),'utf8');
const code = [bounded(tagsSource,'export function getLocalTagPB<','export function saveLocalTagPB<'),
  bounded(tagsSource,'export function getActiveTagsPB<','/**\n * Used for non reactive access.'),
  bounded(paceSource,'export async function init():','export async function update(')].join('\n');
const ids = ['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222'];
const unknown = '33333333-3333-4333-8333-333333333333';
const Config = {paceCaret:'tagPb',funbox:['owned-current-funbox']};
let selected = [], target;
const sourceTags = ids.map(_id => ({_id,personalBests:{}}));
const directory = {version:1,tags:ids.map(id => ({id,name:'desk',personalBestLedgerVersion:1,personalBests:[]}))};
const groups = [];
for (const [mode,parameter] of [['time',15],['time',30],['words',25],['words',50],['custom',0],['zen',0],['quote',0]]) {
  for (const difficulty of ['normal','expert','master']) for (let bits=0;bits<8;bits++) {
    groups.push({mode,parameter,difficulty,punctuation:!!(bits&1),numbers:!!(bits&2),lazyMode:!!(bits&4),language:'english'});
  }
}
groups.forEach((group,index) => {
  if (group.mode === 'quote') return;
  const mode2 = ['time','words'].includes(group.mode) ? String(group.parameter) : group.mode;
  ids.forEach((id,tagIndex) => {
    const speed = 50 + index % 60 + (tagIndex ? 0.49 : 0.41);
    sourceTags[tagIndex].personalBests[group.mode] ??= {};
    sourceTags[tagIndex].personalBests[group.mode][mode2] ??= [];
    sourceTags[tagIndex].personalBests[group.mode][mode2].push({...group,wpm:speed});
    const native = {id,mode:group.mode,mode2,language:group.language,wpm:Math.round(speed),preciseWpm:speed,
      rawWpm:200,preciseRawWpm:200,accuracy:98,consistency:80,finishedAt:100,
      acceptedAtMilliseconds:1800000000875,personalBestOrigin:'accepted',
      personalBestConfiguration:{version:1,difficulty:group.difficulty,punctuation:group.punctuation,
        numbers:group.numbers,lazyMode:group.lazyMode}};
    if (group.mode === 'time') native.durationSeconds = group.parameter;
    if (group.mode === 'words') native.wordLimit = group.parameter;
    directory.tags[tagIndex].personalBests.push(native);
  });
});
const context = vm.createContext({Config,settings:null,caret:{hide:() => {}},
  getTag:id => sourceTags.find(t => t._id === id), getActiveTags:() => selected.map(_id => ({_id})),
  Misc:{getMode2:() => Config.mode2},getCurrentQuote:() => undefined,
  setPaceCaretWpm:value => {target=value;},
  DB:{getLocalPB:() => {throw Error('Account tag mode must not read ordinary PB');}}});
new vm.Script(stripTypeScriptTypes(code,{mode:'transform'})).runInContext(context);
const fixtures = [];
for (const group of groups) for (const language of ['english','spanish']) {
  for (const active of [[],[ids[0]],[ids[1]],ids,[unknown]]) {
    selected = active;
    Object.assign(Config,group,{language,mode2:['time','words'].includes(group.mode) ? String(group.parameter) : group.mode});
    const expected = context.getActiveTagsPB(Config.mode,Config.mode2,Config.punctuation,Config.numbers,
      Config.language,Config.difficulty,Config.lazyMode);
    await context.init();
    assert.equal(target,expected >= 1 ? expected : undefined);
    fixtures.push({...group,language,selectedIDs:active,expected:target ?? null});
  }
}
assert.equal(fixtures.length,1680);
verify();
console.log(emit ? JSON.stringify({referenceCommit:pin,directory,fixtures})
  : 'Account tag pace source passed (1680 grouping/identity/precision/init cases; 3 complete bounded functions; owned adapters; no GUI)');
