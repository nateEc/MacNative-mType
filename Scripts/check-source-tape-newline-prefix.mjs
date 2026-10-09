// QA only: complete pinned scrollTape/getNlCharWidth and real locked Anime.js.
// Shared native metrics may arrive on stdin; owned boxes, not browser CSS.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const [argument, option] = process.argv.slice(2);
assert.ok(argument && (!option || option === '--emit-fixtures'));
const root = path.resolve(argument), pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git', ['-C',root,'rev-parse','HEAD'], {encoding:'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C',root,'status','--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
const archive = process.env.TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE;
assert.ok(archive, 'Requires locked Anime.js 4.2.2');
const integrity = 'sha512-' + createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
assert.equal(integrity, 'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
assert.ok(fs.readFileSync(path.join(root,'pnpm-lock.yaml'),'utf8').includes(integrity));
const bundle = execFileSync('tar', ['-xOf',archive,'package/dist/bundles/anime.esm.js'], {encoding:'utf8',maxBuffer:2**21});
const ui = fs.readFileSync(path.join(root,'frontend/src/ts/test/test-ui.ts'),'utf8');
const begin=ui.indexOf('function getNlCharWidth('), end=ui.indexOf('\nfunction removeTestElements(',begin);
assert.ok(begin>=0&&end>begin);
const source=stripTypeScriptTypes(ui.slice(begin,end).replace(/^export /gm,''), {mode:'transform'});
const defaults=Array.from({length:6},(_,index)=>({index,width:48,gap:12,newlineWidth:index<5?12:null}));
const metrics=option?JSON.parse(fs.readFileSync(0,'utf8')):{before:defaults,changed:defaults.map((w,i)=>({...w,width:w.width+(i===0?24:0)}))};
assert.equal(metrics.before.length,6);assert.equal(metrics.changed.length,6);
for(const set of [metrics.before,metrics.changed])for(const [i,w] of set.entries()) {
  assert.equal(w.index,i);assert.ok(Number.isFinite(w.width)&&w.width>0&&Number.isFinite(w.gap)&&w.gap>=0);
  assert.ok(w.newlineWidth===null||Number.isFinite(w.newlineWidth)&&w.newlineWidth>=0);
}
assert.ok(metrics.before.every(w=>w.gap===metrics.before[0].gap));
assert.ok(metrics.changed.every((w,i)=>w.gap===metrics.before[i].gap&&w.newlineWidth===metrics.before[i].newlineWidth));
const fixtures=[];
for(const retained of [1,2])for(const rtl of [false,true])for(const smooth of [false,true])
for(const running of [false,true])for(const viewportWidth of [20,400])for(const multipleLeading of [false,true]) {
  let clock=10000, nextFrame=0, active=retained, currentMetrics=metrics.before;
  class ControlledDate extends Date {static now(){return clock;}}
  const context=vm.createContext({Date:ControlledDate,performance:{now:()=>clock-10000},
    requestAnimationFrame:()=>++nextFrame,cancelAnimationFrame(){},
    setImmediate(){throw new Error('Unexpected automatic animation loop');},clearImmediate(){}});
  const anime=new vm.SourceTextModule(bundle,{context});
  await anime.link(id=>{throw new Error('Unexpected bundle import '+id);});await anime.evaluate();
  anime.namespace.engine.useDefaultMainLoop=false;anime.namespace.engine.fps=1000;anime.namespace.engine.defaults.frameRate=1000;
  const animations=[],children=[],fillers=[],words=[],removed=[],corrections=[];
  function element(kind,index=-1) {
    const native={kind,marginLeft:0,isConnected:true};
    Object.defineProperty(native,'style',{get:()=>({marginLeft:native.marginLeft+'px'})});
    return {native,kind,index,hasClass:name=>name===kind,
      getStyle:()=>({marginLeft:native.marginLeft+'px'}),
      setStyle:values=>{for(const [key,value]of Object.entries(values))native[key]=parseFloat(value);},
      animate:options=>{const a=anime.namespace.animate(native,options);animations.push(a);return a;},
      getOffsetWidth:()=>0,getOffsetLeft:()=>0,
      remove(){assert.ok(native.isConnected);native.isConnected=false;removed.push({kind,index});}};
  }
  for(const w of metrics.before) {
    const word=element('word',w.index);
    word.getOuterWidth=()=>currentMetrics[w.index].width+w.gap;
    word.getOffsetWidth=()=>Math.round(currentMetrics[w.index].width);
    word.qsa=()=>[];
    word.qs=selector=>{
      assert.equal(selector,'letter.nlChar');if(w.newlineWidth===null)return null;
      const marker=element('nlChar',w.index);marker.getOffsetWidth=()=>Math.round(w.newlineWidth);
      marker.hasClass=()=>false;return marker;
    };
    words.push(word);children.push(word);
    if(w.newlineWidth!==null) {
      const filler=element('afterNewline',w.index);fillers.push(filler);
      children.push(element('beforeNewline',w.index),element('newline',w.index),filler);
    }
  }
  const wordsEl=element('words');wordsEl.getOffsetWidth=()=>viewportWidth;
  wordsEl.getChildren=()=>children.filter(c=>c.native.isConnected);
  wordsEl.qsa=()=>fillers.filter(f=>f.native.isConnected);
  Object.assign(context,{Config:{tapeMode:'word',tapeMargin:25,smoothLineScroll:smooth},wordsEl,
    wordsWrapperEl:{getOffsetWidth:()=>viewportWidth},getActiveWordElement:()=>words[active],getCurrentInput:()=>'',
    getActivePage:()=>'test',getResultVisible:()=>false,centeringActiveLine:Promise.resolve(),
    isDirectionReversed:()=>false,isLanguageRightToLeft:()=>rtl,
    window:{getComputedStyle:native=>({marginRight:native.kind==='word'?String(metrics.before[0].gap):'0',marginLeft:'0'})},
    Caret:{caret:{handleTapeScroll(){},handleTapeWordsRemoved:width=>corrections.push(width)}},
    PaceCaret:{caret:{handleTapeScroll(){},handleTapeWordsRemoved(){}}}});
  // Preserve shared fractional native marker width through integer offsetWidth
  // plus an owned inline margin. This is not a browser font measurement.
  const oldStyle=context.window.getComputedStyle;
  context.window.getComputedStyle=native=>native.kind==='nlChar'
    ? {marginRight:'0',marginLeft:String(native.metricWidth-Math.round(native.metricWidth))}:oldStyle(native);
  for(const word of words) {
    const original=word.qs;word.qs=selector=>{const marker=original(selector);if(marker)marker.native.metricWidth=metrics.before[word.index].newlineWidth;return marker;};
  }
  vm.runInContext(source,context);await context.scrollTape(true);
  if(running) {
    currentMetrics=metrics.changed;clock=11000;await context.scrollTape();
    for(let ms=1;ms<=40;ms++){clock=11000+ms;anime.namespace.engine.update();}
  }
  clock=11050;
  const width=fillers[retained-1].native.marginLeft;
  const before=wordsEl.native.marginLeft;
  const oldIndents=Object.fromEntries(fillers.map(f=>[f.index,f.native.marginLeft]));
  for(const child of children)if(child.index<retained&&!(child.kind==='afterNewline'&&(multipleLeading||child.index===retained-1)))child.remove();
  removed.length=0;
  await context.scrollTape();
  assert.equal(corrections.length,1);assert.equal(corrections[0],(rtl?-1:1)*width);
  if(smooth)assert.equal(wordsEl.native.marginLeft,before+(rtl?-1:1)*width);
  assert.equal(removed.length,multipleLeading?retained:1);assert.ok(removed.every(c=>c.kind==='afterNewline'));
  const snapshot=milliseconds=>({milliseconds,indents:Object.fromEntries(fillers.filter(f=>f.native.isConnected).map(f=>[f.index,f.native.marginLeft]))});
  const samples=[snapshot(0)];
  for(let ms=1;ms<=150;ms++){clock=11050+ms;anime.namespace.engine.update();if([31,62,113,150].includes(ms))samples.push(snapshot(ms));}
  fixtures.push({retained,rtl,smooth,running,viewportWidth,multipleLeading,width,oldIndents,samples});
  for(const animation of animations)animation.cancel();
}
verify();assert.equal(fixtures.length,64);
if(option)process.stdout.write(JSON.stringify({pin,fixtures}));
else console.log('Tape newline prefix source passed: 64 complete cleanup sequences, real locked Anime.js, last leading filler only, LTR/RTL, immediate/smooth, running/capped fillers, one/two retired rows and multiple leading fillers; shared owned metrics, no browser/vertical/queue proof');
