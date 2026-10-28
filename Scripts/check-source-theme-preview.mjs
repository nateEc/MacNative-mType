// QA only. Execute pinned controller functions and the locked debounce package
// against owned colors, a deterministic clock, and explicit DOM/shuffle adapters.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';

export async function checkThemePreview({context, simulation, frontend, bus, setters, defaults, verify, store}) {
  const archive=process.env.TYPEBAR_THEME_DEBOUNCE_ARCHIVE;
  assert.ok(archive,'TYPEBAR_THEME_DEBOUNCE_ARCHIVE required');
  const integrity='sha512-'+createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
  assert.equal(integrity,'sha512-B71/4oyj61iNH0KeCamLuE2rmKuTO5byTOSVwECM5FA7TiAiAW+UqTKZ9ERueC4qvgSttUhdmq1mXC3kJqGX7A==');
  assert.ok(fs.readFileSync(path.resolve(frontend,'../../../pnpm-lock.yaml'),'utf8').includes(integrity));
  const unpack=name=>execFileSync('tar',['-xOf',archive,name],{encoding:'utf8',maxBuffer:2**20});
  assert.equal(JSON.parse(unpack('package/package.json')).version,'5.0.2');
  let now=1000,nextTimer=1,dark=false,pending=[],shown=null,indicator=null,media,subgroup=null,customCount=2;
  const timers=new Map();
  Object.assign(context,{Date:class extends Date {static now(){return now;}},
    setTimeout:(action,delay)=>{const id=nextTimer++;timers.set(id,{at:now+delay,action});return id;},
    clearTimeout:id=>timers.delete(id)});
  const dependency=new vm.SourceTextModule(unpack('package/esm/index.js'),{context});
  await dependency.link(()=>{throw new Error('Unexpected debounce import');});await dependency.evaluate();
  function extract(file,from,to) {
    const source=fs.readFileSync(path.join(frontend,file),'utf8'),a=source.indexOf(from),b=source.indexOf(to,a);
    assert.ok(a>=0&&b>a,from);
    return stripTypeScriptTypes((source.slice(a,b)+(to==='\n}\n'?'\n}':'')).replace(/^export /gm,''),{mode:'transform'});
  }
  for(const name of ['hexToHSL','isColorDark','isColorLight'])
    vm.runInContext(extract('utils/colors.ts',`export function ${name}(`,'\n}\n'),context);
  vm.runInContext(extract('utils/arrays.ts','export function areSortedArraysEqual','\n}\n'),context);
  const colors=Array.from({length:10},(_,i)=>'#'+(0x102030+i*0x090909).toString(16).padStart(6,'0'));
  const customThemes=[{_id:'owned-one',name:'Owned_One',colors},{_id:'owned-two',name:'Owned_Two',colors:colors.slice().reverse()}];
  const themes=Object.fromEntries(['serika_dark','serika','dracula','nord'].map(name=>[name,{name,bg:'#102030',main:'#203040',text:'#304050'}]));
  Object.assign(context,{Config:simulation.Config,setConfig:setters.setConfig,debounce:dependency.namespace.debounce,
    themes,ThemesList:Object.values(themes),Arrays:{areSortedArraysEqual:context.areSortedArraysEqual,shuffle:()=>{}},
    CustomThemes:{__nonReactive:{getCustomThemes:()=>customThemes.slice(0,customCount),getCustomTheme:id=>customThemes.find(t=>t._id===id)}},
    qs:()=>({addClass:()=>{},removeClass:()=>{}}),setTheme:theme=>{shown=structuredClone(theme);},
    setThemeIndicator:value=>{indicator=structuredClone(value);},prefersColorSchemeDark:()=>dark,
    window:{matchMedia:()=>({matches:dark,addEventListener:(_,callback)=>{media=callback;}})},
    configEvent:{subscribe:callback=>bus.subscribe(event=>pending.push(Promise.resolve(callback(event))))},
    applyCustomBackground:async()=>{},applyCustomBackgroundSize:()=>{},showNoticeNotification:()=>simulation.notices.push(false),
    isAuthenticated:()=>!!simulation.flags.authenticated,setCommandlineSubgroup:value=>{subgroup=value;},showModal:()=>{}});
  vm.runInContext(extract('controllers/theme-controller.ts','export let randomTheme:','function applyCustomBackgroundSize(')
    +extract('controllers/theme-controller.ts','window\n  .matchMedia?', 'window.addEventListener("customBackgroundFailed"'),context);
  vm.runInContext('globalThis.footerClick=((themes)=>{'+extract('components/layout/footer/ThemeIndicator.tsx',
    '  const handleClick =','\n\n  return (')+';return handleClick;})(()=>CustomThemes.__nonReactive.getCustomThemes());',context);
  vm.runInContext(extract('commandline/lists/add-or-remove-theme-to-favorites.ts','const commands: Command[] = [','export default commands')
    +'\nglobalThis.favoriteCommands=commands;',context);
  async function drain() {
    for(let count=0;pending.length;count++) {assert.ok(count<30);const batch=pending;pending=[];await Promise.all(batch);}
  }
  if(store) {
    vm.runInContext(extract('../../../packages/util/src/numbers.ts','export function randomIntFromRange','\n}\n'),context);
    vm.runInContext(extract('utils/arrays.ts','export function shuffle','\n}\n'),context);
    context.Arrays.shuffle=context.shuffle;
    Object.assign(context,{ceil:Math.ceil,floor:Math.floor,random:()=>0});
    const keys=['theme','themeLight','themeDark','autoSwitchTheme','customTheme','customThemeColors','favThemes','randomTheme','fontSize'];
    // The real Solid store exposes array proxies; copy JSON config values by
    // enumeration in its own realm instead of structuredClone(proxy).
    const pick=value=>Object.fromEntries(keys.map(key=>[key,context.structuredClone(value[key])]));
    const fixtures=[];
    for(const auto of [false,true])for(const mode of ['on','fav']) {
      timers.clear();pending=[];dark=false;
      Object.assign(simulation.Config,context.structuredClone(defaults),{theme:'serika_dark',themeLight:'serika',themeDark:'dracula',
        autoSwitchTheme:auto,customTheme:true,customThemeColors:context.structuredClone(colors),randomTheme:'off',
        favThemes:context.structuredClone(['nord','serika','dracula']),fontSize:2});
      store.setFullConfigStore(context.structuredClone(simulation.Config));
      simulation.flags={testActive:false,authenticated:false,customThemeCount:0};
      simulation.events=[];simulation.saves=[];simulation.notices=[];simulation.configCheckpoints=[];
      vm.runInContext('randomTheme=null;themesList=[];randomThemeIndex=0;previewState=null;isPreviewingTheme=false;',context);
      const frames=[];
      const snapshot=()=>({runtime:pick(simulation.Config),settings:pick(store.getConfig),
        saved:simulation.configCheckpoints.map(item=>({key:item.key,value:pick(item.value)})),
        events:structuredClone(simulation.events),shown:shown?.name,active:vm.runInContext('randomTheme',context),indicator:structuredClone(indicator)});
      bus.dispatch({key:'fullConfigChangeFinished'});await drain();frames.push(snapshot());
      setters.setConfig('randomTheme',mode);await drain();frames.push(snapshot());
      for(let draw=0;draw<4;draw++) {
        await context.randomizeTheme();await drain();frames.push(snapshot());
      }
      setters.setConfig('fontSize',1.5);await drain();frames.push(snapshot());
      fixtures.push({auto,mode,frames});
    }
    verify();return {fixtures};
  }
  async function advance(delta) {
    const end=now+delta;
    for(let count=0;;count++) {
      assert.ok(count<100);const item=[...timers].filter(([,t])=>t.at<=end).sort((a,b)=>a[1].at-b[1].at||a[0]-b[0])[0];
      if(!item)break;now=item[1].at;timers.delete(item[0]);item[1].action();await drain();
    }
    now=end;await drain();
  }
  const preview=name=>({kind:'preview',name}),tick=ms=>({kind:'tick',ms}),clear={kind:'clear'};
  const field=(key,value)=>({kind:'field',key,value});
  const scenarios=[
    [preview('nord'),tick(249),tick(1),clear,tick(300)],
    [preview('nord'),tick(100),preview('serika'),tick(249),tick(1),clear],
    [preview('nord'),tick(100),clear,tick(400)],
    [preview('owned-two'),tick(250),clear,clear],
    [preview('nord'),tick(250),field('favThemes',['serika_dark','nord']),clear],
    [preview('nord'),tick(250),field('fontSize',1.5),clear],
    [preview('nord'),tick(100),field('theme','dracula'),tick(300),clear],
    [preview('nord'),tick(250),field('theme','dracula'),clear,tick(300)],
    [preview('owned-two'),tick(250),{kind:'custom',name:'owned-two'},clear],
    [preview('nord'),tick(250),field('customTheme',true),clear],
    [preview('nord'),tick(250),{kind:'media'},clear],
    [preview('nord'),tick(100),{kind:'media'},tick(250),clear],
    [preview('nord'),tick(250),field('themeLight','nord'),clear],
    [preview('nord'),tick(250),field('themeDark','nord'),clear],
    [preview('nord'),tick(250),field('autoSwitchTheme',true),clear],
    [preview('nord'),tick(250),field('autoSwitchTheme',false),clear],
    [preview('nord'),tick(250),field('randomTheme','on'),clear],
    [preview('nord'),tick(250),{kind:'full'},tick(300),clear],
    [preview('nord'),tick(250),{kind:'footerShift'},clear],
    [preview('nord'),tick(250),{kind:'favoriteRemove'},{kind:'favoriteAdd'},clear],
  ];
  const fixtures=[];
  for(const auto of [false,true])for(const custom of [false,true])for(const systemDark of [false,true])for(const actions of scenarios) {
    now=1000;timers.clear();pending=[];dark=systemDark;
    vm.runInContext('randomTheme=null;previewState=null;isPreviewingTheme=false;',context);
    Object.assign(simulation.Config,structuredClone(defaults),{theme:'serika_dark',themeLight:'serika',themeDark:'dracula',autoSwitchTheme:auto,
      customTheme:custom,customThemeColors:colors,funbox:[],fontSize:2,favThemes:['serika_dark']});
    simulation.flags={testActive:false,authenticated:false,customThemeCount:0};simulation.events=[];simulation.saves=[];
    simulation.notices=[];simulation.configCheckpoints=[];
    const keys=['theme','themeLight','themeDark','autoSwitchTheme','customTheme','customThemeColors','favThemes','randomTheme','fontSize'];
    const values=()=>Object.fromEntries(keys.map(key=>[key,structuredClone(simulation.Config[key])]));
    const initial=values();bus.dispatch({key:'fullConfigChangeFinished'});await drain();
    const frames=[];
    const snapshot=()=>({shown,indicator,isPreviewing:vm.runInContext('isPreviewingTheme',context),runtime:values(),saves:simulation.saves.length});
    frames.push(snapshot());
    for(const action of actions) {
      switch(action.kind) {
      case 'preview': {
        const custom=customThemes.find(t=>t._id===action.name);
        context.preview(custom?'custom':action.name,custom?.colors);break;
      }
      case 'clear':await context.clearPreview();break;
      case 'tick':await advance(action.ms);break;
      case 'field':setters.setConfig(action.key,action.value);break;
      case 'custom': {
        const theme=customThemes.find(t=>t._id===action.name);setters.setConfig('customTheme',true);setters.setConfig('customThemeColors',theme.colors);break;
      }
      case 'media':dark=!dark;media({matches:dark});break;
      case 'footerShift':context.footerClick({shiftKey:true});break;
      case 'favoriteAdd':context.favoriteCommands[0].exec();break;
      case 'favoriteRemove':context.favoriteCommands[1].exec();break;
      case 'full':
        bus.dispatch({key:'fullConfigChange'});setters.setConfig('theme','dracula',{nosave:true});
        bus.dispatch({key:'fullConfigChangeFinished'});break;
      default:throw new Error(action.kind);
      }
      await drain();frames.push(snapshot());
    }
    fixtures.push({initial,systemDark,actions,frames});
  }
  const footerCases=[];
  for(const custom of [false,true])for(const authenticated of [false,true])for(const count of [0,2])for(const shift of [false,true]) {
    simulation.Config.autoSwitchTheme=false;simulation.Config.customTheme=custom;simulation.flags.authenticated=authenticated;
    customCount=count;subgroup=null;simulation.saves=[];simulation.notices=[];
    context.footerClick({shiftKey:shift});await drain();
    footerCases.push({custom,authenticated,count,shift,enabled:simulation.Config.customTheme,subgroup,notices:simulation.notices.length,saves:simulation.saves.length});
  }
  verify();return {customThemes,fixtures,footerCases};
}
