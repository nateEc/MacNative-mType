// Read-only QA: run the pinned keydown handler, converter and Shift tracker.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';
const root=path.resolve(process.argv[2]??'');
const mirrored=process.argv[3]==='--mirror';
assert.ok(!process.argv[3]||mirrored);
function verify(){
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const frontend=path.join(root,'frontend/src/ts');
function source(file,from,until){
  const text=fs.readFileSync(path.join(frontend,file),'utf8'),start=from?text.indexOf(from):0,end=until?text.indexOf(until,start):text.length;
  assert.ok(start>=0&&end>start);
  return stripTypeScriptTypes(text.slice(start,end).replace(/^export /gm,''),{mode:'transform'});
}
let flags={},layout,correct;
const Config={oppositeShiftMode:'off',keymapLayout:'overrideSync'};
const context=vm.createContext({Config,getModifierState:()=>flags,setCorrectShiftUsed:value=>{correct=value;},
  __nonReactive:{getKeymapLayout:()=>Promise.resolve(layout)},showErrorNotification:()=>assert.fail('Unexpected missing layout')});
vm.runInContext(source('constants/keys.ts'),context);
vm.runInContext(source('utils/key-converter.ts','export function layoutKeyToKeycode('),context);
vm.runInContext('globalThis.KeyConverter={layoutKeyToKeycode,keycodeToKeyboardSide};',context);
vm.runInContext(source('test/shift-tracker.ts','export function isUsingOppositeShift('),context);
vm.runInContext('globalThis.ShiftTracker={isUsingOppositeShift};',context);
vm.runInContext(source('input/handlers/keydown.ts','export async function handleOppositeShift(','async function handleFunboxes('),context);
const fixtures=[];
for(const mode of ['off','on','keymap'])for(const guide of ['overrideSync','qwerty','dvorak','colemak','azerty'])
  for(const [code,macCode] of [['KeyP',35],['KeyA',0],['KeyY',16],['KeyB',11],['Space',49]])
    for(const key of ['P','p','E','e','Y','B','^','🦄','SS','ab','é','e\u0301'])for(const [left,right] of [[false,false],[true,false],[false,true],[true,true]]){
      Config.oppositeShiftMode=mode;Config.keymapLayout=guide;flags={leftShift:left,rightShift:right};correct=undefined;
      layout=guide==='overrideSync'?undefined:JSON.parse(fs.readFileSync(path.join(root,'frontend/static/layouts',guide+'.json'),'utf8'));
      if(mirrored&&layout)layout=context.mirrorLayoutKeys(layout);
      await context.handleOppositeShift({key,code});
      assert.equal(typeof correct,'boolean');fixtures.push({mode,guide,macCode,key,left,right,correct});
    }
verify();console.log(JSON.stringify({fixtures}));
