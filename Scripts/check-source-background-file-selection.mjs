// QA only: actual file callbacks and FileStorage methods, real Solid signals.
// FileReader, database transactions, DOM and failures are owned adapters.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {deflateSync} from 'node:zlib';
import {checkBackgroundRemoval} from './check-source-background-removal.mjs';

export async function checkBackgroundFileSelection({context,simulation,bus,defaults,store,drain,read,expression}) {
  // Independently constructed one-pixel RGBA PNG, never a reference asset.
  function chunk(type,body) {
    const value=Buffer.concat([Buffer.from(type),body]);let crc=0xffffffff;
    for(const byte of value) {crc^=byte;for(let bit=0;bit<8;bit++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}
    const size=Buffer.alloc(4),checksum=Buffer.alloc(4);size.writeUInt32BE(body.length);checksum.writeUInt32BE((crc^0xffffffff)>>>0);
    return Buffer.concat([size,value,checksum]);
  }
  const header=Buffer.alloc(13);header.writeUInt32BE(1,0);header.writeUInt32BE(1,4);header[8]=8;header[9]=6;
  const png=Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),
    chunk('IDAT',deflateSync(Buffer.from([0,31,47,71,255]))),chunk('IEND',Buffer.alloc(0))]);
  let stored,image,activeInput,nextID=0,writes=0,reads=0,fileReads=0,notices=[],errors=[],applyErrors=[],readerCallbacks=[],applications=[],scenario,didStore=false;
  const actualApply=context.applyCustomBackground;
  Object.assign(context,{
    openDB:async()=>({async put(_table,value){writes++;if(scenario?.storeFail)throw new Error('owned store failure');stored=value;didStore=true;},
      async get(){reads++;if(scenario?.backgroundReadFail&&didStore)throw new Error('owned background read failure');return stored;}}),
    buildCommandForConfigKey:()=>({id:'owned-unused-address-command'}),
    showNoticeNotification:message=>notices.push(message),
    FileReader:class {
      readAsDataURL(file) {fileReads++;readerCallbacks.push(async()=>{
        if(scenario.readFail){this.onerror?.(new Error('owned file read failure'));return;}
        this.result='data:'+file.type+';base64,'+file.bytes.toString('base64');
        await this.onload?.({target:{result:this.result}});
      });}
    },
    applyCustomBackground:(...args)=>{
      const result=actualApply(...args);result.catch(error=>applyErrors.push(error.message));applications.push(result);return result;
    },
    document:{body:{appendChild(input){activeInput=input;},removeChild(input){assert.equal(activeInput,input);activeInput=undefined;}},
      querySelector:()=>({replaceChildren(value){image=value;}}),
      createElement:kind=>kind==='input'?{style:{},value:'owned-selection',click(){}}:
        {id:++nextID,attributes:{},style:{},setAttribute(key,value){this.attributes[key]=value;}}},
    qs:selector=>selector==='.customBackground img'?image&&{remove(){image=undefined;},setStyle(value){Object.assign(image.style,value);}}:
      {hide(){},show(){},addClass(){},removeClass(){}}
  });
  const storage=read('utils/file-storage.ts');
  const body=storage.slice(storage.indexOf('class FileStorage {'),storage.indexOf('export default new FileStorage()'));
  const component=read('components/pages/settings/custom-setting/CustomBackground.tsx');
  const reader=component.slice(component.indexOf('  const readFileAsDataURL ='),component.indexOf('\n  return ('));
  const commands=read('commandline/lists/custom-background.ts');
  const commandBody=commands.slice(commands.indexOf('const fromMeta ='),commands.indexOf('const commands:'));
  function mount() {
    context.FileStorage=vm.runInContext(stripTypeScriptTypes('(()=>{'+body+';return new FileStorage();})()',{mode:'transform'}),context);
    context.fileStorage=context.FileStorage;
    vm.runInContext(stripTypeScriptTypes('globalThis.settingsFileUpload=(()=>{'+reader+';return '+expression(component,'onChange')+';})();'+
      'globalThis.fileCommands=(()=>{'+commandBody+';return customBackgroundCommand.subgroup.list;})();',{mode:'transform'}),context);
    context.FileStorage.track('LocalBackgroundFile');
  }
  const cases=[
    {name:'png',type:'image/png'},{name:'jpeg',type:'image/jpeg'},{name:'jpg',type:'image/jpg'},
    {name:'gif',type:'image/gif'},{name:'webp',type:'image/webp'},{name:'unanchored-mime',type:'ximage/png-suffix'},
    {name:'empty',type:'image/png',bytes:Buffer.alloc(0)},{name:'corrupt',type:'image/png',bytes:Buffer.from('owned corrupt png')},
    {name:'uppercase-mime',type:'image/PNG'},{name:'svg-mime',type:'image/svg+xml'},
    {name:'no-mime',type:''},{name:'no-file',type:'image/png',noFile:true},
    {name:'read-failure',type:'image/png',readFail:true},{name:'store-failure',type:'image/png',storeFail:true},
    {name:'background-read-failure',type:'image/png',backgroundReadFail:true},{name:'pdf-mime',type:'application/pdf'}
  ];
  const fixtures=[];
  for(const entry of ['settings','command'])for(const sample of cases) {
    scenario=sample;stored=undefined;image=undefined;activeInput=undefined;writes=0;reads=0;fileReads=0;didStore=false;
    notices=[];errors=[];applyErrors=[];readerCallbacks=[];applications=[];mount();
    Object.assign(simulation.Config,context.structuredClone(defaults),{mode:'words',words:5,fontFamily:'Courier',customBackground:'https://example.invalid/before.png'});
    store.setFullConfigStore(context.structuredClone(simulation.Config));simulation.flags={testActive:true,authenticated:false,documentComplete:true};
    bus.dispatch({key:'fullConfigChangeFinished'});await drain();simulation.saves=[];
    const frames=[],snapshot=input=>({stored:stored??null,version:context.FileStorage.track('LocalBackgroundFile'),
      image:image?{id:image.id,src:image.attributes.src}:null,writes,reads,fileReads,saves:simulation.saves.length,
      address:simulation.Config.customBackground,notices:[...notices],errors:[...errors],applyErrors:[...applyErrors],
      inputPresent:entry==='settings'||activeInput!==undefined,inputValue:input?.value??null});
    let input={value:'owned-selection'};
    frames.push(snapshot(input));
    if(entry==='command') {assert.equal(await context.fileCommands[1].available(),true);await context.fileCommands[1].exec();input=activeInput;}
    const bytes=sample.bytes??png;input.files=sample.noFile?[]:[{type:sample.type,bytes}];
    const completion=Promise.resolve(entry==='settings'?context.settingsFileUpload({target:input}):input.onchange({target:input})).catch(error=>errors.push(error.message));
    while(readerCallbacks.length)await readerCallbacks.shift()();
    await completion;await Promise.allSettled(applications);await drain();frames.push(snapshot(input));
    assert.equal(simulation.saves.length,0);assert.equal(simulation.Config.customBackground,'https://example.invalid/before.png');
    assert.equal(fileReads,sample.noFile||!/image\/(jpeg|jpg|png|gif|webp)/.test(sample.type)?0:1);
    if(stored!==undefined){assert.equal(context.FileStorage.track('LocalBackgroundFile'),1);assert.equal(writes,1);}
    if(entry==='command')assert.equal(activeInput,undefined,'Command always cleans up its temporary input');
    if(sample.readFail||sample.storeFail||sample.noFile)assert.equal(image.id,frames[0].image.id);
    if(sample.backgroundReadFail) {assert.equal(image.id,frames[0].image.id);assert.equal(applyErrors.length,1);assert.notEqual(stored,undefined);}
    else if(stored!==undefined)assert.equal(image.attributes.src,stored);
    fixtures.push({entry,name:sample.name,mimeType:sample.type,base64:bytes.toString('base64'),
      representable:!sample.noFile&&!sample.readFail&&!sample.storeFail&&!sample.backgroundReadFail,frames});
  }
  assert.equal(fixtures.length,32);
  const removalFixtures=await checkBackgroundRemoval({context,simulation,bus,defaults,store,drain,read,expression,actualApply,body,commandBody,png});
  return {fileFixtures:fixtures,removalFixtures};
}
