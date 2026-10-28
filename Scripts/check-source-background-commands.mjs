// QA only: real command functions, setters, Solid, theme and test listeners.
// All image/DOM/storage implementations and URI inputs here are owned adapters.
import assert from 'node:assert/strict';
import vm from 'node:vm';
export async function checkBackgroundCommands({context,simulation,bus,setters,defaults,verify,store,extract,drain,metadata,frontend,backgroundSettingsMode}) {
  let image=null,nextID=0,restarts=0,reads=0;
  const number=value=>Object.is(value,-0)?'-0':String(value);
  const filters=value=>Array.from(value,number);
  const pick=value=>({address:value.customBackground,fit:value.customBackgroundSize,filter:filters(value.customBackgroundFilter)});
  Object.assign(context,{getConfig:store.getConfig,getActivePage:()=> 'test',restart:()=>{restarts++;throw new Error('Background command restarted test');},
    capitalizeFirstLetter:value=>value[0].toUpperCase()+value.slice(1),
    fileStorage:{getFile:async()=>{reads++;return undefined;}},
    document:{querySelector:()=>({replaceChildren(value){image=value;}}),
      createElement:()=>({id:++nextID,attributes:{},style:{},setAttribute(key,value){this.attributes[key]=value;}})},
    qs:selector=>{
      if(selector==='.customBackground img'){
        const current=image;if(!current)return undefined;
        return {remove(){if(image===current)image=null;},setStyle(value){Object.assign(current.style,value);}};
      }
      return {hide(){},show(){},addClass(){},removeClass(){}};
    }});
  vm.runInContext(extract('controllers/theme-controller.ts','function applyCustomBackgroundSize():','\nwindow\n'),context);
  vm.runInContext('globalThis.backgroundFilterCommands=(()=>{'+extract('commandline/lists/background-filter.ts','const subgroup:','export default commands')+';return subgroup.list;})();',context);
  vm.runInContext(extract('commandline/util.ts','function buildSubgroupCommand<','export const __testing'),context);
  vm.runInContext(extract('test/test-logic.ts','configEvent.subscribe(','timerEvent.subscribe('),context);
  for(const key of ['customBackground','customBackgroundSize','customBackgroundFilter'])assert.equal(metadata[key].changeRequiresRestart,false);
  if(backgroundSettingsMode) {
    const {checkBackgroundSettings}=await import('./check-source-background-settings.mjs');
    return await checkBackgroundSettings({context,simulation,bus,setters,defaults,verify,store,drain,frontend,image:()=>image});
  }
  const fixtures=[];
  for(let component=0;component<4;component++)for(const input of ['0.75','-1.25suffix','2.5e2','Infinity','-0','0x10','',' ','invalid']){
    Object.assign(simulation.Config,context.structuredClone(defaults),{mode:'words',words:5,fontFamily:'Courier',funbox:['no_quit'],
      customBackground:'https://example.invalid/before.png',customBackgroundSize:'cover',customBackgroundFilter:[0,1,1,1]});
    store.setFullConfigStore(context.structuredClone(simulation.Config));
    simulation.flags={testActive:true,authenticated:false,documentComplete:true};
    bus.dispatch({key:'fullConfigChangeFinished'});await drain();
    simulation.events=[];simulation.saves=[];simulation.configCheckpoints=[];restarts=0;reads=0;
    const frames=[],snapshot=()=>({runtime:pick(simulation.Config),settings:pick(store.getConfig),
      image:image?{id:image.id,src:image.attributes.src,style:{...image.style}}:null,
      saved:simulation.configCheckpoints.map(x=>({key:x.key,...pick(x.value)})),restarts,reads});
    frames.push(snapshot());
    context.backgroundFilterCommands[component].exec({input});await drain();frames.push(snapshot());
    assert.deepEqual(frames[1].image,frames[0].image,'Command saves filters without repainting');
    setters.setConfig('fontSize',2);await drain();frames.push(snapshot());
    const size=context.buildSubgroupCommand('customBackgroundSize','contain',{});size.exec();await drain();frames.push(snapshot());
    assert.equal(image.style.objectFit,'contain');assert.equal(image.id,frames[0].image.id);
    const address=context.buildInputCommand({key:'customBackground',isPartOfSubgroup:false,configMeta:metadata.customBackground});
    const rawAddress='\uFEFF  https://example.invalid/after.png \n';
    address.exec({input:rawAddress});await drain();frames.push(snapshot());
    assert.notEqual(image.id,frames[0].image.id);assert.equal(image.attributes.src,'https://example.invalid/after.png');
    assert.equal(restarts,0);assert.equal(reads,1);
    const representable=Array.from(simulation.Config.customBackgroundFilter).every(x=>!Number.isNaN(x))&&input!=='';
    if(representable)assert.equal(frames[1].saved.length,1);
    fixtures.push({component,input,rawAddress,representable,frames});
  }
  verify();return {fixtures};
}
