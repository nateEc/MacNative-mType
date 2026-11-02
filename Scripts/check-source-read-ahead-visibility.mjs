// QA only: pinned CSS selectors plus complete caret controller and key handler.
// Word/input/focus/DOM boundaries are owned; this is not browser CSS-engine QA.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const baseCSS = read('frontend/src/styles/test.scss');
for (const token of ['&.correct {', 'color: var(--correct-letter-color);',
  '&.incorrect {', 'color: var(--incorrect-letter-color);', '&.highlight-off {',
  'letter.correct {', 'color: var(--untyped-letter-color);', '&.blind {']) assert.ok(baseCSS.includes(token));
const template = read('frontend/src/html/pages/test.html');
assert.match(template, /id="caret"[\s\S]*?<\/div>\s*<div id="words"/);
const styles = ['read_ahead_easy', 'read_ahead', 'read_ahead_hard', 'simon_says'].map(name => {
  const css = read(`frontend/static/funbox/${name}.css`);
  assert.ok(!css.includes('caret') && !css.includes('.correct') && !css.includes('.incorrect'));
  assert.match(css, /--untyped-letter-color:\s*transparent/);
  if (name === 'simon_says') return {name, offsets:null, firstActive:0};
  const selectors = css.slice(0, css.indexOf('{')).split(',');
  assert.ok(selectors.every(value => value.includes('#words:not(.read_ahead_disabled)')));
  const first = [...css.matchAll(/nth-of-type\(n\s*\+\s*(\d+)\)/g)].map(value => Number(value[1]));
  assert.ok(first.length > 0 && first.every(value => value === first[0]));
  return {name, offsets:selectors.map(value => [...value.matchAll(/\.word\b/g)].length - 1), firstActive:first[0] - 1};
});
const controller = stripTypeScriptTypes(read('frontend/src/ts/test/caret.ts')
  .replace(/^import [\s\S]*?;\n/gm, '').replace(/^export /gm, ''), {mode:'transform'});
const ui = read('frontend/src/ts/test/test-ui.ts');
const htmlBegin = ui.indexOf('function buildWordHTML('), htmlEnd = ui.indexOf('\nfunction updateWordWrapperClasses(', htmlBegin);
assert.ok(htmlBegin >= 0 && htmlEnd > htmlBegin);
const html = stripTypeScriptTypes(ui.slice(htmlBegin,htmlEnd), {mode:'transform'});
const removeBegin = ui.indexOf('function removeTestElements('), removeEnd = ui.indexOf('\nlet currentLinesJumping',removeBegin);
assert.ok(removeBegin >= 0 && removeEnd > removeBegin);
const remove = stripTypeScriptTypes(ui.slice(removeBegin,removeEnd), {mode:'transform'});
const correctBegin=ui.indexOf('export function highlightAllLettersAsCorrect(');
const correctEnd=ui.indexOf('\nfunction updateWordsWidth(',correctBegin);
const beforeBegin=ui.indexOf('export function beforeTestWordChange(');
const beforeEnd=ui.indexOf('\nexport async function afterTestWordChange(',beforeBegin);
assert.ok(correctBegin>=0 && correctEnd>correctBegin && beforeBegin>=0 && beforeEnd>beforeBegin);
const commit=stripTypeScriptTypes((ui.slice(correctBegin,correctEnd)+'\n'+ui.slice(beforeBegin,beforeEnd))
  .replace(/^export /gm,''),{mode:'transform'});
function wordNodes(words) {
  const context = vm.createContext({findSingleActiveFunboxWithFunction:()=>null,
    Strings:{splitIntoCharacters:value=>Array.from(value)}});
  new vm.Script(html).runInContext(context, {timeout:1000});
  const output = words.map((word,index)=>context.buildWordHTML(word,index)).join('');
  return [...output.matchAll(/<div class=['"]([^'"]+)['"]([^>]*)>/g)].map(match=>({
    kind:match[1], word:Number(/data-wordindex=['"](\d+)['"]/.exec(match[2])?.[1] ?? -1)}));
}
const fixtures = [];
function addFixture(words,style,active,highlight,blind,entered,firstRetained=0,removed=[]) {
  const prefixInputs=words.map(word=>word.includes('\n') ? word[0] : word);
  const priorCorrectClasses=words.map((word,field)=>{
    const letters=Array.from(word).map((_,index)=>({correct:field<active && index<prefixInputs[field].length,
      addClass(value){if(value==='correct')this.correct=true;}}));
    if(field<active) {
      const context=vm.createContext({Config:{blindMode:blind},getActiveWordIndex:()=>field,
        getWordElement:()=>({getChildren:()=>letters}),requestDebouncedAnimationFrame:(_,callback)=>callback(),
        highlightBadWord(){},updateWordLetters(){},getCurrentInput:()=>prefixInputs[field],
        CompositionState:{getData:()=>''}});
      new vm.Script(commit).runInContext(context,{timeout:1000});
      context.beforeTestWordChange('forward',prefixInputs[field]===word);
    }
    return letters.map(value=>value.correct);
  });
  const calls = [];
  class Caret {
    show() {} startBlinking() {} stopBlinking() {}
    goTo(value) { calls.push(structuredClone(value)); }
  }
  const context = vm.createContext({Config:{funbox:[style.name], smoothCaret:'off', caretStyle:'default'},
    getCurrentInput:()=>entered, getActiveWordIndex:()=>active,
    isDirectionReversed:()=>false, isLanguageRightToLeft:()=>false,
    CompositionState:{getData:()=>''}, configEvent:{subscribe() {}}, Caret, qsr:()=>({})});
  new vm.Script(controller + '\nshow();').runInContext(context, {timeout:1000});
  assert.equal(calls.length, 1);
  let nodes = wordNodes(words);
  const elements = nodes.map(node=>({...node,native:{isConnected:true},remove(){this.native.isConnected=false;}}));
  if(firstRetained>0) {
    const first=elements.findIndex(node=>node.word===firstRetained);
    assert.ok(first>0);
    // Owned stable line-jump boundary: keep the trailing afterNewline node.
    const last=first-1-(elements[first-1].kind==='afterNewline' ? 1 : 0);
    const context=vm.createContext({wordsEl:{getChildren:()=>elements}});
    new vm.Script(remove).runInContext(context,{timeout:1000});
    context.removeTestElements(last);
  }
  for(const node of elements)if(removed.includes(node.word))node.remove();
  nodes=elements.filter(node=>node.native.isConnected);
  const activeNode = nodes.findIndex(node=>node.word===active); assert.ok(activeNode>=0);
  fixtures.push({words, prefixInputs, priorCorrectClasses,
    modifier:style.name, active, entered, highlight, blind, firstRetained, removed, caret:calls[0],
    hiddenFields:words.map((_, field) => {
      const node = nodes.findIndex(value=>value.word===field), distance=node-activeNode;
      if(node<0)return false;
      return style.offsets === null || (activeNode >= style.firstActive && style.offsets.includes(distance)
        && nodes.slice(activeNode+1,node+1).every(value=>value.word>=0));
    })});
}
for (const words of [['oak','ash','elm','pine'], ['north\nsouth','harbor','tail','bay'],
  ['oak','harbor\nstone','elm','pine']])
for (const style of styles) for (let active = 0; active < words.length; active++)
for (const highlight of ['letter','off']) for (const blind of [false,true])
for (const entered of ['',words[active][0],'x'])addFixture(words,style,active,highlight,blind,entered);
const pruning = [
  {words:['oak','ash','elm','pine'],active:2,first:2,removed:[]},
  {words:['oak','ash\nbay','elm','pine'],active:2,first:2,removed:[]},
  {words:['oak\nbay','ash','elm','pine'],active:1,first:0,removed:[0]},
  {words:['oak','ash','elm','pine'],active:1,first:0,removed:[2]},
  {words:['oak','ash','elm\nbay','pine'],active:1,first:0,removed:[2]},
];
for(const item of pruning)for(const style of styles)
for(const highlight of ['letter','off'])for(const blind of [false,true])
for(const entered of ['',item.words[item.active][0],'x'])
  addFixture(item.words,style,item.active,highlight,blind,entered,item.first,item.removed);
const functions = read('frontend/src/ts/test/funbox/funbox-functions.ts');
const begin = functions.indexOf('async function readAheadHandleKeydown(');
const end = functions.indexOf('\n//todo move', begin);
assert.ok(begin >= 0 && end > begin);
const handler = stripTypeScriptTypes(functions.slice(begin, end), {mode:'transform'});
const keys = [];
for (const key of ['Backspace',' ','Enter','Delete','x'])
for (const current of ['', 'o', 'ox', 'oak', 'oakx', 'o😀', 'o😁'])
for (const disabled of [false,true]) {
  let after = disabled;
  const target = current.includes('😀') || current.includes('😁') ? 'o😀k' : 'oak';
  const context = vm.createContext({Config:{freedomMode:false},
    getCurrentInput:()=>current, TestWords:{words:{getCurrent:()=>({display:target}),
      get:()=>({textWithCommit:'oak '})}}, getActiveWordIndex:()=>1, getInputForWord:()=> 'oak ',
    qs:()=>({addClass:value=>{assert.equal(value,'read_ahead_disabled'); after=true;},
      removeClass:value=>{assert.equal(value,'read_ahead_disabled'); after=false;}})});
  new vm.Script(handler).runInContext(context, {timeout:1000});
  await context.readAheadHandleKeydown({key});
  keys.push({key,current,target,before:disabled,after});
}
const wrapperBegin = ui.indexOf('function updateWordWrapperClasses(');
const wrapperEnd = ui.indexOf('\nexport function appendEmptyWordElement(', wrapperBegin);
assert.ok(wrapperBegin >= 0 && wrapperEnd > wrapperBegin);
const wrapper = stripTypeScriptTypes(ui.slice(wrapperBegin, wrapperEnd), {mode:'transform'});
const classRetention = [];
for (const before of [false,true]) {
  const element = () => ({native:{className:''}, setStyle() {}, setHtml() {},
    addClass(value) { this.native.className += ` ${value}`; },
    removeClass(value) { this.native.className = this.native.className.split(/\s+/).filter(v=>v!==value).join(' '); }});
  const wordsEl = element(); wordsEl.native.className = before ? 'read_ahead_disabled highlight-off' : 'highlight-off';
  const context = vm.createContext({wordsEl, wordsWrapperEl:element(), Config:{mode:'words', tapeMode:'off',
    indicateTypos:'off', fontSize:1.75, highlightMode:'letter', typedEffect:null, showAllLines:true},
    qs:()=>element(), qsa:()=>element(), isLanguageRightToLeft:()=>false,
    setTestFocusState() {}, updateWordsWidth() {}, updateWordsWrapperHeight() {}, updateWordsMargin() {},
    updateWordsInputPosition() {}, updateHintsPositionDebounced() {}, Caret:{updatePosition() {}},
    PaceCaret:{resetCaretPosition() {}}, isInputElementFocused:()=>true,
    updateActiveElement() {}, TestWords:{words:{length:2,get:index=>({display:['oak','ash'][index]})}},
    buildWordHTML:word=>`<div>${word}</div>`});
  new vm.Script(wrapper + '\nshowWords();').runInContext(context, {timeout:1000});
  const after = wordsEl.native.className.split(/\s+/).includes('read_ahead_disabled');
  assert.equal(after,before); classRetention.push({before,after});
}
assert.equal(fixtures.length, 816); assert.equal(keys.length, 70);
verify();
if (emit) process.stdout.write(JSON.stringify({fixtures,keys,classRetention}));
else console.log('Hidden target source passed (816 selector/HTML/controller/removal, 70 complete key-handler and 2 word-rebuild cases; owned boundaries, no browser/layout/device proof)');
