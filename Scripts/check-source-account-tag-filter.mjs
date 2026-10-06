// QA only: complete pinned functions; owned query-expression and storage adapters.
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
function read(file) {return fs.readFileSync(path.join(root,file),'utf8');}
function bounded(text,start,end) {
  assert.equal(text.split(start).length,2,start);
  const from=text.indexOf(start),to=text.indexOf(end,from+start.length);assert.ok(to>from,end);
  return text.slice(from,to).replace(/^export /gm,'');
}
verify();
const results=read('frontend/src/ts/collections/results.ts'), filters=read('frontend/src/ts/components/pages/account/Filters.tsx');
const defaults=read('frontend/src/ts/constants/default-result-filters.ts')
  .replace(/^import .*;\n/gm,'').replace('export default structuredClone(object);','globalThis.defaultResultFilters=structuredClone(object);');
const languages=bounded(read('packages/schemas/src/languages.ts'),'export const LanguageSchema = z.enum(', 'export type Language =');
const languageNames=[...languages.matchAll(/"([a-z0-9_]+)"/g)].map(match=>match[1]);
assert.ok(languageNames.length>400);
let stored;
class OwnedQuery {
  predicates=[];
  from() {return this;}
  where(predicate) {this.predicates.push(predicate);return this;}
  matches(row) {return this.predicates.every(predicate=>predicate({r:row}));}
}
const context=vm.createContext({structuredClone,Date,LanguageList:languageNames,
  getFunboxNames:()=>['no_quit'],getConfig:{mode:'time',time:15,words:25,quoteLength:[0],
    difficulty:'normal',language:'english',punctuation:false,numbers:false,funbox:[]},
  Query:OwnedQuery,resultsCollection:{},eq:(a,b)=>a===b,gte:(a,b)=>a>=b,
  inArray:(value,array)=>array.includes(value),length:array=>array.length,not:value=>!value,or:(...values)=>values.some(Boolean),
  setFilters:update=>{stored=update(stored);}});
const code=[defaults,
  bounded(read('packages/util/src/objects.ts'),'export function typedKeys<','export function typedEntries<'),
  bounded(read('frontend/src/ts/components/pages/account/utils.ts'),'export function mergeWithDefaultFilters(', 'export function verifyResultFiltersStructure('),
  bounded(filters,'function noFilters(', 'function fromDefaultSettings('),
  filters.slice(filters.indexOf('function fromDefaultSettings(')),
  read('frontend/src/ts/states/result-filters.ts').slice(read('frontend/src/ts/states/result-filters.ts').indexOf('export function updateTagsInFilterStorage(')).replace(/^export /,''),
  bounded(results,'export function buildResultsQuery(', 'function calcTimeTyping('),
  bounded(results,'function calcTimeTyping(', '// oxlint-disable-next-line typescript/explicit-function-return-type\nexport const getSingleResultQueryOptions'),
  bounded(results,'function normalizeResult(', 'const resultsCollection =')].join('\n');
new vm.Script(stripTypeScriptTypes(code,{mode:'transform'})).runInContext(context);
const ids=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333'];
const subset=bits=>ids.filter((_,index)=>bits&(1<<index));
const queryFixtures=[],directoryFixtures=[],currentFixtures=[],normalizationFixtures=[];
const tags=ids.map(_id=>({_id,name:'desk',active:false}));
const baseRow={mode:'time',mode2:'15',difficulty:'normal',isPb:false,punctuation:false,numbers:false,
  quoteLength:-1,language:'english',funbox:[],timestamp:1800000000000,testDuration:15,wpm:80};
for(let bits=0;bits<16;bits++) for(let rowBits=0;rowBits<8;rowBits++) {
  const filter=context.fromDefaultSettings(tags);
  filter.tags={none:!!(bits&8),...Object.fromEntries(ids.map((id,index)=>[id,!!(bits&(1<<index))]))};
  const row={...baseRow,tags:subset(rowBits)},state=context.createResultsQueryState(filter);
  const matches=context.buildResultsQuery(state).matches(row);
  assert.equal(matches,!!(bits&8)&&!row.tags.length||row.tags.some(id=>state.tags.includes(id)));
  queryFixtures.push({selectedIDs:subset(bits),includesNoTags:!!(bits&8),tagIDs:row.tags,matches});
}
for(let old=0;old<8;old++) for(let selected=0;selected<8;selected++) {
  if(selected&~old) continue;
  for(let next=0;next<8;next++) for(const none of [false,true]) {
    stored={...structuredClone(context.defaultResultFilters),tags:{none,...Object.fromEntries(subset(old).map(id=>[id,subset(selected).includes(id)])),deleted:true}};
    context.updateTagsInFilterStorage(subset(next));
    assert.equal(stored.tags.deleted,undefined);assert.equal(stored.tags.none,none);
    directoryFixtures.push({knownIDs:subset(old),selectedIDs:subset(selected),includesNoTags:none,
      nextKnownIDs:subset(next),expectedIDs:ids.filter(id=>stored.tags[id]===true)});
  }
}
for(const mode of ['time','words','quote','zen','custom']) for(let active=0;active<8;active++) {
  context.getConfig.mode=mode;
  const filter=context.fromCurrentSettings(tags.map(tag=>({...tag,active:subset(active).includes(tag._id)})));
  currentFixtures.push({mode,activeIDs:subset(active),selectedIDs:ids.filter(id=>filter.tags[id]===true),includesNoTags:filter.tags.none});
  assert.equal(filter.tags.none,active===0);
}
for(let known=0;known<8;known++) for(let rowBits=0;rowBits<8;rowBits++) {
  const normalized=context.normalizeResult({...baseRow,tags:subset(rowBits)},new Set(subset(known)));
  normalizationFixtures.push({knownIDs:subset(known),tagIDs:subset(rowBits),expectedIDs:normalized.tags});
}
assert.equal(JSON.stringify(context.normalizeResult({...baseRow},new Set(ids)).tags),'[]');
assert.equal(queryFixtures.length,128);assert.equal(directoryFixtures.length,432);
assert.equal(currentFixtures.length,40);assert.equal(normalizationFixtures.length,64);
verify();
console.log(emit?JSON.stringify({referenceCommit:pin,ids,queryFixtures,directoryFixtures,currentFixtures,normalizationFixtures}):
  'Account tag filter source passed (128 queries, 432 directory transitions, 40 current settings, 64 normalizations; complete pinned functions/default module; owned expression/storage and Funbox-name adapters, no DOM/HTTP/GUI)');
