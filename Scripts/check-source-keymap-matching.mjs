// QA only: read and execute the pinned event mapping and key predicates.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';
const root=path.resolve(process.argv[2]??''),repo=path.resolve(import.meta.dirname,'..');
const mapping=JSON.parse(fs.readFileSync(path.join(repo,'Compatibility/official-layouts.json'),'utf8'));
function verify(){assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),mapping.referenceCommit);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');}
verify();
const read=file=>fs.readFileSync(path.join(root,'frontend/src/ts',file),'utf8');
const ts=text=>stripTypeScriptTypes(text.replace(/^export /gm,''),{mode:'transform'});
function part(text,start,end){const a=text.indexOf(start);assert.ok(a>=0,start);const b=end?text.indexOf(end,a):text.length;assert.ok(b>a,end);return text.slice(a,b);}
let listener;
const config={keymapMode:'next',keymapStyle:'staggered'};
const context=vm.createContext({getConfig:config,keymapEvent:{useListener:callback=>{listener=callback;}},
  createSignal:initial=>{let value=initial;return [()=>value,next=>{value=next;}];},
  createStore:initial=>[initial,(key,value)=>{initial[key]=value;} ]});
vm.runInContext(ts(part(read('states/test.ts'),'const [getKeymapHighlightKey,','const getInputLayout =')),context);
assert.equal(typeof listener,'function');
const display=read('components/pages/test/Keymap.tsx');
vm.runInContext(part(display,'const isSteno = () =>','\n\n  // Steno'),context);
vm.runInContext(ts('function sourceIsNext(props){return '+part(display,'getConfig.keymapMode === "next" &&','\n  );').trim().replace(/,$/,'')+';}'),context);
vm.runInContext(ts(part(read('components/pages/test/keymapConverter.ts'),'const emptyLegends =')),context);
vm.runInContext(ts(part(read('utils/key-converter.ts'),'export function mirrorLayoutKeys(')),context);
if(process.argv[3]==='--flash-state'){
  vm.runInContext(ts('function sourceComplete(props){'+part(display,'props.legends.forEach((l) => setKeymapFlashState(l, undefined));','\n')+'}'),context);
  vm.runInContext(ts('function sourceFlashEntry(key,props){return '+part(display,'key.legends\n                      .map',';')+';}'),context);
  const actions=[
    {kind:'flash',mode:'react',units:[97],isCorrect:false},
    {kind:'flash',mode:'react',units:[98],isCorrect:true},
    {kind:'flash',mode:'react',units:[97],isCorrect:true},
    {kind:'flash',mode:'react',units:[],isCorrect:false},
    {kind:'flash',mode:'react',units:[233],isCorrect:false},
    {kind:'flash',mode:'react',units:[101,769],isCorrect:true},
    {kind:'flash',mode:'react',units:[55357],isCorrect:false},
    {kind:'flash',mode:'next',units:[122],isCorrect:true},
    {kind:'flash',mode:'react',units:[97],isCorrect:false},
    {kind:'complete',legends:[[97],[98],[]]},
    {kind:'complete',legends:[[32],[233],[101,769]]},
    {kind:'complete',legends:[[55357]]},
  ];
  const fixtures=[];
  for(const action of actions){
    if(action.kind==='flash'){
      config.keymapMode=action.mode;listener({mode:'flash',key:String.fromCharCode(...action.units),correct:action.isCorrect});
    }else context.sourceComplete({legends:action.legends.map(units=>String.fromCharCode(...units))});
    const store=vm.runInContext('getKeymapFlashState',context);
    const expected=Object.entries(store).filter(([,value])=>value!==undefined).map(([key,value])=>({
      units:Array.from({length:key.length},(_,i)=>key.charCodeAt(i)),tick:value.tick,isCorrect:value.correct}));
    const first=context.sourceFlashEntry({legends:['b','a']},{flashState:store});
    fixtures.push({...action,expected,selected:first?{tick:first.tick,isCorrect:first.correct}:null});
  }
  verify();console.log(JSON.stringify({fixtures}));process.exit(0);
}
const layouts=[];
for(const [id,native] of Object.entries(mapping.nativeExact)){
  const original=JSON.parse(fs.readFileSync(path.join(root,'frontend/static/layouts',id+'.json'),'utf8'));
  for(const mirrored of [false,true]){
    const layout=mirrored?context.mirrorLayoutKeys(original):original;
    const rows=Object.values(layout.keys).map(row=>row.map(raw=>context.buildLegends(raw)));
    const candidates=rows.flat(2),queries=new Set(['',' ','SS','ab','é','e\u0301','🦄','\t','\n']);
    for(const value of candidates)for(const text of [value,value.toLowerCase(),value.toUpperCase(),value.normalize('NFD')])queries.add(text);
    const fixtures=[];
    for(const key of queries){
      listener({mode:'highlight',key});
      const matches=[];
      rows.forEach((row,r)=>row.forEach((legends,c)=>{if(context.sourceIsNext({legends}))matches.push(r*100+c);}));
      fixtures.push({key,matches});
    }
    for(const style of ['steno','steno_matrix']){
      config.keymapStyle=style;listener({mode:'highlight',key:' '});
      assert.equal(context.sourceIsNext({legends:[' ']}),false);
    }
    config.keymapStyle='staggered';
    layouts.push({id,native,mirrored,fixtures});
  }
}
verify();console.log(JSON.stringify({layouts}));
