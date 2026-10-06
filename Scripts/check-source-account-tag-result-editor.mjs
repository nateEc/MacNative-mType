// QA only. Complete pinned callback bodies and functions; no TSX/Solid or real DOM.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
function read(file) { return fs.readFileSync(path.join(root,'frontend/src/ts',file),'utf8'); }
function section(text,start,end) {
  assert.equal(text.split(start).length,2,`Unique source start: ${start}`);
  const from=text.indexOf(start)+start.length, to=text.indexOf(end,from);
  assert.ok(to>from,`Source end: ${end}`); return text.slice(from,to);
}
verify();
const modal=read('components/modals/EditResultTagsModal.tsx');
const effect=section(modal,'  createEffect(() => {','\n  });');
const toggle=section(modal,'\n              onClick={() => {','\n              }}');
const save=section(modal,'\n        onClick={() => {','\n        }}');
const arrays=read('utils/arrays.ts'), result=read('test/result.ts');
const equal='function areUnsortedArraysEqual'+section(arrays,'export function areUnsortedArraysEqual','\n/**');
const display='function updateTagsAfterEdit'+section(result,'export function updateTagsAfterEdit','\nqsa(".pageTest #result .chart');
const ids=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333'];
const foreign='44444444-4444-4444-8444-444444444444', resultID='55555555-5555-4555-8555-555555555555';
const subset=mask=>ids.filter((_,i)=>mask&(1<<i));
let selected, selection, calls, closed, loading, notices, callbackCalls, rejected;
let rows, noTags, active, awards;
const context=vm.createContext({
  getSelectedResult:()=>selected, tags:()=>ids.map(_id=>({_id,name:'same name'})),
  selectedTagIds:()=>selection,setSelectedTagIds:value=>selection=value,
  hideModal:name=>{assert.equal(name,'EditResultTags');closed++;},
  showLoaderBar:()=>loading++,hideLoaderBar:()=>loading--,
  showSuccessNotification:message=>notices.push(['success',message]),
  showErrorNotification:message=>notices.push(['error',message]),
  createErrorMessage:()=> 'owned failure',
  updateTags:async params=>{
    calls.push(JSON.parse(JSON.stringify({id:params.resultId,old:params.currentTagIds,new:params.newTagIds})));
    if(rejected) throw new Error('owned transport rejection');
    params.afterUpdate({tagPbs:awards});
  },
  __nonReactive:{getTag:id=>ids.includes(id)?{name:'same name'}:undefined},
  qs:selector=>{
    if(selector.endsWith('div.noTags')) return noTags ? {remove:()=>{noTags=false;}} : undefined;
    if(selector.endsWith('.editTagsButton')) return {setAttribute:(key,value)=>{assert.equal(key,'data-active-tag-ids');active=value;}};
    assert.ok(selector.endsWith('.bottom'));
    return {setHtml:html=>{assert.equal(html,"<div class='noTags'>no tags</div>");rows=[];noTags=true;},
      appendHtml:html=>{for(const match of html.matchAll(/<div tagid="([^"]+)"[^>]*>(.*?)<\/div>/g)) {
        rows.push({id:match[1],crowned:match[2].includes('fa-crown')});
      }}};
  },
  qsa:selector=>{assert.ok(selector.endsWith('div[tagid]'));return rows.map(row=>({
    getAttribute:key=>{assert.equal(key,'tagid');return row.id;},remove:()=>{rows=rows.filter(value=>value!==row);}}));}
});
new vm.Script(stripTypeScriptTypes(equal+display,{mode:'transform'})).runInContext(context);
const realDisplay=context.updateTagsAfterEdit;
context.updateTagsAfterEdit=(...args)=>{callbackCalls++;realDisplay(...args);};
for(const [name,body] of [['effect',effect],['toggle',toggle],['save',save]]) {
  new vm.Script(stripTypeScriptTypes(`globalThis.${name} = () => {${body}\n};`,{mode:'transform'})).runInContext(context);
}
function reset(old=[], source='resultPage') {
  selected={_id:resultID,tags:old,source};selection=new Set();calls=[];closed=0;loading=0;
  notices=[];callbackCalls=0;rejected=false;awards=[];
  rows=old.filter(id=>ids.includes(id)).map(id=>({id,crowned:false}));noTags=rows.length===0;active=old.join(',');
  context.effect();
}
async function settle() { await new Promise(resolve=>setImmediate(resolve)); }
const drafts=[], feedback=[];
for(let before=0;before<8;before++) for(let after=0;after<8;after++) for(const source of ['resultPage','history']) {
  const old=subset(before), wanted=subset(after);reset(old,source);
  for(const id of ids) if(selection.has(id)!==wanted.includes(id)) { context.tag={_id:id};context.toggle(); }
  assert.equal(calls.length,0);assert.equal(closed,0);assert.equal(loading,0);assert.deepEqual(selected.tags,old);
  const selectionOrder=[...selection];context.save();await settle();
  const changed=before!==after;
  assert.equal(calls.length,changed?1:0);assert.equal(closed,1);assert.equal(loading,0);
  assert.equal(notices.length,changed?1:0);assert.equal(callbackCalls,changed&&source==='resultPage'?1:0);
  if(changed) assert.deepEqual(calls[0],{id:resultID,old,new:selectionOrder});
  drafts.push({originalIDs:old,selectedIDs:selectionOrder,changed});
}
for(let before=0;before<8;before++) for(let crowns=0;crowns<8;crowns++) {
  const initial=subset(before), initialCrowns=subset(crowns);if(!initialCrowns.every(id=>initial.includes(id))) continue;
  for(let after=0;after<8;after++) for(let awardMask=0;awardMask<8;awardMask++) for(const reverse of [false,true]) {
    const next=subset(after);if(reverse) next.reverse();const granted=subset(awardMask);
    if(!granted.every(id=>next.includes(id))) continue;
    rows=initial.map(id=>({id,crowned:initialCrowns.includes(id)}));noTags=rows.length===0;active='';
    realDisplay(next,granted);
    assert.equal(active,next.join(','));assert.equal(noTags,next.length===0);
    assert.deepEqual(rows.map(row=>row.id),[...initial.filter(id=>next.includes(id)),...next.filter(id=>!initial.includes(id))]);
    assert.deepEqual(rows.filter(row=>row.crowned).map(row=>row.id),rows.map(row=>row.id).filter(id=>
      initial.includes(id)?initialCrowns.includes(id):granted.includes(id)));
    feedback.push({initialIDs:initial,initialCrowns,nextIDs:next,awards:granted,
      displayedIDs:rows.map(row=>row.id),crownedIDs:rows.filter(row=>row.crowned).map(row=>row.id)});
  }
}
// Reactive reset, unknown associations, cancel-equivalent dismissal, no selection, failure and unordered no-op.
reset([ids[0],foreign]);assert.deepEqual([...selection],[ids[0]]);context.tag={_id:ids[1]};context.toggle();
context.effect();assert.deepEqual([...selection],[ids[0]]);assert.equal(calls.length,0);
context.hideModal('EditResultTags');assert.equal(calls.length,0);
reset([ids[0],ids[1]]);context.tag={_id:ids[0]};context.toggle();context.toggle();
assert.deepEqual([...selection],[ids[1],ids[0]]);context.save();await settle();assert.equal(calls.length,0);
reset();selected=null;context.save();await settle();assert.equal(closed,0);assert.equal(calls.length,0);
reset();context.tag={_id:ids[0]};context.toggle();rejected=true;context.save();await settle();
assert.equal(calls.length,1);assert.equal(closed,1);assert.equal(loading,0);assert.equal(callbackCalls,0);
assert.deepEqual(notices,[['error','owned failure']]);
assert.equal(drafts.length,128);assert.equal(feedback.length,1458);verify();
console.log(emit?JSON.stringify({referenceCommit:pin,drafts,feedback}):
  'Result editor source passed (128 draft/save/source cases, 1458 crown/order cases, reset/no-op/null/failure boundaries; 3 complete callback bodies + 2 functions; owned signals/transport/DOM, no Solid/TSX/HTTP/GUI)');
