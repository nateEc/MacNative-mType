// QA only: compose actual lifecycle, config bus, theme controller, restart and
// UI callback. Initialization/DOM/other services are explicit owned adapters.
import assert from 'node:assert/strict';
import vm from 'node:vm';

export async function checkThemeImportRestart({context,simulation,frontend,bus,setters,defaults,verify,store,extract,drain,pick,shown,indicator,reset}) {
  const noop=()=>{};
  let result=false,restarting=false,gateResolve,initKind='immediate',page='test',restarts=[],draws=[],trace=[];
  const node={hide(){return this;},show(){return this;},setStyle(){return this;},addClass(){return this;},removeClass(){return this;}};
  Object.assign(context,{qs:()=>node,getInputElement:()=>({style:{}}),isFunboxActive:()=>false,
    isTestActive:()=>false,isTestRestarting:()=>restarting,isResultCalculating:()=>false,isRepeated:()=>false,
    getCurrentQuote:()=>null,PractiseWords:{before:{mode:null}},resetTestEvents:noop,TestTimer:{clear:noop},
    setIsTestInvalid:noop,resetModifierState:noop,setTestActive:noop,Replay:{pauseReplay:noop},setBailedOut:noop,
    PaceCaret:{reset:noop,init:async()=>trace.push('pace')},setKoreanStatus:noop,clearQuoteStats:noop,
    CompositionState:{setComposing:noop,setData:noop},Strings:{clearWordDirectionCache:noop},setIsRepeated:noop,setIsPaceRepeat:noop,
    getResultVisible:()=>result,setResultVisible:value=>{result=value;trace.push('result-hidden');},
    setIsTestRestarting:value=>{restarting=value;},setInputElementValue:noop,Funbox:{rememberSettings:async()=>{}},
    init:async()=>{trace.push('init');if(initKind==='gate')await new Promise(resolve=>{gateResolve=resolve;});return initKind!=='fail';},
    getActiveFunboxesWithFunction:()=>[],Focus:{set:noop},setCurrentLiveStats:noop,
    LayoutfluidFunboxTimer:{instantHide:noop},focusWords:noop,ResultWordHighlight:{destroy:noop},MonkeyPower:{reset:noop},
    MemoryFunboxTimer:{reset:noop},Caret:{resetPosition:noop},TestInitFailed:{hide:noop},ConnectionState:{get:()=>true},
    skipBreakdownEvent:{dispatch:()=>trace.push('breakdown')},getActivePage:()=>page,
    AdController:{updateFooterAndVerticalAds:noop,destroyResult:noop},setCompositionText:noop,
    SoundController:{clearAllSounds:async()=>{}},cancelPendingAnimationFramesStartingWith:noop,showWords:()=>trace.push('words'),
    LazyModeState:{getArabicPref:()=>false,setArabicPref:noop},debouncedZipfCheck:noop});
  vm.runInContext('let currentTestLine=0;let testReinitCount=0;let failReason="";'+
    extract('test/test-ui.ts','export function onTestRestart(','export function onTestFinish(')+
    extract('test/test-logic.ts','export async function restart(','let lastInitError:'),context);
  const actualRestart=context.restart;
  context.restart=(...args)=>{const promise=actualRestart(...args);restarts.push(promise);return promise;};
  context.TestUI={fadeOutForRestart:async source=>trace.push('fade-out:'+source),fadeInAfterRestart:async()=>trace.push('fade-in'),
    onTestRestart:source=>{trace.push('ui:'+source);context.onTestRestart(source);}};
  context.ThemeController={randomizeTheme:()=>{
    trace.push('random');const promise=context.randomizeTheme();draws.push(promise);return promise;
  }};
  vm.runInContext(extract('test/test-logic.ts','configEvent.subscribe(','timerEvent.subscribe('),context);
  const fixtures=[];
  for(const activePage of ['test','settings'])for(const fromResult of [false,true])for(const auto of [false,true])for(const oldBag of [false,true])
    for(const mode of ['off','fav'])for(const initialization of ['immediate','gate','fail']) {
      reset();page=activePage;result=fromResult;restarting=false;restarts=[];draws=[];trace=[];gateResolve=null;initKind=initialization;
      Object.assign(simulation.Config,context.structuredClone(defaults),{theme:'serika_dark',fontFamily:'Courier',randomTheme:'off',
        customTheme:true,favThemes:context.structuredClone(['nord','serika','dracula'])});
      store.setFullConfigStore(context.structuredClone(simulation.Config));
      simulation.flags={testActive:false,authenticated:false,documentComplete:true};simulation.events=[];simulation.saves=[];
      simulation.notices=[];simulation.configCheckpoints=[];
      vm.runInContext('randomTheme=null;themesList=[];randomThemeIndex=0;previewState=null;isPreviewingTheme=false;ignoreConfigEvent=false;',context);
      bus.dispatch({key:'fullConfigChangeFinished'});await drain();
      if(oldBag) {setters.setConfig('randomTheme','fav');await drain();await context.randomizeTheme();await drain();}
      trace=[];simulation.events=[];simulation.configCheckpoints=[];
      const colors=Array.from({length:10},(_,i)=>'#'+(0x203040+i*0x050505).toString(16).padStart(6,'0'));
      const json=JSON.stringify({mode:'words',words:5,fontFamily:'Courier',fontSize:2,language:'english',theme:'nord',
        themeLight:'serika',themeDark:'dracula',autoSwitchTheme:auto,customTheme:true,customThemeColors:colors,
        favThemes:['nord'],randomTheme:mode,keymapMode:'off',funbox:[]});
      const frames=[];
      const snapshot=()=>({runtime:pick(simulation.Config),settings:pick(store.getConfig),shown:shown(),indicator:indicator(),
        active:vm.runInContext('randomTheme',context),saved:simulation.configCheckpoints.map(x=>({key:x.key,value:pick(x.value)})),
        events:context.structuredClone(simulation.events),drawCount:draws.length,trace:trace.slice()});
      await context.applyConfigFromJson(json);
      frames.push(snapshot());
      assert.equal(frames[0].drawCount,0,'The full import save precedes the result restart draw');
      assert.equal(frames[0].saved.at(-1)?.key,'full');
      assert.equal(frames[0].runtime.customTheme,true);
      if(initialization==='gate'&&restarts.length>0) {
        for(let i=0;i<30&&!gateResolve;i++)await Promise.resolve();
        assert.ok(gateResolve,'The actual language event must enter initialization');gateResolve();
      }
      await Promise.all(restarts);await Promise.all(draws);await drain();frames.push(snapshot());
      assert.equal(draws.length,activePage==='test'&&fromResult&&mode!=='off'&&initialization!=='fail'?1:0);
      fixtures.push({activePage,fromResult,auto,oldBag,mode,initialization,json,frames});
    }
  verify();return {fixtures};
}
