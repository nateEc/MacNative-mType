// QA only: complete pinned scrollTape/getNlCharWidth, real locked Anime.js.
// Owned multiline boxes/clock, deliberately no word overflow; not browser CSS.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const [argument, option] = process.argv.slice(2);
assert.ok(argument && (!option || option === '--emit-fixtures'));
const root=path.resolve(argument), pin='91bd24bb8513785c7364cbea29296ff7adafac41';
function verify(){
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const archive=process.env.TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE;
assert.ok(archive,'Requires the locked Anime.js archive');
const integrity='sha512-'+createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
assert.equal(integrity,'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
assert.ok(fs.readFileSync(path.join(root,'pnpm-lock.yaml'),'utf8').includes(integrity));
const bundle=execFileSync('tar',['-xOf',archive,'package/dist/bundles/anime.esm.js'],{encoding:'utf8',maxBuffer:2**21});
const ui=fs.readFileSync(path.join(root,'frontend/src/ts/test/test-ui.ts'),'utf8');
const start=ui.indexOf('function getNlCharWidth('), end=ui.indexOf('\nfunction removeTestElements(',start);
assert.ok(start>=0&&end>start);
const code=stripTypeScriptTypes(ui.slice(start,end).replace(/^export /gm,''),{mode:'transform'});
const scenarios=[
  [{width:36},{width:48,newline:12},{width:60},{width:24,newline:12},{width:36,newline:12},{width:48}],
  [{width:12,newline:12},{width:12,newline:12},{width:36,newline:12},{width:24}],
  [{width:36,newline:0},{width:60,newline:12},{width:36,newline:0},{width:48}],
  [{width:1301,newline:12},{width:36,newline:12},{width:24,newline:12},{width:48}],
  [{width:48,newline:12},{width:1190,newline:12},{width:24,newline:12},{width:48}],
];
const fixtures=[];
for(const [scenario,descriptors] of scenarios.entries())for(const rtl of [false,true])for(const smooth of [false,true])
for(const active of [0,1,descriptors.length-1]){
  let clock=10000, nextFrame=0;
  class ControlledDate extends Date{static now(){return clock;}}
  const context=vm.createContext({Date:ControlledDate,performance:{now:()=>clock-10000},
    requestAnimationFrame:()=>++nextFrame,cancelAnimationFrame(){},
    setImmediate(){throw new Error('Unexpected default main loop');},clearImmediate(){}});
  const anime=new vm.SourceTextModule(bundle,{context});
  await anime.link(id=>{throw new Error('Unexpected bundle import '+id);});await anime.evaluate();
  anime.namespace.engine.useDefaultMainLoop=false;anime.namespace.engine.fps=1000;
  anime.namespace.engine.defaults.frameRate=1000;
  const animations=[], children=[], after=[], words=[];
  function element(kind,width=0){
    const native={marginLeft:0,kind};
    Object.defineProperty(native,'style',{get:()=>({marginLeft:native.marginLeft+'px'})});
    return {native,kind,hasClass:name=>name===kind,
      getStyle:()=>({marginLeft:native.marginLeft+'px'}),
      setStyle:values=>{for(const [key,value] of Object.entries(values))native[key]=parseFloat(value);},
      animate:options=>{const animation=anime.namespace.animate(native,options);animations.push(animation);return animation;},
      getOffsetWidth:()=>width,getOffsetLeft:()=>0,
      remove(){throw new Error('This probe deliberately excludes overflow retirement');}};
  }
  descriptors.forEach((descriptor,index)=>{
    const word=element('word',descriptor.width);word.index=index;
    word.getOuterWidth=()=>descriptor.width+12;
    word.qsa=()=>[];
    word.qs=selector=>{
      assert.equal(selector,'letter.nlChar');
      if(descriptor.newline===undefined)return null;
      const nl=element('nlChar',12);
      nl.hasClass=name=>name==='incorrect'&&descriptor.newline===0;
      return nl;
    };
    words.push(word);children.push(word);
    if(descriptor.newline!==undefined){
      const filler=element('afterNewline');filler.afterWord=index;
      after.push(filler);children.push(element('beforeNewline'),element('newline'),filler);
    }
  });
  const wordsEl=element('words',400);wordsEl.getChildren=()=>children;
  wordsEl.qsa=()=>after;
  let target, removed=0;
  Object.assign(context,{Config:{tapeMode:'word',tapeMargin:25,smoothLineScroll:smooth},wordsEl,
    wordsWrapperEl:{getOffsetWidth:()=>400},getActiveWordElement:()=>words[active],getCurrentInput:()=>'',
    getActivePage:()=>'test',getResultVisible:()=>false,centeringActiveLine:Promise.resolve(),
    isDirectionReversed:()=>false,isLanguageRightToLeft:()=>rtl,
    window:{getComputedStyle:native=>({marginRight:native.kind==='word'?'12':'0',marginLeft:'0'})},
    Caret:{caret:{handleTapeScroll(){},handleTapeWordsRemoved(){removed++;}}},
    PaceCaret:{caret:{handleTapeScroll:options=>{target=options.newValue;},handleTapeWordsRemoved(){removed++;}}},
  });
  vm.runInContext(code,context);await context.scrollTape();
  const initial=after.map(filler=>filler.native.marginLeft);
  const snapshot=()=>Object.fromEntries(after.map(filler=>[filler.afterWord,filler.native.marginLeft]));
  const samples=[{milliseconds:0,indents:snapshot()}];
  for(let ms=1;ms<=150;ms++){
    clock=10000+ms;anime.namespace.engine.update();
    if([31,62,113,150].includes(ms))samples.push({milliseconds:ms,indents:snapshot()});
  }
  const indents=snapshot();
  assert.equal(removed,0);
  if(smooth)assert.ok(initial.every(value=>value===0),'Requests do not present new filler margins between frames');
  assert.ok(Object.values(indents).every(value=>value<=1200));
  fixtures.push({scenario,rtl,smooth,active,viewportWidth:400,
    words:descriptors.map((word,index)=>({index,width:word.width,gap:12,newlineWidth:word.newline??null})),
    beforeActive:rtl?target:-target,indents,samples});
  for(const animation of animations)animation.cancel();
}
verify();assert.equal(fixtures.length,60);
if(option)process.stdout.write(JSON.stringify({pin,fixtures}));
else console.log('Tape newline source passed: 60 complete scrollTape/getNlCharWidth sequences with real locked Anime.js, LTR/RTL, immediate/smooth, continuous blank lines, incorrect Return, lookahead and 3x-width cap; owned boxes/clock, no overflow/vertical/browser proof');
