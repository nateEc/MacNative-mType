// QA only: actual bulk lifecycle, setters, Solid store, event subscriber and
// complete restart. Timers/measurement, DOM fade and initializer are adapters.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

export async function checkActiveConfigImport({context,simulation,frontend,bus,defaults,verify,store}) {
  const noop=()=>{};
  let busy=false,repeated=false,starts=[],requests=[],incomplete=[],trace=[],gates=[],success=0,errors=0;
  const extract=(from,to)=>{
    const text=fs.readFileSync(path.join(frontend,'test/test-logic.ts'),'utf8');
    const a=text.indexOf(from),b=text.indexOf(to,a);assert.ok(a>=0&&b>a);
    return stripTypeScriptTypes(text.slice(a,b).replace(/^export /gm,''),{mode:'transform'});
  };
  Object.assign(context,{isTestActive:()=>!!simulation.flags.testActive,
    isFunboxActive:name=>simulation.Config.funbox.includes(name),isTestRestarting:()=>busy,
    isResultCalculating:()=>false,isRepeated:()=>repeated,getCurrentQuote:()=>null,
    TestTimer:{clear:end=>trace.push(end?'timer-end':'timer-clear')},buildEventLog:()=>({owned:true}),
    getIncompleteTestSeconds:()=>3.5,getLiveCachedAccuracy:()=>87.25,Numbers:{roundTo2:value=>value},
    pushIncompleteTest:value=>incomplete.push(value),PractiseWords:{before:{mode:null}},
    resetTestEvents:noop,setIsTestInvalid:noop,resetModifierState:noop,
    setTestActive:value=>{simulation.flags.testActive=value;trace.push('active:'+value);},
    Replay:{pauseReplay:noop},setBailedOut:noop,PaceCaret:{reset:noop},setKoreanStatus:noop,clearQuoteStats:noop,
    CompositionState:{setComposing:noop,setData:noop},Strings:{clearWordDirectionCache:noop},
    setIsRepeated:value=>{repeated=value;},setIsPaceRepeat:noop,getResultVisible:()=>false,
    setIsTestRestarting:value=>{busy=value;},setResultVisible:noop,setInputElementValue:noop,
    Funbox:{rememberSettings:async()=>{}},init:async()=>false,getActivePage:()=> 'test',
    LazyModeState:{getArabicPref:()=>false,setArabicPref:noop},debouncedZipfCheck:noop,
    showSuccessNotification:()=>{success++;},showErrorNotification:()=>{errors++;},showNoticeNotification:()=>trace.push('notice')});
  context.TestUI={fadeOutForRestart:async()=>{
    starts.push(context.structuredClone(simulation.Config));trace.push('fade');
    await new Promise(resolve=>gates.push(resolve));
  }};
  vm.runInContext('let testReinitCount=0;let failReason="";'+extract('export async function restart(','let lastInitError:'),context);
  const actualRestart=context.restart;
  context.restart=(...args)=>{const promise=actualRestart(...args);requests.push(promise);return promise;};
  vm.runInContext(extract('configEvent.subscribe(','timerEvent.subscribe('),context);
  const fixtures=[];
  for(const active of [false,true])for(const oldNoQuit of [false,true])for(const oldSaving of [false,true])
    for(const newNoQuit of [false,true])for(const newSaving of [false,true])for(const wasBusy of [false,true])for(const wasRepeated of [false,true]) {
      simulation.flags={testActive:active,documentComplete:true,authenticated:false};
      Object.assign(simulation.Config,context.structuredClone(defaults),{resultSaving:oldSaving,
        funbox:context.structuredClone(oldNoQuit?['no_quit']:[])});
      store.setFullConfigStore(context.structuredClone(simulation.Config));
      busy=wasBusy;repeated=wasRepeated;starts=[];requests=[];incomplete=[];trace=[];gates=[];success=0;errors=0;
      simulation.events=[];simulation.saves=[];simulation.configCheckpoints=[];
      const json=JSON.stringify({mode:'words',words:4,resultSaving:newSaving,funbox:newNoQuit?['no_quit']:[]});
      await context.applyConfigFromJson(json);
      const beforeFinish={active:simulation.flags.testActive,busy,repeated,requests:requests.length,
        incomplete:incomplete.slice(),starts:starts.slice(),trace:trace.slice(),success,errors,
        runtime:context.structuredClone(simulation.Config)};
      assert.equal(success,1);assert.equal(errors,0);assert.equal(requests.length,1);
      assert.equal(starts.length,wasBusy?0:1);assert.equal(incomplete.length,active&&!wasBusy?1:0);
      if(starts.length) {
        assert.deepEqual(Array.from(starts[0].funbox),[]);
        assert.equal(starts[0].resultSaving,true,'Language restart precedes the requested resultSaving setter');
        assert.equal(starts[0].mode,'time');assert.equal(beforeFinish.active,false);
        assert.equal(beforeFinish.repeated,active&&wasRepeated);
      }
      for(const resolve of gates)resolve();await Promise.all(requests);
      fixtures.push({active,oldNoQuit,oldSaving,newNoQuit,newSaving,wasBusy,wasRepeated,json,beforeFinish,
        afterFinish:{active:simulation.flags.testActive,busy,repeated,incomplete:incomplete.slice()}});
    }
  verify();return {fixtures};
}
