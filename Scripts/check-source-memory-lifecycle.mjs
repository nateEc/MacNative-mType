// QA only: real restart/start callers, Memory handlers, timer and UI reset.
// Generation, unrelated services and DOM/layout endpoints are owned adapters.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {stripTypeScriptTypes} from 'node:module';

assert.ok(process.argv[2], 'Pinned reference required');
const root = path.resolve(process.argv[2]);
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
function section(file, start, end) {
  const source = fs.readFileSync(path.join(root, 'frontend/src/ts', file), 'utf8');
  const first = source.indexOf(start), last = end ? source.indexOf(end, first) : source.length;
  assert.ok(first >= 0 && last > first, `Missing pinned section: ${file} ${start}`);
  return stripTypeScriptTypes(source.slice(first, last).replace(/^export /gm, ''), {mode:'transform'});
}
const timer = section('test/funbox/memory-funbox-timer.ts', 'let memoryTimer:');
const handlers = section('test/funbox/funbox-functions.ts', 'const list: Partial');
const restart = section('test/test-logic.ts', 'export async function restart(', 'let lastInitError:');
const start = section('test/test-logic.ts', 'export function startTest(', 'type RestartOptions');
const uiRestart = section('test/test-ui.ts', 'export function onTestRestart(', 'export function onTestFinish(');
const uiStart = section('test/test-ui.ts', 'export function onTestStart(', 'function getRestartAnimationTime(');
const showWords = section('test/test-ui.ts', 'function showWords(', 'export function appendEmptyWordElement(');
const fixtures = [];
for (const mode of ['words', 'quote', 'custom']) for (const count of [1, 2, 4, 25, 100]) {
  for (const keymapMode of ['off', 'static', 'next', 'react']) for (const resultPage of [false, true]) {
    const noop = () => {};
    let active = false, restarting = false, result = resultPage, nextInterval = 0;
    let intervals = new Map(), registered = 0, cleared = 0, remembered = 0;
    const nodes = new Map(), trace = [];
    function node(selector) {
      if (!nodes.has(selector)) nodes.set(selector, {
        visible:true, text:'', opacity:1, html:'',
        show() { this.visible = true; return this; }, hide() { this.visible = false; return this; },
        setText(value) { this.text = value; return this; },
        setStyle() { return this; }, setHtml(value) { this.html = value; return this; },
        animate(options) { this.opacity = options.opacity; return this; },
      });
      return nodes.get(selector);
    }
    const words = Array.from({length:count}, (_, index) => ({display:`owned${index}`}));
    const config = {mode, words:count, time:15, language:'english', resultSaving:false,
      funbox:['memory'], keymapMode, showAllLines:false, repeatQuotes:'off', repeatedPace:false,
      paceCaret:'off', randomTheme:'off', compositionDisplay:'replace'};
    const context = vm.createContext({Config:config, Math, qs:node, wordsEl:node('#words'),
      applyReducedMotion: value => value,
      setInterval(callback, milliseconds) {
        assert.equal(milliseconds, 1000); registered++; intervals.set(++nextInterval, callback); return nextInterval;
      },
      clearInterval(id) { assert.ok(intervals.delete(id)); cleared++; },
      TestWords:{words:{length:count, get:index => words[index]}}, buildWordHTML:display => display,
      getInputElement:() => ({style:{}}), getCurrentQuote:() => null,
      isFunboxActive:name => config.funbox.includes(name), isTestActive:() => active,
      isTestRestarting:() => restarting, isResultCalculating:() => false, isRepeated:() => false,
      setIsTestRestarting:value => { restarting = value; }, setTestActive:value => { active = value; },
      getResultVisible:() => result, setResultVisible:value => { result = value; },
      PractiseWords:{before:{mode:null}}, Funbox:{rememberSettings:async () => { remembered++; }},
      TestTimer:{clear:noop, start:async () => {}}, resetTestEvents:noop,
      setIsTestInvalid:noop, resetModifierState:noop, Replay:{pauseReplay:noop}, setBailedOut:noop,
      PaceCaret:{reset:noop, init:async () => {}, resetCaretPosition:noop},
      setKoreanStatus:noop, clearQuoteStats:noop, CompositionState:{setComposing:noop, setData:noop},
      Strings:{clearWordDirectionCache:noop}, setIsRepeated:noop, setIsPaceRepeat:noop, setInputElementValue:noop,
      Focus:{set:noop}, setCurrentLiveStats:noop, LayoutfluidFunboxTimer:{instantHide:noop},
      focusWords:noop, ResultWordHighlight:{destroy:noop}, MonkeyPower:{reset:noop},
      Caret:{resetPosition:noop}, TestInitFailed:{hide:noop}, ConnectionState:{get:() => true},
      getActivePage:() => 'test', AdController:{updateFooterAndVerticalAds:noop, destroyResult:noop},
      skipBreakdownEvent:{dispatch:noop}, SoundController:{clearAllSounds:async () => {}},
      cancelPendingAnimationFramesStartingWith:noop, updateActiveElement:noop, updateWordWrapperClasses:noop,
      PageTransition:{get:() => false}, isAuthenticated:() => false, AnalyticsController:{log:async () => {}},
      isPaceRepeat:() => false, setConfig:(key,value) => { config[key] = value; return true; },
    });
    vm.runInContext(`(() => {${timer}\n globalThis.MemoryTimer = {start, reset};})()`, context);
    context.MemoryFunboxTimer = {reset:() => { trace.push('ui-reset'); context.MemoryTimer.reset(); }};
    vm.runInContext(handlers, context);
    const memory = context.getFunboxFunctions().memory;
    context.init = async () => { memory.applyConfig(); return true; };
    context.getActiveFunboxesWithFunction = name => [{functions:memory}].filter(fb => typeof fb.functions[name] === 'function');
    vm.runInContext(`let currentTestLine=0; ${showWords}\n${uiRestart}\n${uiStart}`, context);
    context.TestUI = {fadeOutForRestart:async () => {}, fadeInAfterRestart:async () => {},
      onTestRestart:context.onTestRestart, onTestStart:context.onTestStart};
    vm.runInContext(`let testReinitCount=0; let failReason=''; ${restart}\n${start}`, context);
    await context.restart();
    assert.equal(remembered, 1); assert.equal(restarting, false); assert.equal(active, false);
    assert.equal(registered, 1); assert.equal(cleared, 1); assert.equal(intervals.size, 0);
    assert.deepEqual(trace, ['ui-reset']);
    const timerNode = node('#typingTest #memoryTimer');
    assert.equal(timerNode.text, `Timer left to memorise all words: ${Math.round(Math.pow(count, 1.2))}s`);
    assert.equal(timerNode.opacity, 0); assert.equal(node('#words').visible, true);
    const beforeStart = {wordsVisible:node('#words').visible, timerVisible:timerNode.opacity !== 0, pendingTimers:intervals.size};
    // Advancing the fake scheduler cannot expire a cleared interval.
    for (let i=0; i<1000; i++) for (const callback of [...intervals.values()]) callback();
    assert.equal(node('#words').visible, true);
    assert.equal(context.startTest(100), true);
    assert.equal(active, true); assert.equal(node('#words').visible, false); assert.equal(intervals.size, 0);
    const afterStart = {wordsVisible:node('#words').visible, timerVisible:timerNode.opacity !== 0};
    await context.restart();
    assert.equal(remembered, 2); assert.equal(registered, 2); assert.equal(cleared, 2);
    assert.equal(node('#words').visible, true); assert.equal(active, false); assert.equal(intervals.size, 0);
    fixtures.push({mode,count,keymapMode,resultPage,beforeStart,afterStart,restoredWordsVisible:node('#words').visible});
  }
}
verify();
process.stdout.write(JSON.stringify({fixtures}));
