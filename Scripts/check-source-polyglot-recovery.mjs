// QA only: actual init and Polyglot withWords; owned words, metadata, language
// loader, UI and setter endpoints. No reference language assets or transport.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? '');
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
function read(relative) { return fs.readFileSync(path.join(root,'frontend/src/ts',relative),'utf8'); }
const initSource = read('test/test-logic.ts');
const start = initSource.indexOf('async function init(): Promise<boolean> {');
const end = initSource.indexOf('//add word during the test',start);
assert.ok(start >= 0 && end > start);
const initBody = stripTypeScriptTypes(initSource.slice(start,end),{mode:'transform'});
const functionsSource = read('test/funbox/funbox-functions.ts');
const functionsStart = functionsSource.indexOf('const list: Partial<Record<FunboxName, FunboxFunctions>> = {');
assert.ok(functionsStart >= 0);
const functionsBody = stripTypeScriptTypes(functionsSource.slice(functionsStart).replace(/^export /gm,''),{mode:'transform'});
const rtl = name => ['arabic','hebrew','kurdish_central'].includes(name);
const fixtures = [];
for (const base of ['english','arabic','hebrew','kurdish_central','german','code_python']) {
  for (const selected of [['english','german'],['german','english'],['arabic','hebrew'],['hebrew','arabic'],
    ['kurdish_central','arabic'],['arabic','kurdish_central'],['english','arabic'],['arabic','english'],['code_python','english']]) {
    const config = {mode:'words',words:2,language:base,lazyMode:false,funbox:['polyglot'],customPolyglot:selected,
      keymapMode:'off',quoteLength:[0]};
    let calls = 0, resets = 0;
    const writes = [], notices = [];
    const noop = () => {};
    class WordGenError extends Error {}
    class PolyglotWordset { constructor(words) { this.words = [...words.keys()]; } }
    const language = name => ({name,words:[`owned-${name}`],rightToLeft:rtl(name),noLazyMode:true});
    const context = vm.createContext({Config:config,Error,WordGenError,PolyglotWordset,
      console:{debug:noop,log:noop,error:noop},
      JSONData:{getLanguage:async name => language(name)},
      setConfig:(key,value,options) => { assert.equal(key,'language'); assert.equal(options,undefined); writes.push(value); config[key]=value; return true; },
      toggleFunbox:() => { throw Error('Unexpected Polyglot disable'); },
      showNoticeNotification:(_message,options) => notices.push({important:options?.important ?? false,duration:options?.durationMs}),
      showErrorNotification:() => { throw Error('Silent direction recovery must not post an error'); },
      Sentry:{captureException:() => { throw Error('Valid direction recovery cannot exhaust initialization'); }},
      TestInitFailed:{show:() => { throw Error('Initialization failed'); }},
      TestWords:{words:{reset:() => {resets++;},push:noop,get:() => [],getCurrent:() => undefined,removeCommitCharacterFromLastWord:noop}},
      resetActiveWordIndex:noop,showLoaderBar:noop,hideLoaderBar:noop,
      tryCatch:async promise => ({data:await promise,error:null}),getActivePage:() => 'test',
      Funbox:{activate:async () => {},toggleScript:noop},getActiveFunboxNames:() => config.funbox,
      LazyModeState:{getRemember:() => false,setRemember:noop},
      CustomText:{getData:() => ({}),getText:() => []},Misc:{getMode2:() => '2'},getCurrentQuote:() => null,
      setWordsHaveNumbers:noop,setWordsHaveTab:noop,setWordsHaveNewline:noop,
      TestUI:{setJoiningClass:noop},setIsLanguageRightToLeft:noop,setIsDirectionReversed:noop,isFunboxActiveWithProperty:() => false,
    });
    vm.runInContext(functionsBody,context);
    context.WordsGenerator = {generateWords:async () => {
      calls++; assert.ok(calls <= 2);
      await context.getFunboxFunctions().polyglot.withWords([]);
      return {words:['owned north ','owned south'],sectionIndexes:[0,0],hasTab:false,hasNewline:false};
    },areAllWordsGenerated:() => true};
    vm.runInContext('let lastInitError=null; let showedLazyModeNotification=false; let testReinitCount=0;\n'+initBody,context);
    assert.equal(await context.init(),true);
    const conflict = selected.every(name => rtl(name) !== rtl(base));
    assert.equal(calls,conflict ? 2 : 1); assert.equal(resets,calls);
    assert.deepEqual(writes,conflict ? [selected[0]] : []);
    assert.equal(config.language,conflict ? selected[0] : base);
    assert.deepEqual(notices,conflict ? [{important:false,duration:5000}] : []);
    fixtures.push({base,selected,finalLanguage:config.language,writes,notices,calls});
  }
}
assert.equal(fixtures.length,54);
verify();
process.stdout.write(JSON.stringify({fixtures}));
