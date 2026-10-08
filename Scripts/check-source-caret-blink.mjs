// QA only: real pinned Caret class/focus/RAF + complete input and blink wrappers.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), option = process.argv[3];
assert.ok(process.argv[2] && (!option || ['--emit-fixtures','--serve-css'].includes(option)));
const pin='91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const source=file=>fs.readFileSync(path.join(root,'frontend/src',file),'utf8');
const transform=text=>stripTypeScriptTypes(text.replace(/^import [\s\S]*?;\n/gm,'').replace(/^export /gm,''),{mode:'transform'});
function complete(text,name) {
  const start=text.search(new RegExp(`(?:export )?function ${name}(?=[(<])`)), end=text.indexOf('\n}',start);
  assert.ok(start>=0 && end>start); return transform(text.slice(start,end+2));
}
const animations=source('styles/animations.scss'), caretCSS=source('styles/caret.scss');
function keyframes(name) {
  const start=animations.indexOf('@keyframes '+name+' {'), end=animations.indexOf('\n}',start);
  assert.ok(start>=0 && end>start); return animations.slice(start,end+2);
}
const keyframeCSS=['caretFlashSmooth','caretFlashHard'].map(keyframes).join('\n');
const animation=caretCSS.match(/^  animation: ([^;]+);/m)?.[1];
assert.equal(animation,'caretFlashSmooth 1s infinite');
const cssHash=createHash('sha256').update(keyframeCSS+'\n'+animation).digest('hex');
const captured=JSON.parse(fs.readFileSync(new URL('../Compatibility/caret-blink-browser-samples.json',import.meta.url),'utf8'));
assert.equal(captured.referenceCommit,pin);assert.equal(captured.cssHash,cssHash);
assert.equal(captured.timesMilliseconds.length,16);
for(const mode of ['smooth','hard']){
  assert.equal(captured[mode].length,16);
  assert.ok(captured[mode].every(value=>Number.isFinite(value)&&value>=0&&value<=1));
}
const scenarios=[
  [{kind:'focus',value:true},{kind:'flush'},{kind:'mouse'},{kind:'flush'},{kind:'input'},{kind:'flush'}],
  [{kind:'focus',value:true},{kind:'flush'},{kind:'motion',value:'off'},{kind:'input'},{kind:'flush'},
    {kind:'motion',value:'slow'},{kind:'motion',value:'fast'},{kind:'input'}],
  [{kind:'focus',value:true},{kind:'focus',value:false},{kind:'flush'},{kind:'focus',value:false},
    {kind:'focus',value:true},{kind:'flush'},{kind:'input'},{kind:'flush'}],
  [{kind:'stop'},{kind:'start'},{kind:'stop'},{kind:'motion',value:'off'},{kind:'start'},{kind:'stop'}],
];
const fixtures=scenarios.map(actions=>{
  let focused=false, sequence=0, mouse;
  const frames=new Map(), style={animationName:'caretFlashSmooth'}, classes=new Set();
  const element={native:{id:'caret'}, setStyle:value=>Object.assign(style,value),
    addClass:value=>{for(const name of Array.isArray(value)?value:[value])classes.add(name);},
    removeClass:value=>{for(const name of Array.isArray(value)?value:[value])classes.delete(name);}};
  const context=vm.createContext({element,Config:{smoothCaret:'medium',caretStyle:'default',playSoundOnError:'off',keymapMode:'off'},
    qsr:()=>element,qsa:()=>({addClass(){},removeClass(){},setStyle(){}}),getFocus:()=>focused,setFocus:value=>{focused=value;},
    PageTransition:{get:()=>false},document:{addEventListener:(_,callback)=>{mouse=callback;}},
    requestAnimationFrame:callback=>{frames.set(++sequence,callback);return sequence;},cancelAnimationFrame:id=>frames.delete(id),
    SoundController:{playClick(){},playError(){}},Numbers:{roundTo2:value=>value},getLiveCachedAccuracy:()=>100,setCurrentLiveStats(){},
  });
  function run(code){return new vm.Script(code).runInContext(context,{timeout:1000});}
  context.CaretConstructor=run('(()=>{'+transform(source('ts/elements/caret.ts'))+'\nreturn Caret;})()');
  run('const caret = new CaretConstructor(element,"default");');
  for(const name of ['stopAnimation','startAnimation'])run(complete(source('ts/test/caret.ts'),name));
  context.Caret={stopAnimation:context.stopAnimation,startAnimation:context.startAnimation,updatePosition(){}};
  run(transform(source('ts/utils/debounced-animation-frame.ts'))+'\n'+transform(source('ts/test/focus.ts')));
  context.Focus={set:context.set};
  run(complete(source('ts/test/test-ui.ts'),'afterAnyTestInput'));
  const states=actions.map(action=>{
    switch(action.kind){
      case 'focus':context.set(action.value);break;
      case 'flush':{const batch=[...frames.values()];frames.clear();batch.forEach(callback=>callback());break;}
      case 'mouse':mouse({movementX:4,movementY:0});break;
      case 'input':context.afterAnyTestInput('textInput',true);break;
      case 'motion':context.Config.smoothCaret=action.value;run('caret.updateBlinkingAnimation()');break;
      case 'stop':context.stopAnimation();break;
      case 'start':context.startAnimation();break;
    }
    return {focused,blinking:style.animationName!=='none',mode:context.Config.smoothCaret};
  });
  return {actions,states};
});
assert.deepEqual(fixtures[1].states.slice(2,5).map(value=>[value.focused,value.blinking]),[[true,true],[true,false],[true,false]]);
verify();
if(option==='--emit-fixtures')process.stdout.write(JSON.stringify({pin,cssHash,fixtures}));
else if(option==='--serve-css'){
  const html=`<!doctype html><html lang="zh"><meta charset="utf-8"><title>光标透明度 QA</title>
    <style>body{font:16px system-ui;margin:30px}#sample{width:4px;height:32px;background:#485daa;animation:${animation};animation-play-state:paused}pre{white-space:pre-wrap}${keyframeCSS}</style>
    <h1>固定源码光标曲线采样</h1><p>仅 QA；不加载原版图片、字体或网络资源。</p><button id="collect">采样两个完整周期</button><div id="sample"></div><pre id="result">待采样</pre>
    <script>document.querySelector('#collect').onclick=()=>{
      const samples=[],element=document.querySelector('#sample');
      for(const mode of ['smooth','hard']){
        element.style.animationName=mode==='smooth'?'caretFlashSmooth':'caretFlashHard';
        getComputedStyle(element).opacity;
        const animation=element.getAnimations()[0];animation.pause();
        for(const time of [0,100,250,499,500,501,505,509,510,750,999,1000,1250,1505,1750,2000]){
          animation.currentTime=time;samples.push({mode,time,opacity:Number(getComputedStyle(element).opacity)});
        }
      }
      document.querySelector('#result').textContent=JSON.stringify({pin:${JSON.stringify(pin)},cssHash:${JSON.stringify(cssHash)},userAgent:navigator.userAgent,samples},null,2);
    };</script></html>`;
  const server=http.createServer((request,response)=>{
    if(request.method!=='GET'||request.url!=='/'){response.writeHead(404);response.end();return;}
    response.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'"});response.end(html);
  });
  server.listen(0,'127.0.0.1',()=>console.log('CSS_QA_URL=http://127.0.0.1:'+server.address().port+'/'));
}else console.log('Caret blink source passed (4 composed scenarios, 28 states, complete Caret/focus/RAF with real blink/input methods; owned DOM/geometry/sound boundaries, CSS samples separate)');
