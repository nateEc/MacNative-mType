// QA only. Complete pinned lineJump/removal functions; owned DOM and animation boundary.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const [argument,option]=process.argv.slice(2);
assert.ok(argument&&(!option||option==='--emit-fixtures'));
const root=path.resolve(argument);
function verify(){
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const archive=process.env.TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE;
assert.ok(archive,'Requires pinned Anime.js 4.2.2 archive');
const integrity='sha512-'+createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
assert.equal(integrity,'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
assert.ok(fs.readFileSync(path.join(root,'pnpm-lock.yaml'),'utf8').includes(integrity));
const bundle=execFileSync('tar',['-xOf',archive,'package/dist/bundles/anime.esm.js'],{encoding:'utf8',maxBuffer:2**21});
const anime=await import('data:text/javascript;base64,'+Buffer.from(bundle).toString('base64'));
assert.equal(anime.engine.defaults.ease,'out(2)');
const curve=[];
const object={position:0};
const animation=anime.animate(object,{position:1,duration:125,autoplay:false,precision:8});
for(const elapsed of [0,0.01,0.03125,0.0625,0.1,0.125]){
  animation.seek(elapsed*1000);
  curve.push({elapsed,progress:object.position});
}
animation.cancel();

const settingsSource=fs.readFileSync(path.join(root,'frontend/src/ts/anim.ts'),'utf8');
const settingsStart=settingsSource.indexOf('export function applyEngineSettings(');
const settingsEnd=settingsSource.indexOf('\nexport function setLowFpsMode(',settingsStart);
assert.ok(settingsStart>=0&&settingsEnd>settingsStart);
const settingsCode=stripTypeScriptTypes(settingsSource.slice(settingsStart,settingsEnd),{mode:'transform'})
  .replace(/^export function /,'function ');
let requestedFrameRate=60;
const settingsContext=vm.createContext({engine:anime.engine,fpsLimit:{get:()=>requestedFrameRate}});
new vm.Script(settingsCode).runInContext(settingsContext,{timeout:1000});
const frameRates=[];
for(const value of [15,30,60,120,1000]){
  requestedFrameRate=value;
  new vm.Script('applyEngineSettings()').runInContext(settingsContext,{timeout:1000});
  assert.equal(anime.engine.pauseOnDocumentHidden,false);
  assert.equal(anime.engine.fps,value);assert.equal(anime.engine.defaults.frameRate,value);
  frameRates.push(value);
}

const source=fs.readFileSync(path.join(root,'frontend/src/ts/test/test-ui.ts'),'utf8');
const start=source.indexOf('function removeTestElements(');
const end=source.indexOf('\nexport function setJoiningClass(',start);
assert.ok(start>=0&&end>start);
const code=stripTypeScriptTypes(source.slice(start,end),{mode:'transform'});
const fixtures=[];
for(const smooth of [false,true])for(const rowHeight of [25,45,59]){
  let activeRow=0,firstRow=0;
  const words=Array.from({length:6},(_,row)=>({
    native:{isConnected:true},hasClass:name=>name==='word',
    getOffsetTop:()=>10+(row-firstRow)*rowHeight,
    getOuterHeight:()=>rowHeight,getOffsetHeight:()=>rowHeight-5,
    remove(){this.native.isConnected=false;firstRow=Math.max(firstRow,row+1);},
  }));
  const caret=[],animations=[];
  const context=vm.createContext({currentTestLine:0,lineTransition:false,activeWordTop:0,activeWordHeight:0,
    Config:{smoothLineScroll:smooth},getActiveWordElement:()=>words[activeRow],
    wordsEl:{getChildren:()=>words.filter(word=>word.native.isConnected),setStyle:()=>{},
      promiseAnimate:options=>{animations.push(options);return Promise.resolve();}},
    Caret:{caret:{handleLineJump:options=>caret.push(options)}},
    PaceCaret:{caret:{handleLineJump:options=>assert.deepEqual(options,caret.at(-1))}},
    updateWordsWrapperHeight:()=>{},
  });
  new vm.Script(code).runInContext(context,{timeout:1000});
  const steps=[];
  for(const next of [1,2,3,4,5]){
    const previousTop=words[activeRow].getOffsetTop();activeRow=next;
    const count=caret.length;
    context.previousTop=previousTop;
    await new vm.Script('lineJump(previousTop)').runInContext(context,{timeout:1000});
    assert.equal(firstRow,Math.max(0,next-1));
    if(next===1)assert.equal(caret.length,0);
    else assert.deepEqual({...caret.at(-1)},{newMarginTop:-rowHeight,duration:smooth?125:0});
    steps.push({activeTop:next*rowHeight,previousWordTop:(next-1)*rowHeight,
      expectedOrigin:firstRow*rowHeight,duration:caret.length===count?0:caret.at(-1).duration/1000});
  }
  assert.equal(animations.length,smooth?4:0);
  assert.equal(context.lineTransition,false);
  fixtures.push({smooth,rowHeight,steps});
}
verify();
if(option)console.log(JSON.stringify({fixtures,curve,frameRates}));
else console.log('Line scroll source passed (6 sequences / 30 forward row transitions, actual removal and 125ms caret/word options; 6 full Anime.js 4.2.2 seek samples; 5 complete engine-settings FPS cases; owned DOM/storage and immediate animation boundary, no browser/GUI/real scheduling/mixed fonts/overlap/low-FPS mode)');
