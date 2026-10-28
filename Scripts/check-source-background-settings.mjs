// QA only. Execute the pinned TSX callback bodies and real Solid effects/store.
// Owned refs model range values; actual browser range sanitation is tested separately.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {checkBackgroundAddressForm} from './check-source-background-address-form.mjs';
import {checkBackgroundFileSelection} from './check-source-background-file-selection.mjs';

export async function checkBackgroundSettings({context,simulation,bus,setters,defaults,verify,store,drain,frontend,image}) {
  const read=file=>fs.readFileSync(path.join(frontend,file),'utf8');
  function expression(source,name) {
    const start=source.indexOf(name+'={');assert.ok(start>=0,name);
    let depth=1,index=start+name.length+2,begin=index;
    // These pinned attributes contain no braces inside string literals.
    for(;index<source.length;index++) {
      if(source[index]==='{')depth++;
      if(source[index]==='}'&&!--depth)return source.slice(begin,index);
    }
    throw new Error('Unclosed attribute '+name);
  }
  const filters=read('components/pages/settings/custom-setting/CustomBackgroundFilters.tsx');
  const slider=read('components/common/Slider.tsx');
  const blocks=filters.match(/<Slider\s[\s\S]*?\/>/g);assert.equal(blocks.length,4);
  const props=blocks.map(block=>'{'+['min','max','step','ref','text','onEveryChange','onChange'].map(name=>name+':'+expression(block,name)).join(',')+',get value(){return '+expression(block,'value')+';}}');
  const prefix=filters.slice(filters.indexOf('  let refBlur:'),filters.indexOf('\n  return ('));
  const sliderPrefix=slider.slice(slider.indexOf('  const [value,'),slider.indexOf('\n  return ('));
  const source=`globalThis.mountSettings=()=>createRoot(dispose=>{${prefix}
    const propsList=[${props.join(',')}];
    return {dispose,sliders:propsList.map(props=>{${sliderPrefix}
      const ref={value:''};props.ref(ref);
      createEffect(()=>{ref.value=String(Math.min(props.max,Math.max(props.min,value())));});
      return {ref,label:textToDisplay,input:${expression(slider,'onInput')},change:${expression(slider,'onChange')}};
    })};});`;
  vm.runInContext(stripTypeScriptTypes(source,{mode:'transform'}),context);
  const fixtures=[];
  for(const initial of [[0,1,1,1],[-1,3,0.4,0.7]])for(let component=0;component<4;component++) {
    Object.assign(simulation.Config,context.structuredClone(defaults),{mode:'words',words:5,fontFamily:'Courier',
      customBackground:'https://example.invalid/before.png',customBackgroundFilter:initial.slice()});
    store.setFullConfigStore(context.structuredClone(simulation.Config));
    simulation.flags={testActive:true,authenticated:false,documentComplete:true};
    bus.dispatch({key:'fullConfigChangeFinished'});await drain();
    simulation.saves=[];simulation.configCheckpoints=[];
    const mounted=context.mountSettings(),frames=[];
    const snapshot=()=>({runtime:Array.from(simulation.Config.customBackgroundFilter),settings:Array.from(store.getConfig.customBackgroundFilter),
      refs:mounted.sliders.map(s=>Number(s.ref.value)),labels:mounted.sliders.map(s=>s.label()),
      saves:simulation.saves.length,style:{...image().style}});
    const input=(index,value)=>{const s=mounted.sliders[index];s.ref.value=String(value);s.input({target:s.ref});};
    const change=index=>{const s=mounted.sliders[index];s.change({target:s.ref});};
    frames.push(snapshot());
    input(component,0.5);await drain();frames.push(snapshot());assert.equal(simulation.saves.length,0);
    change(component);await drain();frames.push(snapshot());assert.equal(simulation.saves.length,1);
    change(component);await drain();frames.push(snapshot());assert.equal(simulation.saves.length,1);
    const second=(component+1)%4;
    input(second,0.8);await drain();frames.push(snapshot());
    setters.setConfig('fontSize',2);await drain();frames.push(snapshot());
    assert.deepEqual(frames[5].style,frames[4].style);
    mounted.dispose();fixtures.push({initial,component,second,frames});
  }
  const addressFixtures=await checkBackgroundAddressForm({context,simulation,bus,defaults,store,drain,read,expression});
  const {fileFixtures,removalFixtures}=await checkBackgroundFileSelection({context,simulation,bus,defaults,store,drain,read,expression});
  verify();return {fixtures,addressFixtures,fileFixtures,removalFixtures};
}
