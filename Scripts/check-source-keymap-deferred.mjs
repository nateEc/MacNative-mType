// QA only: execute pinned callback bodies against controlled source bindings.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??'');
function verify(){assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');}
verify();
const read=file=>fs.readFileSync(path.join(root,'frontend/src/ts',file),'utf8');
const logic=read('test/test-logic.ts'),timer=read('test/test-timer.ts'),boxes=read('test/funbox/funbox-functions.ts');
const start=logic.indexOf('    if (key === "keymapMode" && newValue === "next"');
const end=logic.indexOf('\n    if (\n      (key === "language"',start);assert.ok(start>=0&&end>start);
function callback(text,offset){const a=text.indexOf('setTimeout(() => {',offset),b=text.indexOf('}, 1);',a);assert.ok(a>=0&&b>a);return text.slice(a,b+6);}
const wordsStart=boxes.indexOf('    handleSpace(): void {',boxes.indexOf('  layoutfluid: {'));assert.ok(wordsStart>0);
const programs={mode:logic.slice(start,end),words:callback(boxes,wordsStart),time:callback(timer,timer.indexOf('if (Config.layout !== layout'))};
const fixtures=[];
for(const [kind,code]of Object.entries(programs))for(const word of ['e\u0301x','🙂x','a',''])for(const position of [0,1,2,3,4,9])for(const finalMode of ['next','static','react']){
  const Config={mode:'words',keymapMode:'next'},pending=[];let current='old',length=0,result;
  const context=vm.createContext({Config,key:'keymapMode',newValue:'next',nthElementFromArray:(a,i)=>a[i],
    TestWords:{words:{getCurrent:()=>({text:current})}},getCurrentInput:()=>({length}),
    highlight:key=>{result=key===''?' ':key},setTimeout:(run,delay)=>pending.push({run,delay})});
  vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'}),context);
  assert.equal(pending.length,1);current=word;length=position;Config.keymapMode=finalMode;
  pending[0].run();
  fixtures.push({kind,word,position,finalMode,delay:pending[0].delay,units:result===undefined?null:Array.from({length:result.length},(_,i)=>result.charCodeAt(i))});
}
const modeFixtures=[];
const stateCode=read('states/test.ts'),signalStart=stateCode.indexOf('const [getKeymapHighlightKey,'),signalEnd=stateCode.indexOf('const getInputLayout =',signalStart);
const ui=read('test/test-ui.ts'),inputStart=ui.indexOf('  if (Config.keymapMode === "next") {',ui.indexOf('function afterAnyTestInput(')),inputEnd=ui.indexOf('\n\n  Focus.set(true);',inputStart);
const initialStart=logic.indexOf('  if (Config.keymapMode === "next" && Config.mode !== "zen") {'),initialEnd=logic.indexOf('\n\n  Funbox.toggleScript',initialStart);
assert.ok(signalStart>=0&&signalEnd>signalStart&&inputStart>=0&&inputEnd>inputStart&&initialStart>=0&&initialEnd>initialStart);
for(const mode of ['next','static','react','off'])for(const word of ['ab','🙂x','e\u035cx'])for(const action of ['input','composition']){
 const Config={mode:'words',keymapMode:mode};let listener,length=0;
 const context=vm.createContext({Config,getConfig:Config,TestWords:{words:{getCurrent:()=>({text:word,textWithCommit:word+' '})}},getCurrentInput:()=>({length}),
  nthElementFromArray:(a,i)=>a[i],keymapEvent:{useListener:fn=>{listener=fn}},
  createSignal:value=>[()=>value,next=>{value=next}],createStore:value=>[value,(key,next)=>{value[key]=next}]});
 vm.runInContext(stripTypeScriptTypes(stateCode.slice(signalStart,signalEnd).replace(/^export /gm,''),{mode:'transform'}),context);
 context.highlight=key=>listener({mode:'highlight',key});
 vm.runInContext(stripTypeScriptTypes(logic.slice(initialStart,initialEnd),{mode:'transform'}),context);
 const units=()=>{const value=vm.runInContext('getKeymapHighlightKey()',context);return value===undefined?null:Array.from({length:value.length},(_,i)=>value.charCodeAt(i))};
 const initial=units();
 if(action==='input'){length=1;if(mode==='react')listener({mode:'flash',key:'x',correct:false})}
 vm.runInContext(ui.slice(inputStart,inputEnd),context);
 modeFixtures.push({mode,word,action,initial,units:units()});
}
verify();console.log(JSON.stringify({fixtures,modeFixtures}));
