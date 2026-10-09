// QA only: complete pinned updateActiveElement/afterTestWordChange/lineJump/
// scrollTape/getNlCharWidth, Caret/main controller/RAF, promiseAnimate and Anime.
// Owned multiline DOM boxes and 1ms clock: not browser CSS or native geometry.
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
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
const archive = process.env.TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE;
assert.ok(archive, 'Requires pinned Anime.js 4.2.2 archive');
const integrity = 'sha512-' + createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
assert.equal(integrity, 'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
assert.ok(fs.readFileSync(path.join(root,'pnpm-lock.yaml'),'utf8').includes(integrity));
const bundle = execFileSync('tar',['-xOf',archive,'package/dist/bundles/anime.esm.js'], {encoding:'utf8',maxBuffer:2**21});
const ui = fs.readFileSync(path.join(root,'frontend/src/ts/test/test-ui.ts'),'utf8');
function plain(source) { return stripTypeScriptTypes(source.replace(/^import [\s\S]*?;\n/gm,'').replace(/^export /gm,''), {mode:'transform'}); }
function section(from, until) {
  const begin=ui.indexOf(from), end=ui.indexOf(until,begin); assert.ok(begin>=0&&end>begin);
  return plain(ui.slice(begin,end));
}
const callbacks = section('export function updateActiveElement(', '\nfunction createHintsHtml(')
  + section('function getNlCharWidth(', '\nexport function setJoiningClass(')
  + section('export async function afterTestWordChange(', '\nexport function onTestStart(');
const caretModule = plain(fs.readFileSync(path.join(root,'frontend/src/ts/elements/caret.ts'),'utf8'));
const mainModule = plain(fs.readFileSync(path.join(root,'frontend/src/ts/test/caret.ts'),'utf8'));
const rafModule = plain(fs.readFileSync(path.join(root,'frontend/src/ts/utils/debounced-animation-frame.ts'),'utf8'));
const strings = fs.readFileSync(path.join(root,'frontend/src/ts/utils/strings.ts'),'utf8');
const directionModule = plain(strings.slice(strings.indexOf('function hasRTLCharacters('), strings.indexOf('\nexport const CHAR_EQUIVALENCE_SETS')));
const dom=fs.readFileSync(path.join(root,'frontend/src/ts/utils/dom.ts'),'utf8');
const promiseBegin=dom.indexOf('  async promiseAnimate('), promiseEnd=dom.indexOf('\n  /**',promiseBegin);
assert.ok(promiseBegin>=0&&promiseEnd>promiseBegin);
const promiseAdapter=plain('class Adapter {\n'+dom.slice(promiseBegin,promiseEnd)+'\n}');
const fixtures=[];
for (const rtl of [false,true]) for (const mode of ['letter','word'])
for (const smooth of [false,true]) for (const style of ['default','block','outline','underline'])
for (const independent of [false,true]) for (const overlap of [false,true]) {
  let clock=10000, frameID=0, active=0, input='', inFrame=false, rendered=false;
  const frames=new Map(), animations=[], trace=[], children=[], removed=[];
  class ControlledDate extends Date { static now(){return clock;} }
  const context=vm.createContext({Date:ControlledDate,performance:{now:()=>clock-10000},
    requestAnimationFrame:callback=>{frames.set(++frameID,callback);return frameID;},cancelAnimationFrame:id=>frames.delete(id),
    setImmediate(){throw new Error('Unexpected automatic animation loop');},clearImmediate(){}});
  const anime=new vm.SourceTextModule(bundle,{context});
  await anime.link(id=>{throw new Error('Unexpected bundle import '+id);});await anime.evaluate();
  anime.namespace.engine.useDefaultMainLoop=false;anime.namespace.engine.fps=1000;anime.namespace.engine.defaults.frameRate=1000;
  const requestTick=anime.namespace.engine.requestTick.bind(anime.namespace.engine);
  anime.namespace.engine.requestTick=time=>{const result=requestTick(time);if(inFrame)rendered=!!result;return result;};
  class Element {
    constructor(id, kind=id){
      this.native={id,kind,left:0,top:0,width:2,marginLeft:0,marginTop:0,isConnected:true};this.classes=new Set([kind]);
      Object.defineProperty(this.native,'style',{get:()=>this.getStyle()});
    }
    addClass(v){for(const c of Array.isArray(v)?v:[v])this.classes.add(c);}
    removeClass(v){for(const c of Array.isArray(v)?v:[v])this.classes.delete(c);}
    hasClass(v){return this.classes.has(v);}
    show(){this.removeClass('hidden');} hide(){this.addClass('hidden');}
    getStyle(){return Object.fromEntries(['left','top','width','marginLeft','marginTop'].map(k=>[k,this.native[k]+'px']));}
    setStyle(values){
      for(const [k,v] of Object.entries(values))this.native[k]=v===''?k==='width'?2:0:parseFloat(v);
      if(this.native.id==='words'&&values.marginTop==='0'){
        trace.push({type:'wordsReset',time:clock-10000});sample('vertical-completion');
      }
    }
    getOffsetWidth(){return this.native.width;} getOffsetHeight(){return this.hasClass('underline')?2:32;}
    // dom.ts reads HTMLElement.offsetTop (CSSOM long), not a floating rect.
    // Match the existing source line-composition adapter's integer boxes.
    getOffsetTop(){return Math.round(rowOf(this)*45+wordsEl.native.marginTop);}
    animate(options){const animation=anime.namespace.animate(this.native,options);animations.push(animation);return animation;}
    remove(){this.native.isConnected=false;removed.push({time:clock-10000,id:this.native.id,kind:this.native.kind});}
  }
  const wordsEl=new Element('words'), mainElement=new Element('caret'), paceElement=new Element('paceCaret');
  const base=rtl?-88:100;
  wordsEl.getOffsetWidth=()=>400;
  function connected(){return children.filter(child=>child.native.isConnected);}
  function rowOf(node){let row=0;for(const child of connected()){if(child===node)return row;if(child.hasClass('newline'))row++;}return row;}
  function indentBefore(node){let indent=0;for(const child of connected()){if(child===node)return indent;if(child.hasClass('afterNewline'))indent=child.native.marginLeft;}return indent;}
  const words=Array.from({length:6},(_,index)=>{
    const word=new Element('word'+index,'word');word.index=index;if(index===0)word.addClass('active');
    word.getOffsetWidth=()=>48;word.getOuterWidth=()=>60;word.getOffsetHeight=()=>32;word.getOuterHeight=()=>45;
    word.getOffsetLeft=()=>Math.round((rtl?340-indentBefore(word):indentBefore(word))+wordsEl.native.marginLeft);
    word.getAttribute=name=>name==='data-wordindex'?String(index):null;
    const letters=[0,1,2,3].map(i=>{
      const letter=new Element('letter'+index+'-'+i,'letter');letter.native.textContent=i===3?'\n':rtl?'א':'a';
      letter.getOffsetWidth=()=>12;letter.getOffsetHeight=()=>32;letter.getOffsetTop=()=>0;
      letter.getOffsetLeft=()=> (rtl?3-i:i)*12;return letter;
    });
    word.qsa=selector=>{assert.equal(selector,'letter');return letters;};
    word.qs=selector=>{assert.equal(selector,'letter.nlChar');return letters[3];};
    children.push(word,new Element('before'+index,'beforeNewline'),new Element('newline'+index,'newline'),new Element('after'+index,'afterNewline'));
    return word;
  });
  wordsEl.getChildren=connected;wordsEl.qsa=selector=>{assert.equal(selector,'.afterNewline');return connected().filter(x=>x.hasClass('afterNewline'));};
  wordsEl.qs=selector=>{
    if(selector==='.active')return connected().find(word=>word.hasClass('active'))??null;
    const match=/^\.word\[data-wordindex="(\d+)"\]$/.exec(selector);assert.ok(match,selector);
    return connected().find(word=>word.hasClass('word')&&word.index===Number(match[1]))??null;
  };
  const Config={mode:'words',funbox:[],tapeMode:mode,tapeMargin:25,smoothLineScroll:smooth,smoothCaret:'medium',
    caretStyle:style,blindMode:false,hideExtraLetters:false,showAllLines:false,keymapMode:'off'};
  Object.assign(context,{Config,wordsEl,wordsWrapperEl:{getOffsetWidth:()=>400},currentTestLine:0,
    activeWordTop:0,activeWordHeight:32,lineTransition:false,centeringActiveLine:Promise.resolve(),
    qsr:selector=>({'#words':wordsEl,'#wordsWrapper':{getOffsetWidth:()=>400},'#caret':mainElement,'#paceCaret':paceElement}[selector]),
    getTotalInlineMargin:()=>12,TestWords:{words:{get:()=>({display:rtl?'אאא\n':'aaa\n'})}},
    getActivePage:()=>'test',getResultVisible:()=>false,isDirectionReversed:()=>false,isLanguageRightToLeft:()=>rtl,
    getActiveWordElement:()=>words[active],getActiveWordIndex:()=>active,getCurrentInput:()=>input,
    window:{getComputedStyle:native=>({marginRight:native.kind==='word'?'12':'0',marginLeft:'0'})},
    configEvent:{subscribe(){}},CompositionState:{getData:()=>''},Joining:{set(){}},Numbers:{isSafeNumber:Number.isFinite},
    CustomText:{getLimitMode:()=>'words',getLimitValue:()=>6},updateWordsWrapperHeight(){},updateWordsInputPosition(){},
    animejsAnimate:(target,options)=>{assert.equal(target,wordsEl.native);return wordsEl.animate(options);}});
  vm.runInContext(rafModule+directionModule,context);
  vm.runInContext('{'+caretModule+'\nglobalThis.SourceCaret=Caret;}',context);
  vm.runInContext('{const Caret=SourceCaret;'+mainModule+'\nglobalThis.MainController={caret,updatePosition};}',context);
  const main=context.MainController.caret, pace=new context.SourceCaret(paceElement,style);
  Object.assign(context,{Caret:context.MainController,PaceCaret:{caret:pace}});
  vm.runInContext(promiseAdapter+';globalThis.promiseAdapter=new Adapter();',context);
  context.promiseAdapter.native=wordsEl.native;wordsEl.promiseAnimate=options=>context.promiseAdapter.promiseAnimate(options);
  vm.runInContext(callbacks,context);
  for(const [method,type,field] of [['handleTapeScroll','scroll','newValue'],['handleLineJump','line','newMarginTop']]){
    const original=pace[method].bind(pace);pace[method]=options=>{
      trace.push({type,time:clock-10000,value:options[field],duration:options.duration});return original(options);
    };
  }
  const retire=pace.handleTapeWordsRemoved.bind(pace);
  pace.handleTapeWordsRemoved=value=>{trace.push({type:'retire',time:clock-10000,value});return retire(value);};
  for(const [caret,element] of [[main,mainElement],[pace,paceElement]]){
    let target;const geometry=caret.getTargetPositionAndWidth.bind(caret);
    caret.getTargetPositionAndWidth=options=>{target=geometry(options);return target;};
    for(const method of ['setPosition','animatePosition']){
      const original=caret[method].bind(caret);caret[method]=options=>{
        trace.push({type:'position',id:element.native.id,time:clock-10000,x:target.left+(style==='default'?1:0),y:target.top,
          width:caret.isFullWidth()?target.width:element.native.width,height:element.getOffsetHeight(),
          wordsX:wordsEl.native.marginLeft-base,wordsY:wordsEl.native.marginTop,
          duration:method==='setPosition'?0:options.duration??100});return original(options);
      };
    }
  }
  function marker(element,caret){return {x:element.native.left+(style==='default'?1:0),y:element.native.top,width:element.native.width,
    vertical:element.native.marginTop,horizontal:element.native.marginLeft,verticalReady:caret.readyToResetMarginTop,
    horizontalReady:caret.readyToResetMarginLeft,correction:caret.cumulativeTapeMarginCorrection};}
  function sample(reason='frame'){trace.push({type:'sample',time:clock-10000,reason,wordsX:wordsEl.native.marginLeft-base,
    wordsY:wordsEl.native.marginTop,first:connected().find(x=>x.hasClass('word'))?.index??6,
    leadingFiller:connected()[0]?.hasClass('afterNewline')??false,main:marker(mainElement,main),pace:marker(paceElement,pace)});}
  async function drain(){for(let i=0;i<12;i++)await Promise.resolve();}
  async function flush(){for(const [id,callback] of [...frames]){frames.delete(id);callback();}await drain();}
  function paceTo(word,letter,duration=0){pace.goTo({wordIndex:word,letterIndex:letter,isLanguageRightToLeft:rtl,
    isDirectionReversed:false,animate:true,animationOptions:{duration,easing:'linear'}});}
  async function tickTo(time){while(clock<10000+time){clock++;inFrame=true;rendered=false;anime.namespace.engine.update();inFrame=false;
    trace.push({type:'frame',time:clock-10000,rendered});await drain();await flush();sample();}}
  await context.scrollTape(true);context.Caret.updatePosition(true);paceTo(1,0);await flush();sample('initial');
  active=1;await context.afterTestWordChange('forward');await flush();sample('first-line');
  assert.equal(trace.filter(x=>x.type==='line').length,0,'First line only increments the source line counter');
  await tickTo(200);paceTo(2,0);await flush();sample('pace-fold');
  active=2;await context.afterTestWordChange('forward');await flush();paceTo(3,0,180);await flush();sample('jump-request');
  const before=trace.filter(x=>x.type==='scroll').length;
  if(smooth)assert.equal(before,2,'Active-word tape scroll must await the vertical promise');
  if(independent){await tickTo(250);input='a';await context.scrollTape();context.Caret.updatePosition();await flush();sample('independent-scroll');}
  if(overlap){await tickTo(260);active=3;await context.afterTestWordChange('forward');await flush();paceTo(4,0,180);await flush();sample('overlapping-line');}
  await tickTo(400);context.Caret.updatePosition();paceTo(3,1);await flush();sample('fold-both');
  await tickTo(550);
  const complete=trace.filter(x=>x.type==='sample'&&x.reason==='vertical-completion');
  assert.equal(complete.length,smooth?1:0);
  if(smooth)assert.equal(complete[0].leadingFiller,true,'lineJump leaves the leading filler for scrollTape cleanup');
  assert.equal(connected().find(x=>x.hasClass('word')).index,overlap?2:1);
  assert.equal(connected()[0].hasClass('afterNewline'),false);
  assert.deepEqual(removed.filter(x=>x.kind==='word').map(x=>x.id),overlap&&smooth?['word1','word0']:overlap?['word0','word1']:['word0']);
  assert.ok(removed.every(x=>['word','newline','beforeNewline','afterNewline'].includes(x.kind)));
  const retirements=trace.filter(x=>x.type==='retire');
  assert.equal(retirements.length,overlap&&!smooth?2:1);
  assert.equal(retirements.reduce((total,x)=>total+x.value,0),(rtl?-1:1)*(overlap?72:36));
  assert.equal(context.lineTransition,false);assert.equal(wordsEl.native.marginTop,0);
  assert.ok(trace.filter(x=>x.type==='sample').every(x=>x.main.horizontal===0),'Main remains locked');
  fixtures.push({rtl,mode,smooth,style,independent,overlap,trace,removed});
  main.stopAllAnimations();pace.stopAllAnimations();for(const animation of animations)animation.cancel();
}
verify();assert.equal(fixtures.length,128);
if(option)process.stdout.write(JSON.stringify({pin,fixtures}));
else console.log('Tape/line source composition passed: 128 complete active-word/lineJump/scrollTape/Caret/main-controller/RAF/promiseAnimate sequences with real locked Anime.js, LTR/RTL, letter/word, four styles, immediate/smooth, independent scroll during vertical await and overlapping jumps, leading-filler removal and correction; owned DOM/1ms clock, not browser CSS, native geometry or arbitrary queue parity');
