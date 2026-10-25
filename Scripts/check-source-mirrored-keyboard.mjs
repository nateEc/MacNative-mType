// QA only. Original layout bytes and functions stay in the read-only oracle.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';
const root=path.resolve(process.argv[2]??''),repo=path.resolve(import.meta.dirname,'..');
const caps=process.argv[3]==='--caps-lock';
assert.ok(!process.argv[3]||caps);
const map=JSON.parse(fs.readFileSync(path.join(repo,'Compatibility/official-layouts.json'),'utf8'));
function verify(){assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),map.referenceCommit);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');}
verify();
function source(file,from){const text=fs.readFileSync(path.join(root,'frontend/src/ts',file),'utf8'),start=from?text.indexOf(from):0;
  assert.ok(start>=0);return stripTypeScriptTypes(text.slice(start).replace(/^export /gm,''),{mode:'transform'});}
let current;
const context=vm.createContext({isCapsLockOn:()=>caps,showErrorNotification:()=>assert.fail('Unexpected layout failure'),
  navigator:{userAgent:'Mac'},document:{addEventListener:()=>{}},__nonReactive:{getInputLayout:()=>Promise.resolve(current)}});
vm.runInContext(source('constants/keys.ts'),context);
vm.runInContext(source('utils/key-converter.ts','export function layoutKeyToKeycode('),context);
vm.runInContext(source('test/layout-emulator.ts','let isAltGrPressed'),context);
const macRows=[[50,18,19,20,21,23,22,26,28,25,29,27,24],
  [12,13,14,15,17,16,32,34,31,35,33,30,42],[0,1,2,3,5,4,38,40,37,41,39],[6,7,8,9,11,45,46,43,47,44]];
const domRows=[['Backquote','Digit1','Digit2','Digit3','Digit4','Digit5','Digit6','Digit7','Digit8','Digit9','Digit0','Minus','Equal'],
  ['KeyQ','KeyW','KeyE','KeyR','KeyT','KeyY','KeyU','KeyI','KeyO','KeyP','BracketLeft','BracketRight','Backslash'],
  ['KeyA','KeyS','KeyD','KeyF','KeyG','KeyH','KeyJ','KeyK','KeyL','Semicolon','Quote'],
  ['KeyZ','KeyX','KeyC','KeyV','KeyB','KeyN','KeyM','Comma','Period','Slash']];
const domToMac=Object.fromEntries(domRows.flatMap((row,i)=>row.map((code,j)=>[code,macRows[i][j]])));
domToMac.IntlBackslash=10;domToMac.Space=49;
const layouts=[];
for(const [id,native] of Object.entries(map.nativeExact)){
  const original=JSON.parse(fs.readFileSync(path.join(root,'frontend/static/layouts',id+'.json'),'utf8'));
  for(const mirrored of caps?[false,true]:[true]){
  current=mirrored?context.mirrorLayoutKeys(original):original;
  const iso=original.type==='iso';
  const rows=iso?[domRows[0],domRows[1].slice(0,-1),[...domRows[2],'Backslash'],['IntlBackslash',...domRows[3]]]:domRows;
  const fixtures=[];
  for(const flags of [0,1,2,3])for(const code of [...rows.flat(),'Space']){
    context.updateAltGrState({code:'AltRight',type:flags&2?'keydown':'keyup'});
    const text=await context.getCharFromEvent({code,key:'',shiftKey:!!(flags&1)});
    const reverse=text===null?undefined:context.layoutKeyToKeycode(text,current);
    const row=code==='Space'?4:rows.findIndex(row=>row.includes(code));
    const column=row===4?0:rows[row].indexOf(code);
    fixtures.push({macCode:domToMac[code],row,column,flags,text,reverse:domToMac[reverse]??null});
  }
  layouts.push({id,native,mirrored,fixtures});
  }
}
verify();console.log(JSON.stringify({layouts}));
