// QA only: actual remove callbacks, FileStorage, setter, bus and controller.
// Database read completions, storage errors and DOM are owned adapters.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

export async function checkBackgroundRemoval({context,simulation,bus,defaults,store,drain,read,expression,actualApply,body,commandBody,png}) {
  const local='data:image/png;base64,'+png.toString('base64');
  let stored,image,nextID=0,gated=false,reads=[],deletes=0,deleteFail=false,notices=[],applyErrors=[],busErrors=[],orphanErrors=[],applications=[];
  const unhandled=error=>orphanErrors.push(error.message);
  process.on('unhandledRejection',unhandled);
  Object.assign(context,{
    openDB:async()=>({async get(){if(!gated)return stored;return await new Promise((resolve,reject)=>reads.push({resolve,reject}));},
      async delete(){deletes++;if(deleteFail)throw new Error('owned deletion failure');stored=undefined;}}),
    showNoticeNotification:message=>notices.push(message),
    applyCustomBackground:(...args)=>{const result=actualApply(...args);result.catch(error=>applyErrors.push(error.message));applications.push(result);return result;},
    document:{querySelector:()=>({replaceChildren(value){image=value;}}),
      createElement:()=>({id:++nextID,attributes:{},style:{},setAttribute(key,value){this.attributes[key]=value;}})},
    qs:selector=>selector==='.customBackground img'?image&&{remove(){image=undefined;},setStyle(value){Object.assign(image.style,value);}}:
      {hide(){},show(){},addClass(){},removeClass(){}}
  });
  const component=read('components/pages/settings/custom-setting/CustomBackground.tsx');
  const scenarios=[];
  for(const address of ['','https://example.invalid/before.png']) {
    for(const a of ['absent','empty','file','error'])for(const b of ['absent','empty','file','error'])for(const order of [[0,1],[1,0]])
      scenarios.push({entry:'command',address,local:true,results:[a,b],order});
    for(const a of ['absent','empty','file','error'])scenarios.push({entry:'settings',address,local:true,results:[a],order:[0]});
    for(const entry of ['command','settings'])scenarios.push({entry,address,local:true,results:[],order:[],deleteFail:true});
    scenarios.push({entry:'command',address,local:false,results:address?['absent','absent']:[],order:address?[0,1]:[]});
  }
  const fixtures=[];
  try {for(const sample of scenarios) {
    gated=false;stored=sample.local?local:undefined;image=undefined;reads=[];deletes=0;deleteFail=false;
    notices=[];applyErrors=[];busErrors=[];orphanErrors=[];applications=[];
    context.FileStorage=vm.runInContext(stripTypeScriptTypes('(()=>{'+body+';return new FileStorage();})()',{mode:'transform'}),context);
    context.fileStorage=context.FileStorage;context.FileStorage.track('LocalBackgroundFile');
    vm.runInContext(stripTypeScriptTypes('globalThis.settingsRemove='+expression(component,'onClick')+';'+
      'globalThis.removeCommand=(()=>{'+commandBody+';return customBackgroundCommand.subgroup.list[2];})();',{mode:'transform'}),context);
    Object.assign(simulation.Config,context.structuredClone(defaults),{mode:'words',words:5,fontFamily:'Courier',customBackground:sample.address});
    store.setFullConfigStore(context.structuredClone(simulation.Config));simulation.flags={testActive:true,authenticated:false,documentComplete:true};
    bus.dispatch({key:'fullConfigChangeFinished'});await drain();simulation.saves=[];applications=[];
    const available=sample.entry==='settings'?stored!==undefined:await context.removeCommand.available();
    const frames=[],snapshot=()=>({address:simulation.Config.customBackground,settings:store.getConfig.customBackground,
      stored:stored!==undefined,version:context.FileStorage.track('LocalBackgroundFile'),deletes,reads:reads.length,saves:simulation.saves.length,
      selected:image?(image.attributes.src===local?'file':image.attributes.src):null,image:image?.id??null,
      notices:notices.length,applyErrors:applyErrors.length,busErrors:busErrors.length,orphanErrors:orphanErrors.length});
    frames.push(snapshot());gated=true;deleteFail=!!sample.deleteFail;
    const completion=available?Promise.resolve(sample.entry==='command'?context.removeCommand.exec():context.settingsRemove()):Promise.resolve();
    // Run only microtasks until both independent getFile calls are suspended.
    for(let i=0;i<20;i++)await Promise.resolve();
    assert.equal(reads.length,sample.results.length);frames.push(snapshot());
    for(const index of sample.order) {
      const result=sample.results[index];
      if(result==='error')reads[index].reject(new Error('owned read '+index+' failure'));
      else reads[index].resolve(result==='absent'?undefined:result==='empty'?'':local);
      for(let i=0;i<20;i++)await Promise.resolve();
      frames.push(snapshot());
    }
    await completion;await Promise.allSettled(applications);
    try{await drain();}catch(error){busErrors.push(error.message);}
    await new Promise(setImmediate);await new Promise(setImmediate);
    frames[frames.length-1]=snapshot();
    if(sample.deleteFail){assert.equal(simulation.saves.length,0);assert.equal(stored,local);}
    else if(available){assert.equal(stored,undefined);assert.equal(context.FileStorage.track('LocalBackgroundFile'),1);assert.equal(simulation.saves.length,sample.entry==='command'?1:0);}
    if(sample.entry==='command'&&!sample.deleteFail&&available)assert.equal(notices.length,sample.results[1]==='error'?1:0);
    fixtures.push({...sample,available,frames});
  }} finally {process.removeListener('unhandledRejection',unhandled);}
  assert.equal(fixtures.length,78);return fixtures;
}
