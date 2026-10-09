// QA only: complete pinned scrollTape/getNlCharWidth and locked real Anime.js.
// Owned pre-request boxes distinguish word removal from structural row removal.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const [argument,option]=process.argv.slice(2);
assert.ok(argument&&(!option||option==='--emit-fixtures'));
const root=path.resolve(argument),pin='91bd24bb8513785c7364cbea29296ff7adafac41';
function verify(){
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const archive=process.env.TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE;
assert.ok(archive,'Requires locked Anime.js 4.2.2');
const integrity='sha512-'+createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
assert.equal(integrity,'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
assert.ok(fs.readFileSync(path.join(root,'pnpm-lock.yaml'),'utf8').includes(integrity));
const bundle=execFileSync('tar',['-xOf',archive,'package/dist/bundles/anime.esm.js'],{encoding:'utf8',maxBuffer:2**21});
const ui=fs.readFileSync(path.join(root,'frontend/src/ts/test/test-ui.ts'),'utf8');
const begin=ui.indexOf('function getNlCharWidth('),end=ui.indexOf('\nfunction removeTestElements(',begin);
assert.ok(begin>=0&&end>begin);
const source=stripTypeScriptTypes(ui.slice(begin,end).replace(/^export /gm,''),{mode:'transform'});
const scenarios=[
  [{width:36},{width:48},{width:60,newline:12},{width:24},{width:36,newline:12},{width:48}],
  [{width:48,newline:12},{width:36},{width:24,newline:12},{width:48,newline:12},{width:36},{width:48,newline:12}],
  [{width:48,newline:12},{width:48,newline:0},{width:24,newline:12},{width:48,newline:12},{width:36},{width:48,newline:12}],
];
const fixtures=[];
for(const [scenario,descriptors] of scenarios.entries())for(const rtl of [false,true])for(const smooth of [false,true])
for(const overflow of [[0],[1],[0,2],[0,1],[1,5]])for(const viewportWidth of [40,400]){
  let clock=10000,frameID=0;
  class ControlledDate extends Date{static now(){return clock;}}
  const context=vm.createContext({Date:ControlledDate,performance:{now:()=>clock-10000},
    requestAnimationFrame:()=>++frameID,cancelAnimationFrame(){},
    setImmediate(){throw new Error('Unexpected automatic animation loop');},clearImmediate(){}});
  const anime=new vm.SourceTextModule(bundle,{context});
  await anime.link(id=>{throw new Error('Unexpected bundle import '+id);});await anime.evaluate();
  anime.namespace.engine.useDefaultMainLoop=false;anime.namespace.engine.fps=1000;anime.namespace.engine.defaults.frameRate=1000;
  const children=[],words=[],fillers=[],animations=[],removed=[],corrections=[],requests=[];
  function element(kind,index){
    const native={kind,index,marginLeft:0,isConnected:true};
    Object.defineProperty(native,'style',{get:()=>({marginLeft:native.marginLeft+'px'})});
    return {native,kind,index,hasClass:name=>name===kind,
      getStyle:()=>({marginLeft:native.marginLeft+'px'}),
      setStyle:values=>{for(const[key,value]of Object.entries(values))native[key]=parseFloat(value);},
      animate:options=>{const a=anime.namespace.animate(native,options);animations.push(a);return a;},
      getOffsetWidth:()=>0,qs:()=>null,
      remove(){assert.ok(native.isConnected);native.isConnected=false;removed.push({kind,index});}};
  }
  for(const [index,descriptor] of descriptors.entries()){
    const word=element('word',index);word.getOffsetWidth=()=>descriptor.width;word.getOuterWidth=()=>descriptor.width+12;
    word.getOffsetLeft=()=>overflow.includes(index)?rtl?viewportWidth+1:-descriptor.width-1:0;
    word.qsa=()=>[];word.qs=selector=>{
      assert.equal(selector,'letter.nlChar');if(descriptor.newline===undefined)return null;
      const marker=element('marker',index);marker.getOffsetWidth=()=>12;
      marker.hasClass=name=>name==='incorrect'&&descriptor.newline===0;return marker;
    };
    words.push(word);children.push(word);
    if(descriptor.newline!==undefined){
      const filler=element('afterNewline',index);fillers.push(filler);
      children.push(element('beforeNewline',index),element('newline',index),filler);
    }
  }
  const connected=()=>children.filter(c=>c.native.isConnected),wordsEl=element('words',-1);
  wordsEl.getOffsetWidth=()=>viewportWidth;wordsEl.getChildren=connected;
  wordsEl.qsa=()=>fillers.filter(f=>f.native.isConnected);
  Object.assign(context,{Config:{tapeMode:'word',tapeMargin:25,smoothLineScroll:smooth},wordsEl,
    wordsWrapperEl:{getOffsetWidth:()=>viewportWidth},getActiveWordElement:()=>words[4],getCurrentInput:()=>'',
    getActivePage:()=>'test',getResultVisible:()=>false,centeringActiveLine:Promise.resolve(),
    isDirectionReversed:()=>false,isLanguageRightToLeft:()=>rtl,
    window:{getComputedStyle:native=>({marginRight:native.kind==='word'?'12':'0',marginLeft:'0'})},
    Caret:{caret:{handleTapeScroll(){},handleTapeWordsRemoved(){}}},
    PaceCaret:{caret:{handleTapeScroll:o=>requests.push(o.newValue),handleTapeWordsRemoved:w=>corrections.push(w)}}});
  vm.runInContext(source,context);
  const passes=[];
  for(let pass=0;pass<2;pass++){
    // A second real invocation observes the changed structural topology, not
    // an idealized filtered word array. It may expose a leading filler.
    removed.length=0;corrections.length=0;
    await context.scrollTape();
    const samples=[],snapshot=()=>Object.fromEntries(fillers.filter(f=>f.native.isConnected).map(f=>[f.index,f.native.marginLeft]));
    samples.push({milliseconds:0,indents:snapshot()});
    const start=clock;
    for(let ms=1;ms<=150;ms++){
      clock=start+ms;anime.namespace.engine.update();
      if([31,62,113,150].includes(ms))samples.push({milliseconds:ms,indents:snapshot()});
    }
    passes.push({removed:[...removed],corrections:[...corrections],target:requests.at(-1),
      nodes:connected().map(c=>({kind:c.kind,index:c.index})),samples});
  }
  assert.ok(passes.every(p=>p.removed.every(n=>n.kind==='word'||n.kind==='afterNewline')));
  assert.equal(connected().filter(c=>c.kind==='newline').length,descriptors.filter(d=>d.newline!==undefined).length,
    'Horizontal word removal must not collapse structural rows');
  fixtures.push({scenario,rtl,smooth,overflow,viewportWidth,active:4,
    words:descriptors.map((d,index)=>({index,width:d.width,gap:12,newlineWidth:d.newline??null})),passes});
  for(const animation of animations)animation.cancel();
}
verify();assert.equal(fixtures.length,120);
assert.ok(fixtures.some(f=>f.passes.some(p=>p.removed.some(n=>n.kind==='word'&&n.index>f.active))),
  'Future-word cases must actually reach and remove a lookahead word');
if(option)process.stdout.write(JSON.stringify({pin,fixtures}));
else console.log('Tape newline overflow source passed: 120 complete two-request scrollTape sequences, real locked Anime.js, LTR/RTL, smooth/immediate, word-only/non-prefix/future removal, persistent structural rows, changed marker adjacency, leading filler cleanup and cap; owned pre-request boxes, not browser/native full queue parity');
