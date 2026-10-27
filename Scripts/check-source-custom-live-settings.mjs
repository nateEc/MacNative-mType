// QA only: complete pinned Wordset/array/numeric modules and the complete
// getNextWord/areAllWordsGenerated/timer-finish functions. Plain No Quit uses
// neutral text/funbox adapters; custom getters expose post-receipt values.
// This does not emulate the browser's prefetch caller, DOM or real clock.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const reference = process.argv[2];
assert.equal(execFileSync('git', ['-C', reference, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(),
  '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git', ['-C', reference, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
const read = relative => fs.readFileSync(path.join(reference, relative), 'utf8');
const plain = source => stripTypeScriptTypes(source, {mode:'transform'}).replace(/^export /gm, '');
const generator = read('frontend/src/ts/test/words-generator.ts');
const begin = generator.indexOf('export let sectionIndex = 0;');
assert.ok(begin > 0);
const timer = read('frontend/src/ts/test/test-timer.ts');
const timerBegin = timer.indexOf('function checkIfTimeIsUp('), timerEnd = timer.indexOf('\nfunction playTimeWarning(', timerBegin);
assert.ok(timerBegin >= 0 && timerEnd > timerBegin);
const ordinary = process.argv[3] === '--ordinary';
const pool = ordinary ? ['alpha bravo charlie delta echo foxtrot golf hotel india']
  : [Array.from({length:111}, (_,i)=>'old'+i).join(' '), 'harbor stone'];
const cases = ordinary ? [['words',5,'words',17.5], ['words',5,'words',3], ['words',5,'words',0],
  ['words',5,'time',2.5], ['time',100,'words',3], ['time',100,'words',105],
  ['time',100,'words',0], ['words',100,'words',17], ['words',1,'words',2]]
  : [['repeat','word',112.5], ['shuffle','word',112], ['random','word',112],
  ['repeat','section',2], ['repeat','section',2.5], ['shuffle','section',2.5],
  ['random','section',2], ['repeat','word',0], ['repeat','time',2.5]];
const fixtures = [];
for (const entry of cases) {
  const [mode,limitMode,limit] = ordinary ? [entry[0],entry[2],entry[3]] : entry;
  const initialCount = ordinary ? entry[1] : 100;
  const math = Object.create(Math); math.random = ()=>0;
  const live = {mode:'repeat',limitMode:'word',limit:100}, records = [], events = [];
  const context = vm.createContext({Math:math, console:{debug(){}}, Config:{mode:ordinary ? mode : 'custom',
    words:initialCount,time:30,language:'english',
    punctuation:false,numbers:false,funbox:['no_quit']},
    CustomText:{getMode:()=>live.mode,getLimitMode:()=>live.limitMode,getLimitValue:()=>live.limit},
    TestWords:{words:records}, isRepeated:()=>false, currentLanguage:{originalPunctuation:false},
    PolyglotWordset:class {}, WordGenError:Error, PractiseWords:{before:{mode:null}},
    getFunboxWordsFrequency:()=>undefined, getFunboxSection:async()=>[],
    getFunboxWord:value=>value, isCurrentlyUsingFunboxSection:false,
    isFunboxActiveWithFunction:()=>false, isFunboxActiveWithProperty:()=>false,
    applyLazyModeToWord:value=>value, applyBritishEnglishToWord:async value=>value,
    applyFunboxesToWord:value=>value, getCurrentQuote:()=>null,
    timer:null,timerDebug:false,slowTimerCount:0,clearTimeout(){},Caret:{hide(){}},SlowTimer:{clear(){}},
    timerEvent:{dispatch:event=>events.push(event)}});
  const module = relative => new vm.SourceTextModule(stripTypeScriptTypes(read(relative),{mode:'transform'}),{context});
  const numbers = module('packages/util/src/numbers.ts'), arrays = module('frontend/src/ts/utils/arrays.ts');
  const misc = new vm.SyntheticModule(['zipfyRandomArrayIndex'],function(){
    this.setExport('zipfyRandomArrayIndex',()=>{throw Error('Unexpected Zipf branch');});
  },{context});
  const wordset = module('frontend/src/ts/test/wordset.ts');
  await wordset.link(id => {
    if(id==='../utils/misc')return misc;
    if(id==='../utils/arrays')return arrays;
    if(id==='@monkeytype/util/numbers')return numbers;
    throw Error('Unexpected wordset dependency: '+id);
  });
  await wordset.evaluate();
  context.currentWordset = new wordset.namespace.Wordset(pool);
  vm.runInContext(plain(generator.slice(begin))+'\n'+plain(timer.slice(timerBegin,timerEnd)),context);
  async function next(count) {
    const result=[];
    while(result.length<count && !vm.runInContext('areAllWordsGenerated()',context)) {
      const word = await vm.runInContext('getNextWord(TestWords.words.length,100,undefined,undefined)',context);
      records.push({text:word.word}); result.push(word.wordRaw);
    }
    return result;
  }
  const initial = await next(initialCount);
  if(ordinary)Object.assign(context.Config,{mode:limitMode,words:limit,time:limit});
  else Object.assign(live,{mode,limitMode,limit});
  const chunks=[];
  do {
    const words=await next(100), remaining=!vm.runInContext('areAllWordsGenerated()',context);
    chunks.push({words,remaining});
    if(!remaining || limitMode==='time' || limit===0)break;
  } while(chunks.length<4);
  const timeChecks=[2.49,2.5,3].map(elapsed=>{
    events.length=0; context.elapsed=elapsed;
    vm.runInContext('checkIfTimeIsUp(elapsed)',context);
    return {elapsed,finished:events.some(event=>event.key==='finish')};
  });
  assert.deepEqual(context.currentWordset.words,pool);
  fixtures.push({mode,limitMode,limit,initialCount,initial,chunks,timeChecks});
}
process.stdout.write(JSON.stringify({pool,fixtures}));
