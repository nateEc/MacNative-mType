// QA only: complete pinned candidate, shuffle and draw functions over owned
// names/colors. Rendering and the customTheme setter's subscribers are adapters.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';
const root=path.resolve(process.argv[2]??'');
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
function extract(file,from,to) {
  const source=fs.readFileSync(path.join(root,file),'utf8'),a=source.indexOf(from),b=source.indexOf(to,a);
  assert.ok(a>=0&&b>a,from);
  return stripTypeScriptTypes((source.slice(a,b)+(to==='\n}\n'?'\n}':'')).replace(/^export /gm,''),{mode:'transform'});
}
const frontend='frontend/src/ts/';
const entries=[{name:'serika',bg:'#f0e0d0',dark:false},{name:'serika_dark',bg:'#102030',dark:true},
  {name:'dracula',bg:'#eeeeee',dark:false},{name:'nord',bg:'#111111',dark:true}];
const samples=[0,0.99,0.25,0.75,0.5,0.125,0.875,0.375];
let dark=false,calls=0,customIDs=[],requests=[],applied=[],notices=[];
const Config={randomTheme:'off',favThemes:[],customTheme:true,theme:'serika_dark'};
const context=vm.createContext({Config,Math,ceil:Math.ceil,floor:Math.floor,
  random:()=>samples[calls++%samples.length],prefersColorSchemeDark:()=>dark,
  themes:Object.fromEntries(entries.map(x=>[x.name,{bg:x.bg}])),ThemesList:entries.map(x=>({name:x.name,bg:x.bg})),
  CustomThemes:{__nonReactive:{getCustomThemes:()=>customIDs.map(_id=>({_id})),
    getCustomTheme:id=>customIDs.includes(id)?{colors:id}:undefined}},
  setConfig:(key,value,options)=>{requests.push({key,value,nosave:options?.nosave??false});Config[key]=value;},
  apply:async(name,colors)=>{applied.push({theme:name,customID:colors??null});},
  showNoticeNotification:message=>notices.push(message)});
vm.runInContext(extract('packages/util/src/numbers.ts','export function randomIntFromRange(', '\n}\n'),context);
vm.runInContext(extract(frontend+'utils/arrays.ts','export function shuffle(', '\n}\n'),context);
context.Arrays={shuffle:context.shuffle};
for(const name of ['hexToHSL','isColorDark','isColorLight'])
  vm.runInContext(extract(frontend+'utils/colors.ts',`export function ${name}(`,'\n}\n'),context);
for(const entry of entries)assert.equal(context.isColorDark(entry.bg),entry.dark);
vm.runInContext('let randomTheme=null,randomThemeIndex=0;\n'+extract(frontend+'controllers/theme-controller.ts',
  'let themesList:', 'function applyCustomBackgroundSize('),context);
const mode=value=>({kind:'mode',value}),draw={kind:'draw'},fav=value=>({kind:'favorites',names:value});
const presets=[];
for(const value of ['off','on','fav','light','dark','auto','custom'])
  for(const favorites of [[],['nord','serika','dracula'],['nord','nord','serika']])
    for(const isDark of [false,true])presets.push({favorites,dark:isDark,customIDs:['owned-one','owned-two'],actions:[mode(value),...Array(9).fill(draw)]});
presets.push(
  {favorites:['nord','serika','dracula'],dark:false,customIDs:[],actions:[mode('fav'),draw,fav([]),mode('fav'),...Array(7).fill(draw),mode('off'),draw]},
  {favorites:['nord','serika','dracula'],dark:true,customIDs:[],actions:[mode('fav'),fav(['nord','serika','dracula']),draw,{kind:'rebuild'},draw]},
  {favorites:[],dark:false,customIDs:[],actions:[mode('on'),draw,mode('fav'),...Array(8).fill(draw)]},
  {favorites:[],dark:false,customIDs:[],actions:[mode('dark'),{kind:'silentMode',value:'auto'},draw]},
  {favorites:[],dark:false,customIDs:['serika','nord'],actions:[mode('custom'),...Array(6).fill(draw),{kind:'library',names:[]},draw]},
  {favorites:[],dark:true,customIDs:['owned-one','owned-two'],actions:[mode('custom'),draw,mode('on'),draw]},
  {favorites:[],dark:true,customIDs:[],actions:[mode('on'),draw,draw,fav(['serika']),{kind:'silentMode',value:'fav'},draw]},
  {favorites:[],dark:true,customIDs:[],actions:[mode('custom'),draw,mode('auto'),draw,{kind:'system'},...Array(7).fill(draw)]},
  {favorites:[],dark:false,customIDs:[],actions:[mode('on'),draw,{kind:'clear'},{kind:'clear'},draw]},
  {favorites:[],dark:false,customIDs:['owned-one','owned-two'],actions:[mode('custom'),draw,{kind:'clear'},draw]},
  {favorites:['serika','nord'],dark:true,customIDs:[],actions:[mode('fav'),draw,fav([]),{kind:'clear'},mode('off'),draw]}
);
const fixtures=[];
for(const preset of presets) {
  Config.randomTheme='off';Config.favThemes=preset.favorites.slice();Config.customTheme=true;
  customIDs=preset.customIDs.slice();dark=preset.dark;calls=0;requests=[];applied=[];notices=[];
  vm.runInContext('themesList=[];randomThemeIndex=0;randomTheme=null;',context);
  const frames=[];
  for(const action of preset.actions) {
    requests=[];applied=[];notices=[];let fault=null;
    try {
      switch(action.kind) {
      case 'mode':Config.randomTheme=action.value;await context.changeThemeList();break;
      case 'silentMode':Config.randomTheme=action.value;break;
      case 'favorites':Config.favThemes=action.names.slice();break;
      case 'library':customIDs=action.names.slice();break;
      case 'system':dark=!dark;break;
      case 'rebuild':await context.changeThemeList();break;
      case 'draw':await vm.runInContext('randomizeTheme()',context,{timeout:100});break;
      case 'clear':await context.clearRandom();break;
      default:throw new Error(action.kind);
      }
    } catch(error) {fault=error.code==='ERR_SCRIPT_EXECUTION_TIMEOUT'?'nonterminating':error.name;}
    const state=vm.runInContext('({candidates:[...themesList],cursor:randomThemeIndex,active:randomTheme,alias:themesList===Config.favThemes})',context);
    frames.push({...state,favorites:Config.favThemes.slice(),randomCalls:calls,fault,
      draw:applied.at(-1)??null,requests:structuredClone(requests),notices:structuredClone(notices)});
    if(fault==='nonterminating')break;
  }
  fixtures.push({...preset,frames});
}
verify();console.log(JSON.stringify({entries:entries.map(({name,dark})=>({name,dark})),samples,fixtures}));
