// QA only: pinned form/InputField callbacks, real Zod schema, setters and store.
// Form/field API and DOM events are owned adapters, not the TanStack form engine.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

export async function checkBackgroundAddressForm({context,simulation,bus,defaults,store,drain,read,expression}) {
  const component=read('components/pages/settings/custom-setting/CustomBackground.tsx');
  const field=read('components/ui/form/InputField.tsx'),utils=read('components/ui/form/utils.ts');
  const prefix=component.slice(component.indexOf('  const savedIndicator ='),component.indexOf('  const [hasLocalBackground]'));
  const fieldPrefix=field.slice(field.indexOf('  const [shake,'),field.indexOf('\n  return ('));
  const convert=field.slice(field.indexOf('function convertStringToValue<'));
  const validator=utils.slice(utils.indexOf('export function fromSchema<'),utils.indexOf('export function handleResult('));
  const source=validator.replace('export ','')+convert+`
    globalThis.mountAddressForm=()=>{${prefix}
      return {form,validators:${expression(component,'validators')},submit:${expression(component,'onSubmit')}};};
    globalThis.mountAddressField=props=>{${fieldPrefix}
      return {input:${expression(field,'onInput')},blur:${expression(field,'onBlur')}};};`;
  vm.runInContext(stripTypeScriptTypes(source,{mode:'transform'}),context);
  let flashes=0,api,mounted;
  Object.assign(context,{useSavedIndicator:()=>({flash:()=>{flashes++;}}),createForm:factory=>{
    const form=factory();form.handleSubmit=()=>{
      if(!api.state.meta.isValid)return;
      form.onSubmit({value:{customBackground:api.state.value}});
    };return form;
  }});
  const initial='https://example.invalid/before.png';
  const values=[initial,'https://example.invalid/after.jpg','https://example.invalid/after.PNG',
    'https://example.invalid/image.webp?token=owned','https://example.invalid/image?file=a.png',
    'https://example.invalid/after.png  ','https://example.invalid/after.png\n',
    ' https://example.invalid/after.png','\uFEFFhttps://example.invalid/after.png',' ','',
    'ftp://example.invalid/image.png','HTTPS://example.invalid/image.png',
    'https://example.invalid/image.svg','https://example.invalid/\"a.png',
    'https://example.invalid/'+ 'a'.repeat(2048)+'.png'];
  const fixtures=[];
  for(const event of ['blur','submit'])for(const raw of values) {
    Object.assign(simulation.Config,context.structuredClone(defaults),{mode:'words',words:5,fontFamily:'Courier',customBackground:initial});
    store.setFullConfigStore(context.structuredClone(simulation.Config));
    simulation.flags={testActive:true,authenticated:false,documentComplete:true};
    bus.dispatch({key:'fullConfigChangeFinished'});await drain();simulation.saves=[];simulation.configCheckpoints=[];flashes=0;
    mounted=context.mountAddressForm();
    api={name:'customBackground',form:{options:mounted.form},state:{value:mounted.form.defaultValues.customBackground,meta:{isTouched:false,isValid:true}},
      handleChange(value){this.state.value=value;this.state.meta.isValid=mounted.validators.onChange({value})===undefined;},
      handleBlur(){this.state.meta.isTouched=true;mounted.validators.onBlur();}};
    const input=context.mountAddressField({field:()=>api}),frames=[];
    let prevented=0,stopped=0;
    const snapshot=()=>({runtime:simulation.Config.customBackground,settings:store.getConfig.customBackground,
      draft:api.state.value,valid:api.state.meta.isValid,saves:simulation.saves.length,flashes,prevented,stopped});
    frames.push(snapshot());input.input({target:{value:raw}});await drain();frames.push(snapshot());
    const submit=()=>event==='blur'?input.blur():mounted.submit({preventDefault(){prevented++;},stopPropagation(){stopped++;}});
    submit();await drain();frames.push(snapshot());submit();await drain();frames.push(snapshot());
    assert.equal(frames[1].saves,0);
    if(raw===frames[2].settings||!frames[1].valid)assert.equal(frames[3].saves,frames[2].saves);
    else assert.equal(frames[3].saves,frames[2].saves+1);
    if(!frames[1].valid)assert.equal(frames[2].saves,0);
    assert.equal(frames[2].saves,frames[2].flashes);
    fixtures.push({event,raw,frames});
  }
  assert.equal(fixtures.length,32);return fixtures;
}
