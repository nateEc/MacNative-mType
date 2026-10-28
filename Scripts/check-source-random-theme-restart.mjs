// QA: actual pinned restart and onTestRestart, owned init/services/DOM adapters.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??'');
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
function section(file,start,end) {
  const source=fs.readFileSync(path.join(root,'frontend/src/ts',file),'utf8'),a=source.indexOf(start),b=source.indexOf(end,a);
  assert.ok(a>=0&&b>a);return stripTypeScriptTypes(source.slice(a,b).replace(/^export /gm,''),{mode:'transform'});
}
const restart=section('test/test-logic.ts','export async function restart(','let lastInitError:');
const ui=section('test/test-ui.ts','export function onTestRestart(','export function onTestFinish(');
const requests=[];
for(const initialResult of [false,true])for(const mode of ['off','on','auto','fav','light','dark','custom'])
  for(const repeated of [false,true])for(const failFirst of [false,true])requests.push({initialResult,mode,repeated,failFirst,guarded:false});
requests.push({initialResult:false,mode:'on',repeated:false,failFirst:false,guarded:true});
const fixtures=[];
for(const request of requests) {
  let active=!request.initialResult,result=request.initialResult,restarting=false,randomCount=0,initializations=0,trace=[];
  const noop=()=>{},node={hide(){return this;},show(){return this;},setStyle(){return this;}};
  const config={mode:'words',words:5,time:15,language:'english',resultSaving:false,randomTheme:request.mode,
    repeatQuotes:'off',repeatedPace:false,compositionDisplay:'replace'};
  const context=vm.createContext({Config:config,qs:()=>node,getInputElement:()=>({style:{}}),
    isFunboxActive:()=>request.guarded,isTestActive:()=>active,isTestRestarting:()=>restarting,
    isResultCalculating:()=>false,isRepeated:()=>request.repeated,
    showNoticeNotification:()=>trace.push('notice'),getCurrentQuote:()=>null,
    PractiseWords:{before:{mode:null}},resetTestEvents:noop,TestTimer:{clear:noop},
    setIsTestInvalid:noop,resetModifierState:noop,setTestActive:value=>{active=value;},Replay:{pauseReplay:noop},
    setBailedOut:noop,PaceCaret:{reset:noop,init:async()=>trace.push('pace')},setKoreanStatus:noop,clearQuoteStats:noop,
    CompositionState:{setComposing:noop,setData:noop},Strings:{clearWordDirectionCache:noop},setIsRepeated:noop,setIsPaceRepeat:noop,
    getResultVisible:()=>result,setResultVisible:value=>{result=value;trace.push('result-hidden');},
    setIsTestRestarting:value=>{restarting=value;},setInputElementValue:noop,
    Funbox:{rememberSettings:async()=>{}},init:async()=>{initializations++;trace.push('init');return !(request.failFirst&&initializations===1);},
    getActiveFunboxesWithFunction:()=>[],Focus:{set:noop},setCurrentLiveStats:noop,
    LayoutfluidFunboxTimer:{instantHide:noop},focusWords:noop,ResultWordHighlight:{destroy:noop},MonkeyPower:{reset:noop},
    MemoryFunboxTimer:{reset:noop},Caret:{resetPosition:noop},TestInitFailed:{hide:noop},ConnectionState:{get:()=>true},
    ThemeController:{randomizeTheme:async()=>{randomCount++;trace.push('random');}},
    skipBreakdownEvent:{dispatch:()=>trace.push('breakdown')},getActivePage:()=> 'test',
    AdController:{updateFooterAndVerticalAds:noop,destroyResult:noop},setCompositionText:noop,
    SoundController:{clearAllSounds:async()=>{}},cancelPendingAnimationFramesStartingWith:noop,showWords:()=>trace.push('words')});
  vm.runInContext(`let currentTestLine=0;let testReinitCount=0;let failReason='';${ui}\n${restart}`,context);
  context.TestUI={fadeOutForRestart:async source=>trace.push('fade-out:'+source),
    fadeInAfterRestart:async()=>trace.push('fade-in'),onTestRestart:source=>{trace.push('ui:'+source);context.onTestRestart(source);}};
  const frames=[];
  for(let step=0;step<2;step++) {
    trace=[];await context.restart({withSameWordset:request.repeated});
    const source=trace.find(value=>value.startsWith('ui:'))?.slice(3)??null;
    if(source!==null) {
      assert.ok(trace.indexOf('init')<trace.indexOf('ui:'+source));
      assert.ok(trace.indexOf('ui:'+source)<trace.indexOf('fade-in'));
    }
    if(trace.includes('random'))assert.ok(trace.indexOf('ui:resultPage')<trace.indexOf('random')&&trace.indexOf('random')<trace.indexOf('fade-in'));
    frames.push({source,randomCount,resultVisible:result,initializations,trace});
  }
  fixtures.push({...request,frames});
}
verify();console.log(JSON.stringify({fixtures}));
