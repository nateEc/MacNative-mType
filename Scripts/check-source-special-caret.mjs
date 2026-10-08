// QA only: execute the complete pinned Caret module, not a translated resolver.
// LTR layout boxes, CSS widths/margins and DOM utilities are explicit owned boundaries.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const [argument, option, requestedSpaceWidth] = process.argv.slice(2);
assert.ok(argument && (!option || option === '--emit-fixtures'));
const root=path.resolve(argument), pin='91bd24bb8513785c7364cbea29296ff7adafac41';
const spaceWidth=Number(requestedSpaceWidth ?? 8);
assert.ok(Number.isFinite(spaceWidth) && spaceWidth > 0 && spaceWidth < 1000);
function verify(){
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const source=fs.readFileSync(path.join(root,'frontend/src/ts/elements/caret.ts'),'utf8');
const module=stripTypeScriptTypes(source.replace(/^import [\s\S]*?;\n/gm,'').replace(/^export /gm,''),{mode:'transform'});
const tts=fs.readFileSync(path.join(root,'frontend/static/funbox/tts.css'),'utf8');
assert.match(tts, /#words\s*\{\s*--untyped-letter-color:\s*transparent\s*!important;\s*\}/);
assert.ok(!tts.includes('caret'), 'The pinned listening stylesheet does not hide the independent caret');
const css=fs.readFileSync(path.join(root,'frontend/src/styles/test.scss'),'utf8');
for(const token of ['&.correct {','color: var(--correct-letter-color);','&.incorrect {','color: var(--incorrect-letter-color);',
  '&.incorrect.extra {','color: var(--extra-letter-color);','&.highlight-off {'])assert.ok(css.includes(token));
const frames=[{x:10,y:3,width:20,height:32},{x:30,y:3,width:0,height:32},{x:30,y:3,width:24,height:32}];
const fixtures=[];
for(const style of ['default','block','outline','underline'])
for(const [index,side] of [[0,'beforeLetter'],[1,'beforeLetter'],[2,'beforeLetter'],[2,'afterLetter']]){
  const wordLeft=13,wordTop=7;
  const letters=frames.map(frame=>({native:{textContent:'a'},getOffsetWidth:()=>frame.width,getOffsetHeight:()=>frame.height,
    getOffsetLeft:()=>frame.x,getOffsetTop:()=>frame.y}));
  const word={native:{},qsa:()=>letters,getOffsetLeft:()=>wordLeft,getOffsetTop:()=>wordTop,getOffsetWidth:()=>80};
  const element={native:{id:'paceCaret'},setStyle(){},addClass(){},removeClass(){},hasClass:()=>false,
    getOffsetWidth:()=>2,getOffsetHeight:()=>32};
  const context=vm.createContext({Config:{mode:'words',funbox:[],tapeMode:'off',tapeMargin:0,smoothCaret:'off'},
    qsr:()=>({getOffsetWidth:()=>400}),getTotalInlineMargin:()=>spaceWidth,isWordRightToLeft:()=>[false,true],
    requestDebouncedAnimationFrame:(_,callback)=>callback(),element,word,style,index,side});
  new vm.Script(module+'\nconst caret = new Caret(element,style);\n').runInContext(context,{timeout:1000});
  const result=new vm.Script('caret.getTargetPositionAndWidth({word,letterIndex:index,wordText:"aaa",side,isLanguageRightToLeft:false,isDirectionReversed:false})')
    .runInContext(context,{timeout:1000});
  const visible=frames[index].width>0 ? frames[index] : frames[0];
  fixtures.push({style,index,after:side==='afterLetter',spaceWidth,
    rect:{x:wordLeft+visible.x,y:wordTop+visible.y,width:visible.width,height:visible.height},
    source:{left:result.left,top:result.top,width:result.width}});
}
assert.equal(fixtures.length,16);verify();
if(option)process.stdout.write(JSON.stringify({pin,fixtures}));
else console.log('Special caret source passed (complete Caret module, 16 LTR box/zero-width/after-target cases; listening CSS declarations checked statically, owned DOM/metrics/direction, no browser/CSS-engine/animation proof)');
