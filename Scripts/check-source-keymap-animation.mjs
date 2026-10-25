// Read-only QA: actual Key expressions and the pinned animation engine.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??'');
function verify(){assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');}
verify();
const text=fs.readFileSync(path.join(root,'frontend/src/ts/components/pages/test/Keymap.tsx'),'utf8');
const start=text.indexOf('const isSteno = () =>'),end=text.indexOf('\n  return (\n    <Anime',start);
assert.ok(start>=0&&end>start);
const code=stripTypeScriptTypes(text.slice(start,end),{mode:'transform'});
const fixtures=[];
for(const initial of ['next','react','static'])for(const firstMatch of [false,true])for(const steno of [false,true])
for(const mode of ['off','static','next','react'])for(const matches of [false,true])for(const tick of [0,1,2]){
  const config={keymapMode:initial,keymapStyle:steno?'steno':'staggered'};let match=firstMatch,entry;
  const effects=[];
  const context=vm.createContext({getConfig:config,getKeymapHighlightKey:()=>match?'q':'x',
    props:{legends:['q','Q'],flashEntry:()=>entry},getTheme:()=>({main:'accent',subAlt:'panel',bg:'background',sub:'secondary',error:'error'}),
    createMemo:fn=>()=>fn(),createSignal:value=>[()=>value,next=>{value=next;}],createEffect:fn=>{effects.push(fn);fn();}});
  vm.runInContext(code,context);
  const steps=[{mode:initial,matches:firstMatch,tick:0,correct:true,complete:false},
    {mode,matches,tick,correct:tick!==2,complete:false},
    {mode,matches,tick:tick?tick+1:0,correct:true,complete:false},
    {mode,matches,tick:0,correct:true,complete:true}];
  const output=[];
  for(const step of steps){
    config.keymapMode=step.mode;match=step.matches;entry=step.tick?{tick:step.tick,correct:step.correct}:undefined;
    if(step.complete)vm.runInContext('setIsFading(false)',context);
    effects.forEach(fn=>fn());
    const expected=vm.runInContext('({fading:isFading(),background:animKeyBgColor(),foreground:animKeyColor(),duration:animDuration()})',context);
    output.push({...step,expected});
  }
  fixtures.push({steno,steps:output});
}
const archive=process.env.TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE;assert.ok(archive);
const integrity='sha512-'+createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
assert.equal(integrity,'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
assert.ok(fs.readFileSync(path.join(root,'pnpm-lock.yaml'),'utf8').includes(integrity));
const bundle=execFileSync('tar',['-xOf',archive,'package/dist/bundles/anime.esm.js'],{encoding:'utf8',maxBuffer:2**21});
const anime=await import('data:text/javascript;base64,'+Buffer.from(bundle).toString('base64'));
assert.equal(anime.engine.defaults.ease,'out(2)');
const target={value:0},animation=anime.animate(target,{value:1,duration:250,autoplay:false,precision:8}),curve=[];
for(const elapsed of [0,0.01,0.0625,0.125,0.2,0.25]){animation.seek(elapsed*1000);curve.push({elapsed,progress:target.value});}
animation.cancel();verify();console.log(JSON.stringify({fixtures,curve}));
