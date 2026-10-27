import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createRequire,stripTypeScriptTypes} from 'node:module';

// Run the pinned receiver, schema, real setters/Solid store and complete
// custom-text/storage modules. UI/timing effects of restart stop at an owned
// failing initializer; the full restart function still runs its actual guards.
export async function runSharedSettingsOracle({frontend,context,load,simulation,fresh,full,verify}) {
  const require=createRequire(path.join(process.env.TYPEBAR_CONFIG_LINK_SOURCE_DEPENDENCIES,'package.json'));
  assert.equal(require('lz-ts/package.json').version,'1.1.2');
  const {compressToURI,decompressFromURI}=require('lz-ts');
  const storage=new Map(); let writes=[],requests=[],starts=0,inits=0,selectedQuote=null,notices=[],errors=[];
  const failureMode=process.argv[4]==='--storage-failures';
  let failure={},failureKind='quota',attempts=[],attemptCounts={},storageFailures=[];
  const noop=()=>{};
  Object.assign(context,{window:{localStorage:{getItem:key=>storage.get(key)??null,
    setItem:(key,value)=>{
      const index=attemptCounts[key]=(attemptCounts[key]??0)+1;
      const accepted=!(failure[key]?.includes(-1)||failure[key]?.includes(index));
      attempts.push({key,json:value,accepted});
      if(!accepted)throw new Error(failureKind==='quota'?'exceeded the quota':'owned storage rejection');
      storage.set(key,value);writes.push({key,value});
    },removeItem:key=>storage.delete(key)}},
    isTestActive:()=>!!simulation.flags.testActive,isTestRestarting:()=>!!simulation.flags.restarting,
    isResultCalculating:()=>false,isFunboxActive:name=>simulation.Config.funbox.includes(name),
    isRepeated:()=>false,getCurrentQuote:()=>null,getResultVisible:()=>false,
    setIsTestRestarting:value=>{simulation.flags.restarting=value;if(value)starts++;},
    setTestActive:value=>{simulation.flags.testActive=value;},
    TestTimer:{clear:noop},buildEventLog:()=>[],getIncompleteTestSeconds:()=>1.25,
    Numbers:{roundTo2:value=>value},getLiveCachedAccuracy:()=>100,pushIncompleteTest:noop,
    PractiseWords:{before:{mode:null},resetBefore:noop},resetTestEvents:noop,setIsTestInvalid:noop,
    resetModifierState:noop,Replay:{pauseReplay:noop},setBailedOut:noop,PaceCaret:{reset:noop},
    setKoreanStatus:noop,clearQuoteStats:noop,CompositionState:{setComposing:noop,setData:noop},
    Strings:{clearWordDirectionCache:noop},testReinitCount:0,failReason:'',
    setIsRepeated:noop,setIsPaceRepeat:noop,TestUI:{fadeOutForRestart:()=>Promise.resolve()},
    setResultVisible:noop,setInputElementValue:noop,Funbox:{rememberSettings:()=>Promise.resolve()},
    init:async()=>{inits++;return false;},canQuickRestart:()=>true});
  const custom=await load(path.join(frontend,'test/custom-text.ts'));
  simulation.storageError=message=>{
    const match=/^Failed to set (config|customTextSettings) in localStorage:/.exec(message);
    if(match)storageFailures.push(match[1]);
  };
  const configs=await load(path.join(frontend,'config/setters.ts'));
  const results=await load(path.join(frontend,'../../../packages/schemas/src/results.ts'));
  const shared=await load(path.join(frontend,'../../../packages/schemas/src/shared.ts'));
  const configSchemas=await load(path.join(frontend,'../../../packages/schemas/src/configs.ts'));
  function extract(file,from,to) {
    const text=fs.readFileSync(path.join(frontend,file),'utf8'),start=text.indexOf(from),end=text.indexOf(to,start);
    assert.ok(start>=0&&end>start,from);
    return stripTypeScriptTypes(text.slice(start,end).replace(/^export /gm,''),{mode:'transform'});
  }
  const storageModule=await load(path.join(frontend,'utils/local-storage-with-schema.ts'));
  const configLS=new storageModule.LocalStorageWithSchema({key:'config',schema:configSchemas.ConfigSchema,
    fallback:context.getDefaultConfig()});
  Object.assign(context,{configLS,configToSend:{},saveToDatabase:noop});
  vm.runInContext(extract('config/persistence.ts','export function saveToLocalStorage(',
    '\nexport function saveFullConfigToLocalStorage('),context);
  const actualPersist=context.saveToLocalStorage;
  simulation.persistConfig=key=>actualPersist(key);
  context.saveToLocalStorage=(key,nosave=false)=>{
    if(!nosave) {
      simulation.saves.push(key);
      simulation.configCheckpoints?.push({key,value:structuredClone(simulation.Config)});
    }
    actualPersist(key,nosave);
  };
  const funboxActive=await load(path.join(frontend,'test/funbox/active.ts'));
  context.isFunboxActive=funboxActive.isFunboxActive;
  const logic=fs.readFileSync(path.join(frontend,'test/test-logic.ts'),'utf8');
  const rs=logic.indexOf('export async function restart('),re=logic.indexOf('\n}',rs)+2;
  assert.ok(rs>=0&&re>rs);
  vm.runInContext(stripTypeScriptTypes(logic.slice(rs,re).replace(/^export /,''),{mode:'transform'}),context);
  const actualRestart=context.restart;
  context.restart=options=>{requests.push('listener');return actualRestart(options);};
  context.restartTest=options=>{requests.push('handler');return actualRestart(options);};
  const utilJson=await load(path.join(frontend,'../../../packages/util/src/json.ts'));
  const utilTry=await load(path.join(frontend,'../../../packages/util/src/trycatch.ts'));
  Object.assign(context,{setConfig:configs.setConfig,CustomText:custom,
    CustomTextSettingsSchema:results.CustomTextSettingsSchema,ModeSchema:shared.ModeSchema,
    Mode2Schema:shared.Mode2Schema,DifficultySchema:shared.DifficultySchema,FunboxSchema:configSchemas.FunboxSchema,
    parseJsonWithSchema:utilJson.parseWithSchema,tryCatchSync:utilTry.tryCatchSync,decompressFromURI,
    setSelectedQuoteId:value=>{selectedQuote=value;},
    Misc:{findGetParameter:(_key,override)=>override,escapeHTML:value=>value},
    showNoticeNotification:message=>notices.push(message),showSuccessNotification:noop});
  vm.runInContext(extract('controllers/url-handler.tsx','const TestSettingsSchema =','\nconst challengeNameLookup'),context);
  function raw(value) {
    if(typeof value==='number')return value===Infinity?'1e999':value===-Infinity?'-1e999':Object.is(value,-0)?'-0':String(value);
    if(Array.isArray(value))return '['+value.map(raw).join(',')+']';
    if(value&&typeof value==='object')return '{'+Object.entries(value).map(([k,v])=>JSON.stringify(k)+':'+raw(v)).join(',')+'}';
    return JSON.stringify(value);
  }
  const fixtures=[];
  const incoming={text:['owned incoming','e\u0301','字😀'],mode:'shuffle',limit:{mode:'word',value:3.5},pipeDelimiter:false};
  async function run(label,tuple,base={mode:'words',words:25,numbers:true,punctuation:true},active=false,rawTuple,busy=false,faults={},kind='quota') {
    failure={};attemptCounts={};
    fresh(); await full(raw(base));
    for(let i=0;i<20;i++)await Promise.resolve();
    custom.setText(['owned baseline','raw|section']);custom.setMode('random');
    custom.setLimitMode('section');custom.setLimitValue(7);custom.setPipeDelimiter(!failureMode);
    if(failureMode)configLS.set(simulation.Config);
    const initial=raw(simulation.Config),initialStore=raw(context.getConfig);
    const initialCustom=raw(custom.getData()),initialSaved=raw(configLS.get());
    simulation.events=[];simulation.saves=[];simulation.configCheckpoints=[];simulation.flags.testActive=active;
    simulation.flags.restarting=busy;writes=[];requests=[];starts=0;inits=0;selectedQuote=null;notices=[];errors=[];
    failure=faults;failureKind=kind;attempts=[];attemptCounts={};storageFailures=[];
    const json=rawTuple??raw(tuple);context.receivedToken=compressToURI(json);
    try {vm.runInContext('loadTestSettingsFromUrl(receivedToken)',context);}catch(e){errors.push(String(e));}
    for(let i=0;i<8;i++)await Promise.resolve();
    fixtures.push({label,json,active,busy,initial,initialStore,initialCustom,initialSaved,saved:raw(configLS.get()),
      runtime:raw(simulation.Config),store:raw(context.getConfig),
      custom:raw(custom.getData()),events:raw(simulation.events),saves:simulation.saves,
      configCheckpoints:simulation.configCheckpoints.map(value=>({key:value.key,json:raw(value.value)})),
      customWrites:writes.filter(value=>value.key==='customTextSettings').map(value=>value.value),
      configWrites:writes.filter(value=>value.key==='config').map(value=>value.value),
      selectedQuote,requests:[...requests],starts,inits,parseRejected:notices.some(value=>value.startsWith('Failed to load test settings')),
      selectedQuoteText:selectedQuote===null?null:raw(selectedQuote),activeAfter:!!simulation.flags.testActive,
      threw:errors.length>0,failure,failureKind,attempts:[...attempts],storageFailures:[...storageFailures]});
  }
  if(!failureMode) {
  for(const mode of ['time','words','custom','zen','quote'])for(let mask=0;mask<256;mask++) {
    const values=[mode,mode==='time'?'45':mode==='words'?'17':mode==='quote'?'42':mode,incoming,true,false,'arabic','expert',['no_quit']];
    await run(mode+'-'+mask,values.map((v,i)=>mask&(1<<i)?v:null));
  }
  for(const active of [false,true])for(const mode of ['words','quote'])
    await run('no-quit-'+mode+'-'+active,[mode,'42',incoming,true,true,'english','master',[]],
      {mode:'words',funbox:['no_quit']},active);
  const extras=[
    [null,3.5,null,null,null,null,null,null], [null,-1,null,null,null,null,null,null],
    ['quote',-1,null,null,null,null,null,null],
    ['custom',null,{text:['one'],isWordRandom:true,isTimeRandom:true,word:0,time:5,pipeDelimiter:false},null,null,null,null,null],
    ['custom',null,{text:['one'],isTimeRandom:true,word:-4,delimiter:'|'},null,null,null,null,null],
    ['custom',null,{text:['one'],mode:'random',limit:{mode:'time',value:Infinity}},null,null,null,null,null],
    [null,null,null,null,null,'owned_unknown',null,'owned_unknown'],
    [null,null,null,null,null,null,null,'none'],
    [null,null,null,null,1,null,null,null],
    ['custom',null,{text:[]},null,null,null,null,null],
    [null,'-1',null,null,null,null,null,null],
    [null,null,null,null,null,null,null,['owned_unknown']]];
  for(let i=0;i<extras.length;i++)await run('edge-'+i,extras[i]);
  for(const language of [null,'arabic'])
    await run('active-add-noquit-'+language,[null,null,null,null,null,language,null,['no_quit']],undefined,true);
  await run('busy-language',[null,null,null,null,null,'arabic',null,null],undefined,false,undefined,true);
  await run('warm-infinite-off',[null,null,null,null,null,'arabic',null,[]],
    {mode:'words',minWpm:'off',minWpmCustomSpeed:Infinity,minBurst:'flex',minBurstCustomSpeed:Infinity});
  await run('duplicate-funbox',[null,null,null,null,null,null,null,['no_quit','no_quit']]);
  await run('legacy-funbox-empty',[null,null,null,null,null,null,null,'']);
  await run('quote-infinite-number',['quote',Infinity,null,null,null,null,null,null]);
  await run('numeric-exponential-mode2',[null,1e21,null,null,null,null,null,null]);
  await run('custom-code-units',['custom',null,{text:['','a|b','\ud800','e\u0301','é'],mode:'repeat',
    limit:{mode:'section',value:2.5},pipeDelimiter:true},null,null,null,null,null]);
  await run('custom-subunit',['custom',null,{text:['aa','bb'],mode:'repeat',
    limit:{mode:'word',value:0.5},pipeDelimiter:false},null,null,null,null,null]);
  await run('custom-large-limit',['custom',null,{text:['aa','bb'],mode:'shuffle',
    limit:{mode:'section',value:1e99},pipeDelimiter:false},null,null,null,null,null]);
  await run('custom-signed-zero',['custom',null,{text:['aa','bb'],mode:'repeat',
    limit:{mode:'time',value:-0},pipeDelimiter:false},null,null,null,null,null]);
  } else {
    const payload=['quote','42',{...incoming,pipeDelimiter:true},true,false,'arabic','expert',[]];
    for(const kind of ['quota','generic']) {
      for(const index of [1,2,3,4,5,-1])
        await run('custom-failure-'+kind+'-'+index,payload,undefined,false,undefined,false,{customTextSettings:[index]},kind);
      await run('config-failure-'+kind,payload,undefined,false,undefined,false,{config:[1]},kind);
    }
    await run('combined-schema-and-write',['quote','42',{text:['one'],isTimeRandom:true,word:-4,delimiter:'|'},
      null,null,null,null,null],undefined,false,undefined,false,{config:[1],customTextSettings:[1]});
    await run('parse-rejects-before-writes',[null,null,incoming,null,1,null,null,null],undefined,false,undefined,false,
      {config:[-1],customTextSettings:[-1]});
    await run('no-op-has-no-storage-attempt',Array(8).fill(null),undefined,false,undefined,false,
      {config:[-1],customTextSettings:[-1]});
    await run('active-noquit-storage-failure',payload,{mode:'words',funbox:['no_quit']},true,undefined,false,
      {customTextSettings:[1]});
  }
  verify();await new Promise((resolve,reject)=>process.stdout.write(JSON.stringify({fixtures}),error=>error?reject(error):resolve()));
}
