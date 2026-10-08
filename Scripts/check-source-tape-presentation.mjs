// QA only: complete pinned scrollTape/getNlCharWidth, Caret, RAF and locked Anime.js.
// Single-line LTR/RTL owned DOM boxes/clock; not browser CSS or complete Tape/removal proof.
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
assert.ok(archive, 'Requires the pinned Anime.js 4.2.2 archive');
const integrity = 'sha512-' + createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
assert.equal(integrity, 'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
assert.ok(fs.readFileSync(path.join(root, 'pnpm-lock.yaml'),'utf8').includes(integrity));
const bundle = execFileSync('tar',['-xOf',archive,'package/dist/bundles/anime.esm.js'], {encoding:'utf8',maxBuffer:2**21});
const ui = fs.readFileSync(path.join(root,'frontend/src/ts/test/test-ui.ts'),'utf8');
const begin = ui.indexOf('function getNlCharWidth('), end = ui.indexOf('\nfunction removeTestElements(',begin);
assert.ok(begin >= 0 && end > begin);
function plain(source) { return stripTypeScriptTypes(source.replace(/^import [\s\S]*?;\n/gm,'').replace(/^export /gm,''), {mode:'transform'}); }
const callbacks = plain(ui.slice(begin,end));
const caretModule = plain(fs.readFileSync(path.join(root,'frontend/src/ts/elements/caret.ts'),'utf8'));
const rafModule = plain(fs.readFileSync(path.join(root,'frontend/src/ts/utils/debounced-animation-frame.ts'),'utf8'));
const strings = fs.readFileSync(path.join(root,'frontend/src/ts/utils/strings.ts'),'utf8');
const directionModule = plain(strings.slice(strings.indexOf('function hasRTLCharacters('), strings.indexOf('\nexport const CHAR_EQUIVALENCE_SETS')));
const fixtures = [];
for (const rtl of [false,true])
for (const wordRTL of [false,true])
for (const mode of ['letter','word']) for (const style of ['default','block','outline','underline'])
for (const smooth of [false,true]) for (const overlap of [false,true]) {
  let clock=10000, frameID=0, active=0, input='';
  const frames=new Map(), animations=[], trace=[];
  class ControlledDate extends Date { static now(){return clock;} }
  const context=vm.createContext({Date:ControlledDate, performance:{now:()=>clock-10000},
    requestAnimationFrame:callback=>{frames.set(++frameID,callback);return frameID;},
    cancelAnimationFrame:id=>frames.delete(id),
    setImmediate(){throw new Error('Unexpected automatic animation loop');},clearImmediate(){},
  });
  const anime=new vm.SourceTextModule(bundle,{context});
  await anime.link(id=>{throw new Error('Unexpected bundle import '+id);}); await anime.evaluate();
  anime.namespace.engine.useDefaultMainLoop=false; anime.namespace.engine.fps=1000;
  anime.namespace.engine.defaults.frameRate=1000;
  let inFrame=false, rendered=false;
  const requestTick=anime.namespace.engine.requestTick.bind(anime.namespace.engine);
  anime.namespace.engine.requestTick=time=>{const result=requestTick(time);if(inFrame)rendered=!!result;return result;};
  class Element {
    constructor(id){this.native={id,left:0,top:0,width:2,marginLeft:0,marginTop:0};this.classes=new Set();}
    addClass(v){for(const c of Array.isArray(v)?v:[v])this.classes.add(c);}
    removeClass(v){for(const c of Array.isArray(v)?v:[v])this.classes.delete(c);}
    hasClass(v){return this.classes.has(v);}
    getStyle(){return Object.fromEntries(['left','top','width','marginLeft','marginTop'].map(k=>[k,this.native[k]+'px']));}
    setStyle(value){for(const [k,v] of Object.entries(value))this.native[k]=v===''?k==='width'?2:0:parseFloat(v);}
    getOffsetWidth(){return this.native.width;}
    getOffsetHeight(){return this.hasClass('underline')?2:32;}
    animate(options){const animation=anime.namespace.animate(this.native,options);animations.push(animation);return animation;}
  }
  const wordsEl=new Element('words'), mainElement=new Element('caret'), paceElement=new Element('paceCaret');
  wordsEl.getOffsetWidth=()=>400;
  const words=Array.from({length:5},(_,index)=>{
    const word=new Element('word'+index);word.addClass('word');word.index=index;
    word.getOffsetLeft=()=> (rtl?400-36-12-index*48:index*48)+wordsEl.native.marginLeft;
    word.getOffsetTop=()=>0;word.getOffsetWidth=()=>36;word.getOuterWidth=()=>48;
    word.qsa=selector=>{assert.equal(selector,'letter');return [0,1,2].map(i=>({native:{textContent:wordRTL?'א':'a'},
      getOffsetLeft:()=> (wordRTL?2-i:i)*12,getOffsetTop:()=>0,getOffsetWidth:()=>12,getOffsetHeight:()=>32,hasClass:()=>false}));};
    word.remove=()=>{throw new Error('These bounded fixtures must not remove words');};return word;
  });
  wordsEl.getChildren=()=>words;wordsEl.qsa=selector=>{assert.equal(selector,'.afterNewline');return [];};
  wordsEl.qs=selector=>{
    const match=/^\.word\[data-wordindex="(\d+)"\]$/.exec(selector);assert.ok(match,selector);
    return words[Number(match[1])]??null;
  };
  const Config={mode:'words',funbox:[],tapeMode:mode,tapeMargin:25,smoothLineScroll:smooth,
    smoothCaret:'medium',blindMode:false,hideExtraLetters:false};
  Object.assign(context,{Config,wordsEl,wordsWrapperEl:{getOffsetWidth:()=>400},
    qsr:selector=>selector==='#words'?wordsEl:{getOffsetWidth:()=>400},
    getTotalInlineMargin:()=>12,
    TestWords:{words:{get:()=>({display:wordRTL?'אאא':'aaa'})}},
    getActivePage:()=>'test',getResultVisible:()=>false,centeringActiveLine:Promise.resolve(),
    isDirectionReversed:()=>false,isLanguageRightToLeft:()=>rtl,getActiveWordElement:()=>words[active],
    getCurrentInput:()=>input,window:{getComputedStyle:()=>({marginRight:'12'})},
  });
  vm.runInContext(rafModule,context);
  vm.runInContext(directionModule,context);
  vm.runInContext('{'+caretModule+'\nglobalThis.SourceCaret = Caret;}',context);
  const main=new context.SourceCaret(mainElement,style), pace=new context.SourceCaret(paceElement,style);
  Object.assign(context,{Caret:{caret:main},PaceCaret:{caret:pace}});
  vm.runInContext(callbacks,context);
  const scroll=pace.handleTapeScroll.bind(pace);
  pace.handleTapeScroll=options=>{trace.push({type:'scroll',time:clock-10000,value:options.newValue,duration:options.duration});return scroll(options);};
  for(const [caret,element] of [[main,mainElement],[pace,paceElement]]){
    let target;
    const geometry=caret.getTargetPositionAndWidth.bind(caret);
    caret.getTargetPositionAndWidth=options=>{target=geometry(options);return target;};
    for(const method of ['setPosition','animatePosition']){
      const original=caret[method].bind(caret);
      caret[method]=options=>{
        // Record the resolved un-folded geometry, not the final animation value.
        trace.push({type:'position',id:element.native.id,time:clock-10000,
          x:target.left+(style==='default'?1:0),width:target.width,
          words:wordsEl.native.marginLeft-(rtl?-88:100),
          duration:method==='setPosition'?0:options.duration??100,linear:options.easing==='linear'});
        return original(options);
      };
    }
  }
  function marker(element,caret){return {x:element.native.left+(style==='default'?1:0),
    margin:element.native.marginLeft,visible:element.native.left+element.native.marginLeft+(style==='default'?1:0),
    ready:caret.readyToResetMarginLeft,correction:caret.cumulativeTapeMarginCorrection};}
  function sample(){trace.push({type:'sample',time:clock-10000,words:wordsEl.native.marginLeft-(rtl?-88:100),
    main:marker(mainElement,main),pace:marker(paceElement,pace)});}
  function flush(){for(const [id,callback] of [...frames]){frames.delete(id);callback();}}
  function go(letter,paceWord=1,paceLetter=1,duration=200,initial=false){
    main.goTo({wordIndex:active,letterIndex:letter,isLanguageRightToLeft:rtl,isDirectionReversed:false,animate:!initial});
    pace.goTo({wordIndex:paceWord,letterIndex:paceLetter,isLanguageRightToLeft:rtl,isDirectionReversed:false,
      animate:true,animationOptions:{duration,easing:'linear'}});flush();
  }
  function tickTo(time){while(clock<10000+time){clock++;inFrame=true;rendered=false;anime.namespace.engine.update();inFrame=false;
    trace.push({type:'frame',time:clock-10000,rendered});flush();sample();}}
  await context.scrollTape(true);go(0,1,0,0,true);sample();
  assert.equal(wordsEl.native.marginLeft,rtl?-88:100,'Initial tape margin follows test flow and CSS word-right margin');
  input='a';await context.scrollTape();go(1);sample();
  tickTo(25);
  if(overlap){input='aa';await context.scrollTape();go(2,2,0,150);sample();}
  tickTo(220);
  go(input.length,2,1,0);sample(); // A completed margin folds only on the next goTo.
  active=1;input='a';await context.scrollTape();go(1,3,0,100);sample();
  tickTo(450);go(1,3,1,0);sample();
  assert.equal(mainElement.native.marginLeft,0,'Locked main never receives a tape margin');
  assert.equal(main.cumulativeTapeMarginCorrection,0);
  assert.equal(wordsEl.native.marginLeft,rtl?(mode==='letter'?-28:-40):(mode==='letter'?40:52));
  assert.equal(trace.filter(item=>item.type==='scroll').length,overlap?4:3);
  fixtures.push({rtl,wordRTL,mode,style,smooth,overlap,trace});
  main.stopAllAnimations();pace.stopAllAnimations();for(const animation of animations)animation.cancel();
}
const context=vm.createContext({});vm.runInContext(directionModule,context);
const directions=[];
for(const text of ['', 'אבג', 'abc', '123', '؟', '،אבג؟', 'word؟', '🙂', 'aא', '\u200b', 'أهلاً', 'الله', '،', 'א1'])
for(const fallback of [false,true]) directions.push({text,fallback,rtl:context.isWordRightToLeft(text,fallback,false)[0]});
verify();assert.equal(fixtures.length,128);assert.equal(directions.length,28);
if(option)process.stdout.write(JSON.stringify({pin,fixtures,directions}));
else console.log('Tape presentation source passed: 128 complete scrollTape/Caret/RAF sequences and 28 complete direction-helper cases with real locked Anime.js, independent LTR/RTL test and word flow, single-line owned boxes/clock, four styles, immediate/smooth/overlap/folding; not browser CSS, removal, newline, reverse-direction or arbitrary scheduling proof');
