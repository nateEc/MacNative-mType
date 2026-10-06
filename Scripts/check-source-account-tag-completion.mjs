// QA only: execute complete pinned functions against owned collection/UI adapters.
// No frontend bundle, real DOM, Chart.js, HTTP, credentials or GUI.
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
  const from=text.indexOf(start), to=text.indexOf(end,from+start.length);assert.ok(to>from,end);
  return text.slice(from,to).replace(/^export /,'');
}
verify();
const tags=read('frontend/src/ts/collections/tags.ts'), resultSource=read('frontend/src/ts/test/result.ts');
const funbox=read('packages/funbox/src/list.ts').replace(/^import .*;\n/gm,'').replace(/^export /gm,'');
const rounding=bounded(read('packages/util/src/numbers.ts'),'export function roundTo2(', '\n/**');
const code=[funbox,rounding,
  bounded(read('packages/funbox/src/validation.ts'),'export function checkForcedConfig(', 'export function checkCompatibility('),
  bounded(read('frontend/src/ts/config/funbox-validation.ts'),'export function canSetConfigWithCurrentFunboxes(', 'export type FunboxConfigError'),
  bounded(tags,'export function getLocalTagPB<','export function saveLocalTagPB<'),
  bounded(tags,'export function saveLocalTagPB<','export function reconcileLocalTagPB<'),
  bounded(resultSource,'async function resultCanGetPb(', 'export function showConfetti('),
  bounded(resultSource,'async function updateTags(', 'function updateTestType(')].join('\n');
const ids=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222'];
let collection, active, rows, annotations, hidden, noTags, attributes, writes;
const Config={typingSpeedUnit:'wpm',fontFamily:'owned_font'};
class OwnedDate extends Date {static now(){return 1800000000875;}}
const context=vm.createContext({Config,Date:OwnedDate,structuredClone,
  result:{},resultAnnotation:[],getTag:id=>collection.get(id),
  tagsCollection:{get:id=>collection.get(id),utils:{writeUpdate:tag=>{collection.set(tag._id,tag);writes++;}}},
  __nonReactive:{getTags:()=>[...collection.values()],getActiveTags:()=>active.map(id=>collection.get(id))},
  getTypingSpeedUnit:()=>({fromWpm:value=>value}),getTheme:()=>({sub:'#777777',bg:'#ffffff'}),
  Chart:{defaults:{font:{weight:'normal',lineHeight:1}}},
  qs:selector=>{
    if(selector==='#result .stats .tags') return {hide:()=>{hidden=true;},show:()=>{hidden=false;}};
    if(selector.endsWith('.editTagsButton')) return {setAttribute:(key,value)=>attributes[key]=value,
      addClass:value=>{assert.equal(value,'invisible');attributes.invisible=true;}};
    if(selector.endsWith('.bottom')) return {setHtml:()=>{rows=[];noTags=true;},setText:()=>{rows=[];noTags=false;},
      appendHtml:html=>{const id=html.match(/tagid="([^"]+)"/)[1], hint=html.match(/aria-label="([^"]+)"/)[1];
        rows.push({id,hint,crowned:false});}};
    const id=selector.match(/tagid="([^"]+)"/)[1], row=rows.find(row=>row.id===id);
    return {show:()=>{row.crowned=true;},setAttribute:(key,value)=>{assert.equal(key,'aria-label');row.hint=value;}};
  }
});
new vm.Script(stripTypeScriptTypes(code,{mode:'transform'})).runInContext(context);
context.Numbers={roundTo2:context.roundTo2};
function reset(mode,mode2,options,previous) {
  Object.assign(Config,{mode,mode2,language:'english',...options});
  collection=new Map(ids.map((id,index)=>[id,{_id:id,name:'desk',personalBests:mode==='quote'?{}:
    {[mode]:{[mode2]:[{...options,language:'english',wpm:index?90.69:previous,raw:120,acc:99,consistency:75,timestamp:123}]}}}]));
  active=ids;rows=[];annotations=[];hidden=false;noTags=false;attributes={};writes=0;
  context.resultAnnotation=annotations;
}
const fixtures=[];
for(const [mode,mode2] of [['time','15'],['time','30'],['words','25'],['custom','custom'],['zen','zen'],['quote','owned-quote']]) {
  for(let bits=0;bits<8;bits++) for(const dontSave of [false,true]) {
    for(const funboxes of [[],['no_quit'],['58008']]) for(const stopOnLetter of [false,true]) {
      for(const accuracy of [98.25,100]) for(const bailedOut of [false,true]) for(const previous of [0,80.41,80.49]) {
        const options={difficulty:['normal','expert','master'][bits%3],punctuation:!!(bits&1),numbers:!!(bits&2),lazyMode:!!(bits&4)};
        reset(mode,mode2,options,previous);Config.stopOnError=stopOnLetter?'letter':'off';
        context.result={mode2,funbox:funboxes,acc:accuracy,bailedOut,wpm:80.49,rawWpm:95.75,consistency:80.75};
        const before=structuredClone([...collection.values()]);
        const admission=await context.resultCanGetPb();await context.updateTags(dontSave);
        assert.equal(hidden,false);assert.equal(noTags,false);assert.equal(attributes['data-result-id'],'');
        assert.equal(attributes['data-active-tag-ids'],ids.join(','));assert.equal(attributes.invisible,true);
        const canAward=mode!=='quote'&&!dontSave&&admission.value;
        assert.equal(writes,canAward&&previous<80.49?1:0);
        const expectedRows=rows.map((row,index)=>({id:row.id,previousBestWpm:mode==='quote'?0:index?90.69:previous,
          isNewPersonalBest:row.crowned,showsPreviousBestLine:annotations.some(a=>a.label.content.startsWith('desk PB')&&a.value===(index?90.69:previous))}));
        assert.deepEqual(rows.map(row=>row.crowned),[canAward&&previous<80.49,false]);
        assert.equal(annotations.length,canAward?(previous<80.49?1:2):0);
        annotations.forEach((line,index)=>{assert.equal(line.label.position,index%2?'end':'start');assert.equal(line.label.xAdjust,index%2?-15:15);});
        if(writes) {
          const best=collection.get(ids[0]).personalBests[mode][mode2][0];
          assert.equal(best.wpm,80.49);assert.equal(best.raw,95.75);assert.equal(best.acc,accuracy);
          assert.equal(best.consistency,80.75);assert.equal(best.timestamp,1800000000875);
        } else assert.deepEqual([...collection.values()],before);
        const modeAllowed=context.canSetConfigWithCurrentFunboxes('mode',mode,funboxes);
        const numbersAllowed=context.canSetConfigWithCurrentFunboxes('numbers',options.numbers,funboxes);
        fixtures.push({mode,mode2,...options,dontSave,funboxes,stopOnLetter,accuracy,bailedOut,previous,
          modeAllowed,numbersAllowed,rows:expectedRows});
      }
    }
  }
}
assert.equal(fixtures.length,6912);
assert.equal(fixtures.filter(f=>f.modeAllowed&&f.numbersAllowed).length,5184);
reset('time','15',{difficulty:'normal',punctuation:false,numbers:false,lazyMode:false},0);
active=[];await context.updateTags(false);assert.equal(noTags,true);assert.equal(hidden,false);assert.equal(writes,0);
collection=new Map();await context.updateTags(false);assert.equal(hidden,true);
verify();
console.log(emit?JSON.stringify({referenceCommit:pin,ids,fixtures}):
  'Account tag completion source passed (6912 function cases: 5184 selectable states, 1728 source-rejected mode/forced-number states; empty states; 6 complete functions + pinned Funbox module and rounding; owned collection/UI adapters, no DOM/Chart.js/HTTP/GUI)');
