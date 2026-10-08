// QA only. Execute complete pinned focus + RAF modules against owned boundaries.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
function completeModule(file) {
  const text = fs.readFileSync(path.join(root,file),'utf8');
  return stripTypeScriptTypes(text.replace(/^import .*;\n/gm,'').replace(/^export /gm,''),{mode:'transform'});
}
const raf = completeModule('frontend/src/ts/utils/debounced-animation-frame.ts');
const focus = completeModule('frontend/src/ts/test/focus.ts');
const set = (value,withCursor=false) => ({kind:'set',value,withCursor});
const flush = {kind:'flush'};
const move = (x,y,transitioning=false) => ({kind:'move',x,y,transitioning});
const scenarios = [
  ['initial', [set(true,true),flush]],
  ['input', [set(true),flush]],
  ['repeated input', [set(true,true),flush,set(true),flush]],
  ['threshold', [set(true),flush,move(3,3),flush,move(3.001,0),flush]],
  ['vertical', [set(true),flush,move(0,4),flush]],
  ['negative', [set(true),flush,move(-100,-100),flush]],
  ['transition', [set(true),flush,move(10,10,true),flush,move(10,0),flush]],
  ['unfocused mouse', [move(100,100),flush]],
  ['same current false leaves pending true', [set(true),set(false),flush]],
  ['same current true leaves pending false', [set(true),flush,set(false),set(true),flush]],
  ['debounced initial cursor', [set(true),set(true,true),flush]],
  ['reentry', [set(true),flush,set(false),flush,set(true),flush]],
];
const fixtures = scenarios.map(([name,actions]) => {
  let focused=false, transitioning=false, sequence=0, listener;
  const frames=new Map(), effects=[];
  const context=vm.createContext({
    getFocus:()=>focused, setFocus:value=>{ focused=value; effects.push(['focus',value]); },
    Caret:{stopAnimation:()=>effects.push(['caret','stop']),startAnimation:()=>effects.push(['caret','start'])},
    PageTransition:{get:()=>transitioning},
    document:{addEventListener:(type,callback)=>{ assert.equal(type,'mousemove'); assert.equal(listener,undefined); listener=callback; }},
    requestAnimationFrame:callback=>{ const id=++sequence; frames.set(id,callback); return id; },
    cancelAnimationFrame:id=>frames.delete(id),
    qsa:selector=>({addClass:value=>effects.push(['add',selector,value]),removeClass:value=>effects.push(['remove',selector,value]),
      setStyle:value=>effects.push(['style',selector,JSON.parse(JSON.stringify(value))])}),
  });
  new vm.Script(raf+'\n'+focus).runInContext(context,{timeout:1000});
  const states=actions.map(action=>{
    if (action.kind==='set') context.set(action.value,action.withCursor);
    if (action.kind==='move') { transitioning=action.transitioning; listener({movementX:action.x,movementY:action.y}); }
    if (action.kind==='flush') { const batch=[...frames.values()]; frames.clear(); for(const callback of batch) callback(); }
    return focused;
  });
  assert.ok(frames.size<=1);
  return {name,actions,states,effects};
});
const fixture=name=>fixtures.find(value=>value.name===name);
assert.deepEqual(fixture('threshold').states,[false,true,true,true,true,false]);
assert.equal(fixture('negative').states.at(-1),true);
assert.deepEqual(fixture('same current false leaves pending true').states,[false,false,true]);
assert.deepEqual(fixture('same current true leaves pending false').states,[false,true,true,true,false]);
assert.equal(fixture('initial').effects.some(value=>value[0]==='style'),false);
assert.equal(fixture('repeated input').effects.some(value=>value[0]==='style'),false);
assert.equal(fixture('debounced initial cursor').effects.some(value=>value[0]==='style'),false);
assert.deepEqual(fixture('reentry').effects.filter(value=>value[0]==='caret').map(value=>value[1]),['stop','start','stop']);
assert.deepEqual(fixture('reentry').effects.filter(value=>value[0]==='style').map(value=>value[2].cursor),['none','','none']);
verify();
if(emit) process.stdout.write(JSON.stringify(fixtures));
else console.log('Visual focus source passed (12 scenarios, complete focus and debounced RAF modules; owned signal/DOM/caret/frame boundaries, not browser/device/Solid rendering)');
