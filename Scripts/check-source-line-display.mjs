// QA only: the complete pinned wrapper-height function, with owned DOM metrics.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const [argument,option]=process.argv.slice(2);
assert.ok(argument&&(!option||option==='--emit-fixtures'));
const root=path.resolve(argument);
function verify(){
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const source=fs.readFileSync(path.join(root,'frontend/src/ts/test/test-ui.ts'),'utf8');
const start=source.indexOf('export function updateWordsWrapperHeight(');
const end=source.indexOf('\nfunction updateWordsMargin()',start);
assert.ok(start>=0&&end>start);
// Only remove the module export. The function body and all its branches run unchanged.
const code=stripTypeScriptTypes(source.slice(start,end),{mode:'transform'})
  .replace(/^export function /,'function ');
let mode='words',limit=25,completion='word',height=null,shown=0,focusHeight=null;
let activePage='test',resultVisible=false,hasActiveWord=true;
const config={mode,showAllLines:false,tapeMode:'off'};
const word={native:{},getOffsetHeight:()=>20};
const context=vm.createContext({Config:config,CustomText:{getLimitMode:()=>completion,getLimitValue:()=>limit},
  getActivePage:()=>activePage,getResultVisible:()=>resultVisible,
  getActiveWordElement:()=>hasActiveWord?word:null,
  wordsWrapperEl:{show(){shown++;},setStyle(style){height=style.height;}},
  wordsEl:{qsa:()=>[10,35,60,85].map(top=>({...word,getOffsetTop:()=>top})),getOffsetHeight:()=>25},
  wordsHaveNewline:()=>false,window:{getComputedStyle:()=>({marginTop:'2px',marginBottom:'3px'})},
  setOutOfFocusMaxHeight:value=>{focusHeight=value;}});
new vm.Script(code).runInContext(context,{timeout:1000});
const invoke=new vm.Script('updateWordsWrapperHeight(true)');
const cases=[
  {mode:'words',limit:25},{mode:'words',limit:0},{mode:'quote',limit:25},{mode:'zen',limit:0},
  {mode:'time',limit:30},{mode:'time',limit:0},
  {mode:'custom',completion:'finish',limit:9},
  ...['time','words','sections'].flatMap(completion=>[25,0].map(limit=>({mode:'custom',completion,limit}))),
];
const fixtures=[];
for(const item of cases)for(const enabled of [false,true])for(const tape of ['off','word','letter']){
  // The real setting command rejects showAllLines=true with tape enabled.
  if(enabled&&tape!=='off')continue;
  config.mode=item.mode;config.showAllLines=enabled;config.tapeMode=tape;
  limit=item.limit;completion=item.completion==='time'?'time':item.completion==='sections'?'section':'word';
  height=null;shown=0;focusHeight=null;
  invoke.runInContext(context,{timeout:1000});
  assert.equal(shown,1);assert.equal(focusHeight,75);assert.notEqual(height,null);
  const expands=height==='';
  if(!expands)assert.equal(height,item.mode==='zen'? '50px':tape==='off'?'75px':'25px');
  fixtures.push({...item,enabled,tape,expands});
}
assert.equal(fixtures.length,52);
for(const item of fixtures.filter(value=>value.enabled)){
  if(item.mode==='custom'&&(item.completion==='time'||item.limit===0))assert.equal(item.expands,false);
  if(item.mode==='zen')assert.equal(item.expands,true);
}
for(const guardCase of ['page','result','word']){
  activePage=guardCase==='page'?'account':'test';resultVisible=guardCase==='result';hasActiveWord=guardCase!=='word';
  height=null;shown=0;invoke.runInContext(context,{timeout:1000});assert.equal(height,null);assert.equal(shown,0);
}
verify();
if(option)console.log(JSON.stringify(fixtures));
else console.log('Line display source passed (52 valid mode/limit/setting/tape combinations and 3 guards; complete pinned wrapper-height function, owned DOM metrics; no browser/layout/scroll/GUI)');
