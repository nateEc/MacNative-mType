// Read-only complete pinned generator/functions/wordset/weak-spot modules. GetText,
// configuration, active metadata, random draws and UI are owned adapters.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??'');
assert.ok(process.argv[2],'Reference checkout required');
assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),
  '91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
const actual=new Set(['test/words-generator','test/funbox/funbox-functions','test/wordset','test/weak-spot','test/test-words','input/helpers/fail-or-finish','input/handlers/insert-text','input/handlers/before-insert-text','input/helpers/validation','input/helpers/util']);
const config={mode:'words',words:3,language:'english',showAllLines:false,lazyMode:false,
  punctuation:false,numbers:false,britishEnglish:false};
const rawBoundProbe=process.argv[3]==='--custom-raw-bound';
const spanishRepeatProbe=process.argv[3]==='--spanish-repeat-gate';
if(rawBoundProbe||spanishRepeatProbe){actual.add('utils/strings');actual.add('test/english-punctuation');}
let ownedContentUnit=0.5;
const probeMath=Object.create(Math);probeMath.random=()=>ownedContentUnit;
const probeContext=rawBoundProbe||spanishRepeatProbe?vm.createContext({Math:probeMath,console}):undefined;
let activeNames=['backwards','binary'], functions, drawIndex=0;
let ownedIndexes=[], spacingMs=0, ownedRepeated=false;
let ownedCustom={text:[],mode:'repeat',limitMode:'word',limitValue:0,pipe:false};
let ownedActiveWordIndex=0;
let ownedSection, sectionCalls=0;
let ownedSectionQueue=[];
let ownedSectionError;
let ownedInput='',ownedCurrentInput='',ownedFinished=0;
const ownedInputEvents=[];
const toggledSources=[];
const languages={english:{name:'english',words:['ab','cd'],rightToLeft:false},
  owned:{name:'owned',words:['ef','gh'],rightToLeft:false}};
const binary=i=>(i%256).toString(2).padStart(8,'0');
const unexpected=()=>{throw Error('Unexpected adapter call outside ordering probe')};
const focusNames=['plus_zero','plus_one','plus_two','plus_three'];
const active=()=>activeNames.map(name=>({name,properties:name==='backwards'?['wordOrder:reverse']:
  focusNames.includes(name)?['toPush:'+String(focusNames.indexOf(name)+1)]:
  ['underscore_spaces','nospace'].includes(name)?['nospace']:[],functions:functions[name]??{}}));
const arrays={randomElementFromArray:words=>words[ownedIndexes.shift()??0],shuffle:words=>{
    if(['--custom-replay','--custom-fresh','--custom-fresh-focus'].includes(process.argv[3]))for(let i=words.length-1;i>0;i--){
      const j=(ownedIndexes.shift()??0)%(i+1);[words[i],words[j]]=[words[j],words[i]];
    }
    return words;
  },
  nthElementFromArray:(words,index)=>words.at(index)};
const bindings={
  'utils/strings':{removeLanguageSize:value=>value,isSpace:value=>value===' ',
    areCharactersVisuallyEqual:(a,b)=>a===b},
  'test/test-ui':{afterTestTextInput:()=>{},pendingWordData:new Map(),activeWordTop:0,activeWordHeight:10,
    getActiveWordTopAndHeightWithDifferentData:()=>({top:0,height:10})},
  'test/test-logic':{finish:()=>{ownedFinished++;},startTest:()=>{}},
  'input/input-element':{getInputElementValue:()=>({inputValue:ownedInput}),
    setInputElementValue:value=>{ownedInput=value;},
    appendToInputElementValue:value=>{ownedInput+=value;},
    replaceInputElementLastValueChar:value=>{ownedInput=ownedInput.slice(0,-1)+value;}},
  'test/events/data':{getCurrentInput:()=>ownedCurrentInput,
    logTestEvent:(_type,_now,event)=>{ownedInputEvents.push(event);}},
  'legacy-states/composition':{getComposing:()=>false},
  'input/state':{resetIncorrectShiftsInARow:()=>{},isAwaitingNextWord:()=>false},
  'legacy-states/slow-timer':{get:()=>false},
  'input/helpers/word-navigation':{goToNextWord:async()=>({lastBurst:null,increasedWordIndex:false})},
  'config/store':{Config:config},
  'config/setters':{toggleFunbox:name=>toggledSources.push(name)},
  'test/poetry':{getPoem:async()=>{sectionCalls++;if(ownedSectionError)throw ownedSectionError;return ownedSectionQueue.length?ownedSectionQueue.shift():ownedSection}},
  'test/custom-text':{getPipeDelimiter:()=>ownedCustom.pipe,getText:()=>ownedCustom.text,
    getMode:()=>ownedCustom.mode,getLimitMode:()=>ownedCustom.limitMode,getLimitValue:()=>ownedCustom.limitValue},
  'test/practise-words':{before:{mode:null}},
  'controllers/quotes-controller':{default:{}},
  'states/test':{isRepeated:()=>ownedRepeated,getCurrentQuote:()=>null,setCurrentQuote:()=>{},getSelectedQuoteId:()=>null,
    getActiveWordIndex:()=>ownedActiveWordIndex,isTestActive:()=>true,
    isTestRestarting:()=>false,isResultCalculating:()=>false,wordsHaveNewline:()=>true},
  'test/funbox/list':{
    getActiveFunboxes:active,
    getActiveFunboxesWithFunction:name=>active().filter(value=>typeof value.functions[name]==='function'),
    findSingleActiveFunboxWithFunction:name=>active().find(value=>typeof value.functions[name]==='function'),
    isFunboxActiveWithFunction:name=>active().some(value=>typeof value.functions[name]==='function'),
    isFunboxActiveWithProperty:name=>active().some(value=>value.properties.includes(name)),
  },
  'utils/arrays':arrays,
  'utils/misc':{zipfyRandomArrayIndex:()=>ownedIndexes.shift()??0},
  'utils/json-data':{getLanguage:async name=>languages[name]},
  'test/events/live-cache':{getLiveCachedMsSinceLastInputEvent:()=>spacingMs},
  'utils/generate':{getBinary:()=>binary(drawIndex++)},
  'utils/word-gen-error':{WordGenError:class extends Error {}},
};
// Erased imported type names are explicit inert exports. Unknown unused
// bindings throw if called; they are not replacement behavior implementations.
const modules=new Map();
const requested=new Map();
function resolve(id,from){
  return id.startsWith('.')?path.posix.normalize(path.posix.join(path.posix.dirname(from),id)):id;
}
for(const id of actual){
  const source=fs.readFileSync(path.join(root,'frontend/src/ts',id+'.ts'),'utf8');
  const code=stripTypeScriptTypes(source,{mode:'transform'});
  for(const match of code.matchAll(/import\s+([\s\S]*?)\s+from\s+["']([^"']+)["'];/g)){
    const target=resolve(match[2],id), names=requested.get(target)??new Set();
    const clause=match[1];
    if(!clause.startsWith('*')){
      if(!clause.startsWith('{')) names.add('default');
      const fields=clause.match(/\{([\s\S]*?)\}/)?.[1]??'';
      for(const field of fields.split(',')){
        const name=field.trim().split(/\s+as\s+/)[0];if(name)names.add(name);
      }
    }
    requested.set(target,names);
  }
  // These are type-only exports erased in the real target module. Exposing
  // inert names repairs single-file stripping, leaving all functions intact.
  const extras=id==='test/wordset'?'\nexport const FunboxWordsFrequency=undefined;':'';
  modules.set(id,new vm.SourceTextModule(code+extras,{identifier:id,
    context:probeContext}));
}
function moduleFor(id){
  if(modules.has(id))return modules.get(id);
  const values={...Object.fromEntries([...(requested.get(id)??[])].map(name=>[name,unexpected])),...bindings[id]};
  const mod=new vm.SyntheticModule(Object.keys(values),function(){
    for(const[key,value]of Object.entries(values))this.setExport(key,value);
  },{identifier:id,context:probeContext});
  modules.set(id,mod);return mod;
}
const main=moduleFor('test/words-generator');
await main.link((id,from)=>moduleFor(resolve(id,from.identifier)));
await main.evaluate();
functions=modules.get('test/funbox/funbox-functions').namespace.getFunboxFunctions();
const logicSource=fs.readFileSync(path.join(root,'frontend/src/ts/test/test-logic.ts'),'utf8');
const addStart=logicSource.indexOf('export async function addWord(): Promise<void> {');
const addEnd=logicSource.indexOf('\ntype RetrySaving = {',addStart);
assert.ok(addStart>=0&&addEnd>addStart,'Pinned complete addWord range must exist');
const addBody=stripTypeScriptTypes(logicSource.slice(addStart,addEnd),{mode:'transform'}).replace(/^export /,'');
if(spanishRepeatProbe){
  const fixtures=[],language={name:'spanish',words:['node','bay']};
  const debug=console.debug;console.debug=()=>{};
  try{
    for(const mode of ['words','time']){
      Object.assign(config,{mode:'words',words:1,language:'spanish',punctuation:true,showAllLines:false});
      activeNames=[];ownedRepeated=false;ownedIndexes=[0];ownedContentUnit=0.95;
      const first=await main.namespace.generateWords(language);
      ownedIndexes=[1];
      const second=await main.namespace.getNextWord(1,100,first.words[0].trim(),undefined);
      ownedContentUnit=0.85;
      assert.equal(await main.namespace.punctuateWord(undefined,'owned',0,100),'¡Owned');
      ownedRepeated=true;config.words=2;
      const cached=await main.namespace.generateWords(language);
      Object.assign(config,{mode,words:0,time:30});ownedIndexes=[0];ownedContentUnit=0;
      let fresh,error;
      try{fresh=(await main.namespace.getNextWord(2,100,'bay','¿Node')).word;}
      catch(caught){error=caught.message;}
      const after=await main.namespace.punctuateWord('bay','node',3,100);
      fixtures.push({mode,opening:[...first.words,second.word],cached:cached.words,fresh,error,after});
    }
  }finally{console.debug=debug;}
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
  process.stdout.write(JSON.stringify({fixtures})+'\n');process.exit(0);
}
if(rawBoundProbe){
  const words=modules.get('test/test-words').namespace.words,failures=[];
  const continuation=vm.compileFunction(addBody+'\nreturn addWord;',[
    'Config','TestWords','WordsGenerator','TestUI','getActiveFunboxes','getActiveWordIndex',
    'findSingleActiveFunboxWithFunction','showErrorNotification','toggleFunbox','restart','timerEvent',
  ])(config,modules.get('test/test-words').namespace,main.namespace,
    {addWord:()=>{},appendEmptyWordElement:unexpected},active,()=>ownedActiveWordIndex,
    name=>active().find(value=>typeof value.functions[name]==='function'),unexpected,unexpected,unexpected,
    {dispatch:value=>failures.push(value)});
  const fixtures=[],reconfigured=[],text=['ab cd','ef gh','ij kl'];
  const plans=[[],['underscore_spaces'],['backwards','underscore_spaces'],['underscore_spaces','backwards'],
    ...focusNames.map(name=>[name])];
  const debug=console.debug;console.debug=()=>{};
  try{
    for(const unit of [0.05,0.5])for(const boxes of plans)for(const punctuation of [false,true])for(const limitMode of ['word','section','time'])
      for(const limit of [0,0.5,1,1.5,2,2.5,4.5,99.5,100,100.5,101,Infinity])for(const pipe of [false,true]){
        ownedContentUnit=unit;
        Object.assign(config,{mode:'custom',language:'english',punctuation,showAllLines:false});
        activeNames=boxes.slice();ownedRepeated=false;ownedIndexes=[];
        ownedCustom={text:text.slice(),mode:'repeat',limitMode,limitValue:limit,pipe};
        const bound=main.namespace.getLimit();
        const generated=await main.namespace.generateWords({name:'english',words:['unused']});
        words.reset();generated.words.forEach((word,index)=>words.push(word,generated.sectionIndexes[index]));
        if(main.namespace.areAllWordsGenerated())words.removeCommitCharacterFromLastWord();
        const fields=Array.from({length:words.length},(_,i)=>words.get(i).textWithCommit);
        const allGenerated=main.namespace.areAllWordsGenerated();failures.length=0;let calls=0;
        const bounded=limit===0||!Number.isFinite(limit)||limitMode==='time';
        for(let i=0;i<(bounded?3:512)&&!main.namespace.areAllWordsGenerated()&&!failures.length;i++){
          ownedActiveWordIndex=words.length-1;await continuation();calls++;
        }
        assert.equal(failures.length,0);
        if(!bounded)assert.equal(main.namespace.areAllWordsGenerated(),true);
        const finalFields=Array.from({length:words.length},(_,i)=>words.get(i).textWithCommit);
        ownedRepeated=true;
        const repeated=await main.namespace.generateWords({name:'english',words:['unused']});
        words.reset();repeated.words.forEach((word,index)=>words.push(word,repeated.sectionIndexes[index]));
        if(main.namespace.areAllWordsGenerated())words.removeCommitCharacterFromLastWord();
        fixtures.push({unit,boxes,punctuation,limitMode,limit:String(limit),pipe,bound,fields,allGenerated,calls,finalFields,
          repeatedFields:Array.from({length:words.length},(_,i)=>words.get(i).textWithCommit)});
      }
    for(const unit of [0.05,0.5])for(const boxes of plans.slice(0,4))for(const punctuation of [false,true])
      for(const limitMode of ['word','section'])for(const limit of [1.5,4.5,100.5]){
        ownedContentUnit=unit;
        Object.assign(config,{mode:'words',words:2,language:'english',punctuation:false,showAllLines:false});
        activeNames=[];ownedRepeated=false;ownedIndexes=[0,1];
        const opening=await main.namespace.generateWords({name:'english',words:['old','kept']});
        assert.equal(ownedIndexes.length,0);
        Object.assign(config,{mode:'custom',punctuation});activeNames=boxes.slice();ownedRepeated=true;
        ownedCustom={text:text.slice(),mode:'repeat',limitMode,limitValue:limit,pipe:false};
        const generated=await main.namespace.generateWords({name:'english',words:['unused']});
        words.reset();generated.words.forEach((word,index)=>words.push(word,generated.sectionIndexes[index]));
        if(main.namespace.areAllWordsGenerated())words.removeCommitCharacterFromLastWord();
        reconfigured.push({unit,boxes,punctuation,limitMode,limit,opening:opening.words,
          fields:Array.from({length:words.length},(_,i)=>words.get(i).textWithCommit)});
      }
  }finally{console.debug=debug;}
  assert.equal(fixtures.length,2304);assert.equal(reconfigured.length,96);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
  await new Promise((resolve,reject)=>process.stdout.write(JSON.stringify({text,fixtures,reconfigured})+'\n',error=>error?reject(error):resolve()));
  process.exit(0);
}
if(process.argv[3]==='--section-indices') {
  const debug=console.debug;console.debug=()=>{};
  let first,repeated;
  try {
    config.mode='words';config.words=4;config.language='english';config.showAllLines=false;
    activeNames=[];ownedRepeated=false;ownedIndexes=[0,1,2,0];
    first=await main.namespace.generateWords({name:'english',words:['ab cd','ef gh','ij kl']});
    assert.equal(ownedIndexes.length,0);
    ownedRepeated=true;config.words=6;ownedIndexes=[0,0];
    repeated=await main.namespace.generateWords({name:'english',words:['ab cd','ef gh','ij kl']});
    assert.equal(ownedIndexes.length,0);
  } finally {console.debug=debug;}
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
  await new Promise((resolve,reject)=>process.stdout.write(JSON.stringify({first:first.sectionIndexes,repeated:repeated.sectionIndexes})+'\n',error=>error?reject(error):resolve()));
  process.exit(0);
}
if(['--custom-replay','--custom-fresh','--custom-fresh-focus'].includes(process.argv[3])) {
  const focused=process.argv[3]==='--custom-fresh-focus';
  const fresh=process.argv[3]!=='--custom-replay';
  if(focused){
    const catalog=fs.readFileSync(path.join(root,'packages/funbox/src/list.ts'),'utf8');
    for(const [index,name] of focusNames.entries())assert.ok(
      catalog.slice(catalog.indexOf('  '+name+': {')).split('\n  },')[0].includes('"toPush:'+String(index+1)+'"'));
  }
  const fixtures=[], words=modules.get('test/test-words').namespace.words;
  const failures=[];
  const continueWords=vm.compileFunction(addBody+'\nreturn addWord;',[
    'Config','TestWords','WordsGenerator','TestUI','getActiveFunboxes','getActiveWordIndex',
    'findSingleActiveFunboxWithFunction','showErrorNotification','toggleFunbox','restart','timerEvent',
  ])(config,modules.get('test/test-words').namespace,main.namespace,
    {addWord:()=>{},appendEmptyWordElement:unexpected},active,()=>ownedActiveWordIndex,
    name=>active().find(value=>typeof value.functions[name]==='function'),()=>{},unexpected,unexpected,
    {dispatch:value=>failures.push(value)});
  const debug=console.debug;console.debug=()=>{};
  try {
    for(const focus of focused?focusNames:[null])for(const text of [['Aa Bb','Cc','I','x2','Ω'],['Aa Bb','I']])
      for(const mode of ['repeat','random','shuffle'])for(const limitMode of ['word','time','section'])
      for(const limitValue of [0,2,4,4.5,5,101,103,Infinity])for(const pipe of [false,true]) {
        config.mode='words';config.words=3;config.language='english';config.showAllLines=false;
        activeNames=[];ownedRepeated=false;ownedIndexes=[0,1,2];
        const opening=await main.namespace.generateWords({name:'english',words:['ab','cd','ef']});
        config.mode='custom';ownedRepeated=!fresh;
        activeNames=focus?[focus]:[];
        ownedCustom={text:text.slice(),mode,limitMode,limitValue,pipe};
        const draws=Array.from({length:1000},(_,i)=>i%text.length);ownedIndexes=draws.slice();
        words.reset();let generated,error;
        try {
          generated=await main.namespace.generateWords({name:'english',words:['unused']});
          generated.words.forEach((word,index)=>words.push(word,generated.sectionIndexes[index]));
          if(main.namespace.areAllWordsGenerated())words.removeCommitCharacterFromLastWord();
        }catch(caught){error=caught.message;}
        const fields=Array.from({length:words.length},(_,i)=>words.get(i).textWithCommit);
        const allGenerated=main.namespace.areAllWordsGenerated(),drawsUsed=draws.length-ownedIndexes.length;
        const tailDraws=Array.from({length:3000},(_,i)=>i%text.length);
        if(mode==='random'&&limitMode==='section'&&limitValue>100&&!error){
          const last=words.get(words.length-1).text;
          const rank=text.findIndex(section=>section.split(' ').includes(last));
          assert.ok(rank>=0);
          tailDraws.unshift(...Array(16).fill(rank));
        }
        ownedIndexes=tailDraws.slice();
        failures.length=0;
        let continuationCalls=0;
        if(!error&&limitMode!=='time')for(let i=0;i<(Number.isFinite(limitValue)&&limitValue>0?256:3)&&!main.namespace.areAllWordsGenerated()&&!failures.length;i++){
          ownedActiveWordIndex=words.length-1;await continueWords();continuationCalls++;
        }
        if(!error&&limitMode!=='time'&&!failures.length&&Number.isFinite(limitValue)&&limitValue>0)assert.equal(main.namespace.areAllWordsGenerated(),true);
        const fixture={focus,text,mode,limitMode,limitValue:String(limitValue),pipe,opening:opening.words,
          generated:generated?.words,sectionIndexes:generated?.sectionIndexes,
          fields,finalFields:Array.from({length:words.length},(_,i)=>words.get(i).textWithCommit),
          finalSectionIndexes:Array.from({length:words.length},(_,i)=>words.get(i).sectionIndex),
          currentSection:Array.from(main.namespace.currentSection),sectionIndex:main.namespace.sectionIndex,
          allGenerated,drawsUsed,finalDrawsUsed:drawsUsed+tailDraws.length-ownedIndexes.length,
          tailRanks:tailDraws.slice(0,tailDraws.length-ownedIndexes.length),
          continuationFailed:failures.length>0,continuationCalls,error};
        if(fresh){
          ownedRepeated=true;ownedIndexes=draws.slice();words.reset();
          const repeated=await main.namespace.generateWords({name:'english',words:['unused']});
          repeated.words.forEach((word,index)=>words.push(word,repeated.sectionIndexes[index]));
          if(main.namespace.areAllWordsGenerated())words.removeCommitCharacterFromLastWord();
          fixture.repeatedFields=Array.from({length:words.length},(_,i)=>words.get(i).textWithCommit);
          fixture.repeatedSectionIndexes=repeated.sectionIndexes;
          fixture.repeatedAllGenerated=main.namespace.areAllWordsGenerated();
          assert.equal(ownedIndexes.length,draws.length,'Same-settings repeat must use cached targets');
        }
        fixtures.push(fixture);
      }
  } finally {console.debug=debug;}
  assert.equal(fixtures.length,focused?1152:288);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
  await new Promise((resolve,reject)=>process.stdout.write(JSON.stringify({fixtures})+'\n',error=>error?reject(error):resolve()));
  process.exit(0);
}
if(['--replay-framing','--custom-live-framing'].includes(process.argv[3])) {
  const admission=moduleFor('input/handlers/before-insert-text');
  await admission.link((id,from)=>moduleFor(resolve(id,from.identifier)));
  await admission.evaluate();
  const finish=moduleFor('input/helpers/fail-or-finish');
  await finish.link((id,from)=>moduleFor(resolve(id,from.identifier)));
  await finish.evaluate();
  const fixtures=[], words=modules.get('test/test-words').namespace.words;
  if(process.argv[3]==='--custom-live-framing'){
    const debug=console.debug;console.debug=()=>{};
    let result;
    try{
      config.mode='custom';config.language='english';ownedRepeated=false;activeNames=[];
      Object.assign(config,{difficulty:'normal',deleteOnError:'off',stopOnError:'off',strictSpace:false});
      ownedCustom={text:['aa bb cc dd ee ff gg hh ii','jj'],mode:'repeat',limitMode:'word',limitValue:2,pipe:false};
      const opening=await main.namespace.generateWords({name:'english',words:['unused']});
      words.reset();opening.words.forEach((word,index)=>words.push(word,opening.sectionIndexes[index]));
      words.removeCommitCharacterFromLastWord();
      ownedCustom={text:['replacement'],mode:'repeat',limitMode:'word',limitValue:7.5,pipe:false};
      const continuation=vm.compileFunction(addBody+'\nreturn addWord;',[
        'Config','TestWords','WordsGenerator','TestUI','getActiveFunboxes','getActiveWordIndex',
        'findSingleActiveFunboxWithFunction','showErrorNotification','toggleFunbox','restart','timerEvent',
      ])(config,modules.get('test/test-words').namespace,main.namespace,
        {addWord:()=>{},appendEmptyWordElement:unexpected},active,()=>ownedActiveWordIndex,
        name=>active().find(value=>typeof value.functions[name]==='function'),unexpected,unexpected,unexpected,
        {dispatch:unexpected});
      for(let i=0;i<10&&!main.namespace.areAllWordsGenerated();i++)await continuation();
      assert.equal(main.namespace.areAllWordsGenerated(),true);
      const fields=Array.from({length:words.length},(_,i)=>words.get(i).textWithCommit);
      const tape=fields.map((field,index)=>index===fields.length-1||field.endsWith(' ')?field:field+' ').join('');
      ownedActiveWordIndex=0;ownedInput='';ownedCurrentInput='';const events=[];
      for(const data of tape.split('')){
        const blocked=admission.namespace.onBeforeInsertText(data);assert.equal(blocked,false);
        const targetWord=fields[ownedActiveWordIndex],options={data,inputValue:ownedInput,targetWord};
        const commit=modules.get('input/helpers/util').namespace.getCommitCharacterType(options);
        const validation=modules.get('input/helpers/validation').namespace;
        const correct=validation.isCharCorrect({...options,correctShiftUsed:null});
        const advances=validation.shouldGoToNextWord({...options,commitCharacterType:commit});
        events.push({data,correct,advances});ownedInput+=data;ownedCurrentInput=ownedInput;
        if(advances){ownedActiveWordIndex++;ownedInput='';ownedCurrentInput='';}
      }
      assert.equal(events.filter(event=>!event.correct).length,1,'Former final field keeps its missing commit');
      result={fields,tape,events};
    }finally{console.debug=debug;}
    assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
    process.stdout.write(JSON.stringify(result)+'\n');process.exit(0);
  }
  const debug=console.debug;console.debug=()=>{};
  try {
    for(const pool of [['ab','cd','ef'],['é','界','🙂']])for(const oldNoSpace of [false,true])for(const newNoSpace of [false,true]) {
      config.language='english';config.words=3;config.showAllLines=false;
      ownedRepeated=false;activeNames=oldNoSpace?['nospace']:[];ownedIndexes=[0,1,2];
      const opening=await main.namespace.generateWords({name:'english',words:pool.slice()});
      assert.equal(ownedIndexes.length,0);
      ownedRepeated=true;activeNames=newNoSpace?['nospace']:[];config.words=5;ownedIndexes=[0,1];
      const generated=await main.namespace.generateWords({name:'english',words:pool.slice()});
      assert.deepEqual(generated.words.slice(0,3),opening.words,'Cached commit characters are not re-appended under new settings');
      assert.deepEqual(generated.words.slice(3),pool.slice(0,2).map(word=>word+(newNoSpace?'':' ')));
      assert.equal(ownedIndexes.length,0,'Exactly two fresh draws after the three cached fields');
      words.reset();generated.words.forEach((word,index)=>words.push(word,index));
      words.removeCommitCharacterFromLastWord();
      const fields=Array.from({length:words.length},(_,i)=>words.get(i).textWithCommit);
      Object.assign(config,{difficulty:'normal',deleteOnError:'off',stopOnError:'off',strictSpace:false});
      ownedActiveWordIndex=0;ownedInput='';ownedCurrentInput='';
      // Physical input and navigation are owned. Admission, commit classification,
      // correctness and permission to advance execute the complete source helpers.
      const tape=(newNoSpace?' ':'')+fields.map((field,index)=>{
        if(index===fields.length-1)return field;
        if(newNoSpace)return field.endsWith(' ')?field.slice(0,-1)+'x':field;
        return field.endsWith(' ')?field:field+' ';
      }).join('');
      const events=[];let completed=false;
      for(const data of tape.split('')) {
        const blocked=modules.get('input/handlers/before-insert-text').namespace.onBeforeInsertText(data);
        if(blocked){events.push({data,blocked});continue;}
        const targetWord=fields[ownedActiveWordIndex];
        const options={data,inputValue:ownedInput,targetWord};
        const commit=modules.get('input/helpers/util').namespace.getCommitCharacterType(options);
        const validation=modules.get('input/helpers/validation').namespace;
        const correct=validation.isCharCorrect({...options,correctShiftUsed:null});
        const advances=validation.shouldGoToNextWord({...options,commitCharacterType:commit});
        completed=finish.namespace.checkIfFinished({goingToNextWord:advances,
          testInputWithData:ownedInput+data,currentWord:targetWord,
          allWordsTyped:ownedActiveWordIndex===fields.length-1,
          allWordsGenerated:main.namespace.areAllWordsGenerated()});
        events.push({data,blocked,correct,advances,completed});
        ownedInput+=data;ownedCurrentInput=ownedInput;
        if(advances){ownedActiveWordIndex++;ownedInput='';ownedCurrentInput='';}
      }
      assert.equal(events.filter(event=>!event.blocked&&!event.correct).length,
        oldNoSpace===newNoSpace?0:3);
      assert.equal(completed,true);
      activeNames=oldNoSpace?['nospace']:[];config.words=7;ownedIndexes=[2,0];
      const returned=await main.namespace.generateWords({name:'english',words:pool.slice()});
      assert.deepEqual(returned.words.slice(0,5),generated.words);
      assert.deepEqual(returned.words.slice(5),[pool[2],pool[0]].map(word=>word+(oldNoSpace?'':' ')));
      assert.equal(ownedIndexes.length,0);
      words.reset();returned.words.forEach((word,index)=>words.push(word,index));
      words.removeCommitCharacterFromLastWord();
      fixtures.push({pool,oldNoSpace,newNoSpace,opening:opening.words,generated:generated.words,
        fields,tape,events,returnedFields:Array.from({length:words.length},(_,i)=>words.get(i).textWithCommit)});
    }
  } finally {console.debug=debug;}
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
  process.stdout.write(JSON.stringify({fixtures})+'\n');
  process.exit(0);
}
// Run the replay fixture first so the real generator's retained results begin
// at index zero. Only the external repeated flag and rank draws are adapters.
config.language='code_swift';activeNames=[];ownedIndexes=[0,2,1];
const codeOpening=await main.namespace.generateWords({name:'code_swift',words:['ab','cd','ef']});
assert.deepEqual(codeOpening.words,['ab ','ef ','cd ']);
ownedRepeated=true;ownedIndexes=[2,2,2];
const codeRepeated=await main.namespace.generateWords({name:'code_swift',words:['other','owned','pool']});
assert.deepEqual(codeRepeated.words,codeOpening.words);
assert.deepEqual(ownedIndexes,[2,2,2],'Repeat uses actual saved targets without rank draws');
ownedRepeated=false;ownedIndexes=[];config.language='english';
for(const [limit,showAll,underscore] of [[3,false,false],[3,false,true],[101,false,true],[101,true,true],
  [100001,true,true]]){
  config.words=limit;config.showAllLines=showAll;drawIndex=0;
  activeNames=['backwards','binary',...(underscore?['underscore_spaces']:[])];
  const pool=['oak','elm','ash'];
  const savedDebug=console.debug;
  let generated;
  try {
    // The large owned-word boundary needs assertions, not per-word traces.
    if(limit>100000) console.debug=()=>{};
    generated=await main.namespace.generateWords({name:'english',words:pool});
  } finally { console.debug=savedDebug; }
  assert.deepEqual(pool,['ash','elm','oak'],'Only the source candidate pool reverses');
  const bound=showAll?limit:Math.min(100,limit);
  const expected=Array.from({length:bound},(_,i)=>binary(i).split('').reverse().join('')+
    (underscore?(i===bound-1?'':'_'):' '));
  assert.deepEqual(generated.words,expected);
  if(limit>bound){
    const next=await main.namespace.getNextWord(bound,100,expected.at(-1),expected.at(-2));
    assert.equal(next.word,binary(bound).split('').reverse().join('')+'_');
  }
}
console.log('5 generated-backwards ordering fixtures passed, including the 100001-word whole preview (GetText/config/metadata/random adapters).');
for(const backwards of [false,true]){
  for(const zipf of [false,true]){
    config.words=3;config.showAllLines=false;
    activeNames=[...(backwards?['backwards']:[]),...(zipf?['zipf']:[])];
    ownedIndexes=[0,2,1];
    const pool=['ab','cd','ef'];
    const generated=await main.namespace.generateWords({name:'english',words:pool});
    assert.deepEqual(pool,backwards?['ef','cd','ab']:['ab','cd','ef']);
    assert.deepEqual(generated.words,backwards?['fe ','ba ','dc ']:['ab ','ef ','cd ']);
    assert.equal(ownedIndexes.length,0);
  }
}
const weakspot=modules.get('test/weak-spot').namespace;
spacingMs=1000;weakspot.updateScore('a',true);
spacingMs=800;weakspot.updateScore('b',true);
ownedIndexes=[0,...Array(19).fill(1)];
const wordset=modules.get('test/wordset').namespace;
assert.equal(weakspot.getWord(new wordset.Wordset(['aaax','bb'])),'aaax');
assert.equal(ownedIndexes.length,0,'Exactly twenty candidates, unknown letters excluded from the mean');
// Fresh keys keep these fixtures independent of the learned a/b scores above.
for(const [character,milliseconds] of [['z',0],['y',1000],['v',750]]){
  spacingMs=milliseconds;weakspot.updateScore(character,true);
}
ownedIndexes=[0,...Array(19).fill(1)];
assert.equal(weakspot.getWord(new wordset.Wordset(['zy','v'])),'v',
  'A learned zero stays in the average; an unknown character does not');
assert.equal(ownedIndexes.length,0);
for(const [character,candidate] of [['e','e\u0301'],['🙂','🙂x']]){
  spacingMs=1000;weakspot.updateScore(character,true);
  ownedIndexes=[0,...Array(19).fill(1)];
  assert.equal(weakspot.getWord(new wordset.Wordset([candidate,'bb'])),candidate,
    'Source for-of scores known code points inside a combining or astral word');
  assert.equal(ownedIndexes.length,0);
}
config.words=3;config.customPolyglot=['english','owned'];
activeNames=['backwards','polyglot'];ownedIndexes=[0,3,1];
const primary=['oak','elm','ash'];
const polyglot=await main.namespace.generateWords({name:'english',words:primary});
assert.deepEqual(primary,['ash','elm','oak']);
assert.deepEqual(polyglot.words,['ba ','hg ','dc '],'Polyglot builds a fresh combined pool, not the reversed primary list');
assert.equal(ownedIndexes.length,0);
console.log('9 ordinary/Zipf/weakspot/polyglot fixtures passed (4 complete actual modules; deterministic rank/shuffle/spacing/language adapters, no source RNG/distribution, physical input, corpus or browser parity claim).');
config.language='code_swift';config.showAllLines=false;
for(const zipf of [false,true]){
  config.words=3;activeNames=['backwards',...(zipf?['zipf']:[])];ownedIndexes=[0,2,1];
  const pool=['ab','cd','ef'];
  const result=await main.namespace.generateWords({name:'code_swift',words:pool});
  assert.deepEqual(pool,['ef','cd','ab']);
  assert.deepEqual(result.words,['fe ','ba ','dc ']);
  assert.equal(ownedIndexes.length,0);
}
for(const [pool,indexes,expected] of [
  [['value2','func'],[0,1],['func ']],
  [['foo()','Foundation','v٢'],[0,1,2],['foo() ','Foundation ','v٢ ']],
  [['aa','AA'],[0,1,1],['aa ','AA ']],
  [['value2'],Array(101).fill(0),['value2 ']],
  [['I','Foundation'],[0,1],['Foundation ']],
]){
  config.words=expected.length;activeNames=[];ownedIndexes=[...indexes];
  const result=await main.namespace.generateWords({name:'code_swift',words:pool});
  assert.deepEqual(result.words,expected);
  assert.equal(ownedIndexes.length,0);
}
config.words=1;activeNames=['weakspot'];ownedIndexes=[1,0,...Array(19).fill(1)];
const codeWeak=await main.namespace.generateWords({name:'code_swift',words:['aaax','bb']});
assert.deepEqual(codeWeak.words,['aaax ']);assert.equal(ownedIndexes.length,0);
console.log('10 code-pool fixtures passed (normal/reverse/Zipf plumbing, real cached repeat, candidate gates and weakspot; ranks, source input words, repeated flag and runtime boundaries are owned adapters, no code corpus, source RNG, punctuation decoration, number injection or device equivalence claim).');
// Provider responses are authored adapters, not HTTP or parser evidence.
// Execute the real section selection and word admission: a successful empty
// section must not be conflated with false/undefined provider failure.
config.language='english';config.words=1;activeNames=['poetry'];ownedRepeated=false;
for(const [response,message,disabled] of [
  [{words:[]},'Random word is empty',false],
  [false,'Failed to pull section',true],
  [undefined,'Failed to pull section',true],
]) {
  ownedSection=response;sectionCalls=0;toggledSources.length=0;
  await assert.rejects(main.namespace.generateWords({name:'english',words:['owned']}),error=>{
    assert.equal(error.message,message);
    assert.equal(error instanceof bindings['utils/word-gen-error'].WordGenError,!disabled);
    return true;
  });
  assert.equal(sectionCalls,1,'Neither failure path silently refetches');
  assert.deepEqual(toggledSources,disabled?['poetry']:[]);
}
ownedSection={words:['harbor']};sectionCalls=0;toggledSources.length=0;
assert.deepEqual((await main.namespace.generateWords({name:'english',words:['owned']})).words,['harbor ']);
assert.equal(sectionCalls,1);assert.deepEqual(toggledSources,[]);
console.log('4 pinned section-admission cases passed (actual generator and funbox functions; authored provider responses distinguish empty generation failure from requested source-disable on fetch failure; toggle recorder is not setter-admission evidence; no parser/HTTP/UI/recovery equivalence claim).');
// Execute the complete actual addWord function, not a paraphrase of its branch
// conditions. Its surrounding module/startup is deliberately outside this
// probe. The exact pinned source range is read only and remains in memory.
const testWords=modules.get('test/test-words').namespace;
let restarts=0;
const failures=[],notices=[],displayed=[];
const addWord=vm.compileFunction(addBody+'\nreturn addWord;',[
  'Config','TestWords','WordsGenerator','TestUI','getActiveFunboxes','getActiveWordIndex',
  'findSingleActiveFunboxWithFunction','showErrorNotification','toggleFunbox','restart','timerEvent',
])(config,testWords,main.namespace,
  {addWord:word=>displayed.push(word),appendEmptyWordElement:unexpected},active,()=>ownedActiveWordIndex,
  name=>active().find(value=>typeof value.functions[name]==='function'),
  (...args)=>notices.push(args),bindings['config/setters'].toggleFunbox,
  async()=>{restarts++},{dispatch:value=>failures.push(value)});
config.words=300;
for(const fixture of [
  {name:'empty with retained generator tail',tail:['retained'],responses:[{words:[]}],calls:1,added:['retained'],fails:0,restarts:0,disabled:false},
  {name:'empty then valid generator section',tail:[],responses:[{words:[]},{words:['fresh']}],calls:2,added:['fresh'],fails:0,restarts:0,disabled:false},
  {name:'empty side before visible exhaustion with empty generator',published:151,active:134,tail:[],responses:[{words:[]},{words:['fresh']}],calls:2,added:['fresh'],fails:0,restarts:0,disabled:false},
  {name:'empty then empty generator section',tail:[],responses:[{words:[]},{words:[]}],calls:2,added:[],fails:1,restarts:0,disabled:false},
  {name:'false prefetch with retained tail',tail:['retained'],responses:[false],calls:1,added:[],fails:0,restarts:1,disabled:true},
  {name:'undefined prefetch with retained tail',tail:['retained'],responses:[undefined],calls:1,added:[],fails:0,restarts:0,disabled:false},
  {name:'valid prefetch still consumes generator tail',tail:['retained'],responses:[{words:['first','second']}],calls:1,added:['first','second','retained'],fails:0,restarts:0,disabled:false},
]){
  const published=fixture.published??1;
  ownedActiveWordIndex=fixture.active??0;
  testWords.words.reset();
  for(let i=0;i<published;i++)testWords.words.push('opening ',i);
  main.namespace.currentSection.splice(0,main.namespace.currentSection.length,...fixture.tail);
  ownedSectionQueue=[...fixture.responses];ownedSection=undefined;
  sectionCalls=0;restarts=0;toggledSources.length=0;
  failures.length=0;notices.length=0;displayed.length=0;
  await addWord();
  assert.equal(sectionCalls,fixture.calls,fixture.name);
  assert.deepEqual(testWords.words.get().slice(published).map(word=>word.text),fixture.added,fixture.name);
  assert.deepEqual(displayed,fixture.added,fixture.name);
  assert.equal(failures.length,fixture.fails,fixture.name);
  if(fixture.fails) assert.deepEqual(failures,[{key:'fail',value:'word generation error'}]);
  assert.equal(restarts,fixture.restarts,fixture.name);
  assert.deepEqual(toggledSources,fixture.disabled?['poetry']:[],fixture.name);
  assert.equal(notices.length,fixture.fails+fixture.restarts,fixture.name);
  assert.equal(ownedSectionQueue.length,0,fixture.name);
}
ownedActiveWordIndex=0;
console.log('7 pinned complete-addWord cases passed with actual generator/functions/word storage (owned provider, UI, active index, notification and timer boundaries; no full test-logic module, HTTP, DOM or native recovery equivalence claim).');
// A rejected provider Promise is not a false return. Use an owned rejecting
// adapter to isolate propagation through the complete real caller; this does
// not claim that poetry itself rejects, or execute MediaWiki transport.
for (const published of [1, 100]) {
  config.words=300;ownedActiveWordIndex=0;
  testWords.words.reset();
  for(let i=0;i<published;i++)testWords.words.push(`owned${i} `,0);
  const tail=published===1?['retained']:[];
  main.namespace.currentSection.splice(0,main.namespace.currentSection.length,...tail);
  ownedSectionQueue=[];ownedSectionError=new Error('Owned provider rejection');
  sectionCalls=0;restarts=0;toggledSources.length=0;
  failures.length=0;notices.length=0;displayed.length=0;
  if(published===1) await assert.rejects(addWord(),error=>error===ownedSectionError);
  else await addWord();
  assert.equal(sectionCalls,1);
  assert.equal(testWords.words.length,published);
  assert.deepEqual(Array.from(main.namespace.currentSection),tail);
  assert.deepEqual(displayed,[]);
  assert.deepEqual(toggledSources,[],'Rejection does not reach the false/undefined toggle branch');
  assert.equal(restarts,0);
  assert.deepEqual(failures,published===1?[]:[{key:'fail',value:'word generation error'}]);
  assert.equal(notices.length,published===1?0:1);
  ownedSectionError=undefined;
}
console.log('2 pinned complete-addWord rejection cases passed (side pull propagates rejection without timer failure; generator catches rejection and fails without source toggle; owned rejecting provider, not MediaWiki transport or browser presentation evidence).');
// Authored storage/cursor states isolate the side-pull boundary. They do not
// establish that every state is reachable through real keyboard navigation.
for (const fixture of [
  {name:'twenty published fields remain', active:80, limit:300, calls:0, added:['retained0']},
  {name:'nineteen published fields remain with cached tail', active:81, limit:300,
    calls:1, added:['fresh', 'later', 'retained0']},
  {name:'cached tail reaches finite budget but published fields do not', active:81, limit:105,
    calls:1, added:['fresh', 'later', 'retained0']},
]) {
  config.mode='words';config.words=fixture.limit;config.language='english';
  activeNames=['poetry'];ownedRepeated=false;ownedSectionError=undefined;
  ownedSection={words:['setup']};ownedSectionQueue=[];
  await main.namespace.generateWords({name:'english',words:['owned']});
  testWords.words.reset();
  for(let i=0;i<100;i++)testWords.words.push(`owned${i} `,0);
  main.namespace.currentSection.splice(0,main.namespace.currentSection.length,
    ...Array.from({length:5},(_,i)=>`retained${i}`));
  ownedActiveWordIndex=fixture.active;
  ownedSection={words:['fresh','later']};ownedSectionQueue=[];
  sectionCalls=0;restarts=0;failures.length=0;notices.length=0;toggledSources.length=0;displayed.length=0;
  await addWord();
  assert.equal(sectionCalls,fixture.calls,fixture.name);
  assert.deepEqual(testWords.words.get().slice(100).map(word=>word.text),fixture.added,fixture.name);
  assert.deepEqual(Array.from(main.namespace.currentSection),['retained1','retained2','retained3','retained4']);
  assert.deepEqual(failures,[]);assert.deepEqual(toggledSources,[]);assert.equal(restarts,0);
  console.log(`PASS side threshold: ${fixture.name}`);
}
console.log('3 side-threshold cases passed: published count controls demand and finite completion; cached ownership alone does not suppress a side pull. Authored state, no navigation/HTTP reachability claim.');
config.words=103;
testWords.words.reset();
for(let i=0;i<100;i++)testWords.words.push(`owned${i} `,0);
main.namespace.currentSection.splice(0,main.namespace.currentSection.length,'north\nsouth','e\u0301','tail');
sectionCalls=0;displayed.length=0;failures.length=0;toggledSources.length=0;
for(let i=0;i<3;i++){
  // word-navigation calls addWord before increasing the active index.
  ownedActiveWordIndex=i;
  await addWord();
  assert.equal(testWords.words.length,101+i);
  assert.equal(main.namespace.currentSection.length,2-i);
  assert.equal(sectionCalls,0,'A retained generator tail supplies one new field per forward transition');
}
assert.deepEqual(displayed,['north\nsouth','e\u0301','tail']);
assert.equal(testWords.words.get(102).commit,'','Final finite target has no commit');
assert.deepEqual(failures,[]);assert.deepEqual(toggledSources,[]);
ownedActiveWordIndex=3;
await addWord();
assert.equal(testWords.words.length,103);assert.equal(sectionCalls,0);
console.log('Pinned sequential forward-tail case passed (100 published fields plus 3 retained fields; actual addWord/generator/storage, owned forward index; no navigation or physical-input execution claim).');
// Generator demand is distinct from the <20-field side pull. A full visible
// window can still require the generator to acquire its next retained section.
config.words=300;ownedActiveWordIndex=0;
for(const fixture of [
  {name:'empty generator with full visible window',published:100,response:{words:['fresh','later']},calls:1,added:['fresh'],tail:['later'],fails:0,disabled:false},
  {name:'empty generator with inclusive future bound',published:101,response:{words:['fresh','later']},calls:1,added:['fresh'],tail:['later'],fails:0,disabled:false},
  {name:'future window beyond bound',published:102,response:{words:['unused']},calls:0,added:[],tail:[],fails:0,disabled:false},
  {name:'successful empty generator pull',published:100,response:{words:[]},calls:1,added:[],tail:[],fails:1,disabled:false},
  {name:'false generator pull',published:100,response:false,calls:1,added:[],tail:[],fails:1,disabled:true},
  {name:'undefined generator pull',published:100,response:undefined,calls:1,added:[],tail:[],fails:1,disabled:true},
]){
  testWords.words.reset();
  for(let i=0;i<fixture.published;i++)testWords.words.push(`owned${i} `,0);
  main.namespace.currentSection.splice(0,main.namespace.currentSection.length);
  ownedSection=fixture.response;ownedSectionQueue=[];sectionCalls=0;restarts=0;
  displayed.length=0;failures.length=0;notices.length=0;toggledSources.length=0;
  await addWord();
  assert.equal(sectionCalls,fixture.calls,fixture.name);
  assert.deepEqual(displayed,fixture.added,fixture.name);
  assert.deepEqual(testWords.words.get().slice(fixture.published).map(word=>word.text),fixture.added,fixture.name);
  assert.deepEqual([...main.namespace.currentSection],fixture.tail,fixture.name);
  assert.deepEqual(failures,fixture.fails?[{key:'fail',value:'word generation error'}]:[],fixture.name);
  assert.deepEqual(toggledSources,fixture.disabled?['poetry']:[],fixture.name);
  assert.equal(notices.length,fixture.fails,fixture.name);
  assert.equal(restarts,0,fixture.name);
}
console.log('6 pinned generator-demand cases passed (100/101/102 published fields; real addWord/generator/storage; authored provider and UI boundaries, toggle recorder is not actual setter admission; no HTTP/navigation/device equivalence claim).');
testWords.words.reset();
for(let i=0;i<100;i++)testWords.words.push(`owned${i} `,0);
main.namespace.currentSection.splice(0,main.namespace.currentSection.length,'lastRetained');
ownedSection={words:['fresh','later']};ownedSectionQueue=[];sectionCalls=0;displayed.length=0;
ownedActiveWordIndex=0;
await addWord();
assert.equal(sectionCalls,0,'Consuming the last retained field does not itself pull a new section');
assert.equal(main.namespace.currentSection.length,0);
ownedActiveWordIndex=1;
await addWord();
assert.equal(sectionCalls,1,'The next forward action sees an already-empty pool and pulls');
assert.deepEqual(displayed,['lastRetained','fresh']);
assert.deepEqual([...main.namespace.currentSection],['later']);
console.log('Pinned last-retained-field transition passed (no pull while consuming the tail; next forward action pulls exactly once; owned active-index boundary, not complete navigation execution).');
// The earlier recorder boundaries prove requests to toggle/restart, not that
// those requests are admitted. Execute both complete pinned functions on the
// active no_quit path; unknown downstream dependencies remain unresolved so
// crossing either guard fails instead of inventing successful mutation.
const settersSource=fs.readFileSync(path.join(root,'frontend/src/ts/config/setters.ts'),'utf8');
const toggleStart=settersSource.indexOf('export function toggleFunbox(');
assert.ok(toggleStart>=0);
const toggleBody=stripTypeScriptTypes(settersSource.slice(toggleStart),{mode:'transform'}).replace(/^export /,'');
const restartStart=logicSource.indexOf('export async function restart(');
const restartEnd=logicSource.indexOf('\nlet lastInitError:',restartStart);
assert.ok(restartStart>=0&&restartEnd>restartStart);
const restartBody=stripTypeScriptTypes(logicSource.slice(restartStart,restartEnd),{mode:'transform'}).replace(/^export /,'');
const guardNotices=[];
config.funbox=['poetry','no_quit'];config.words=50;ownedActiveWordIndex=0;
const activeToggle=vm.compileFunction(toggleBody+'\nreturn toggleFunbox;',
  ['Config','isTestActive','showNoticeNotification'])(config,()=>true,(...args)=>guardNotices.push(args));
const activeRestart=vm.compileFunction(restartBody+'\nreturn restart;',
  ['isTestActive','isFunboxActive','showNoticeNotification'])(()=>true,
  name=>config.funbox.includes(name),(...args)=>guardNotices.push(args));
const guardedAddWord=vm.compileFunction(addBody+'\nreturn addWord;',[
  'Config','TestWords','WordsGenerator','TestUI','getActiveFunboxes','getActiveWordIndex',
  'findSingleActiveFunboxWithFunction','showErrorNotification','toggleFunbox','restart','timerEvent',
])(config,testWords,main.namespace,
  {addWord:word=>displayed.push(word),appendEmptyWordElement:unexpected},active,()=>ownedActiveWordIndex,
  name=>active().find(value=>typeof value.functions[name]==='function'),
  (...args)=>notices.push(args),activeToggle,activeRestart,{dispatch:value=>failures.push(value)});
testWords.words.reset();testWords.words.push('opening ',0);
main.namespace.currentSection.splice(0,main.namespace.currentSection.length,'retained');
ownedSection=false;ownedSectionQueue=[];sectionCalls=0;
notices.length=0;failures.length=0;displayed.length=0;
await guardedAddWord();
assert.equal(sectionCalls,1);
assert.deepEqual(config.funbox,['poetry','no_quit'],'Actual active NoQuit setter keeps the source enabled');
assert.equal(guardNotices.length,2,'Both toggle and restart reject the active NoQuit attempt');
assert.equal(notices.length,1,'The section-fetch error is still reported');
assert.deepEqual(failures,[],'False prefetch does not dispatch a generation failure');
assert.deepEqual(displayed,[]);assert.equal(testWords.words.length,1);
assert.deepEqual([...main.namespace.currentSection],['retained']);
ownedSection={words:['first','second']};
await guardedAddWord();
assert.equal(sectionCalls,2);
assert.deepEqual(displayed,['first','second','retained'],
  'A later valid response can append its section and the preserved generator tail');
assert.equal(testWords.words.length,4);assert.deepEqual(failures,[]);
assert.deepEqual(config.funbox,['poetry','no_quit']);assert.equal(guardNotices.length,2);
console.log('Pinned active-NoQuit false-prefetch case passed (complete actual addWord/toggleFunbox/restart functions, real generator/storage; owned active/config/notification boundaries; no full event bus, UI or backend execution claim).');

// Compose a real generated opening, an authored near-tail cursor and repeat.
// Direct side publication does not pass through getNextWord's saved history.
config.mode='words';config.words=105;config.showAllLines=false;config.language='english';
activeNames=['poetry'];ownedRepeated=false;ownedSectionError=undefined;
ownedSection={words:Array.from({length:105},(_,i)=>`opening${i}`)};
ownedSectionQueue=[];sectionCalls=0;
const beforeSideRepeat=await main.namespace.generateWords({name:'english',words:['owned']});
assert.equal(beforeSideRepeat.words.length,100);
assert.deepEqual(Array.from(main.namespace.currentSection),
  Array.from({length:5},(_,i)=>`opening${100+i}`));
testWords.words.reset();
for(const word of beforeSideRepeat.words)testWords.words.push(word,0);
ownedActiveWordIndex=81;ownedSection={words:['sideFirst','sideSecond']};
displayed.length=0;failures.length=0;notices.length=0;toggledSources.length=0;
await addWord();
assert.deepEqual(testWords.words.get().slice(100).map(word=>word.text),
  ['sideFirst','sideSecond','opening100']);
assert.equal(sectionCalls,2);
ownedRepeated=true;ownedSection={words:['fallbackFirst','fallbackSecond']};sectionCalls=0;
const afterSideRepeat=await main.namespace.generateWords({name:'english',words:['different']});
assert.deepEqual(afterSideRepeat.words,beforeSideRepeat.words);
assert.equal(sectionCalls,0,'Saved opening avoids another provider call');
const savedTail=await main.namespace.getNextWord(100,100,afterSideRepeat.words.at(-1),afterSideRepeat.words.at(-2));
assert.equal(savedTail.word,'opening100 ');
assert.equal(sectionCalls,0,'Only the generator-consumed old tail was saved');
const missingHistory=await main.namespace.getNextWord(101,100,savedTail.word,afterSideRepeat.words.at(-1));
assert.equal(missingHistory.word,'fallbackFirst ');
assert.equal(sectionCalls,1,'Missing finite history below the limit resumes actual section generation');
await assert.rejects(main.namespace.getNextWord(105,100,missingHistory.word,savedTail.word),
  /Repeated word is undefined/);
assert.equal(sectionCalls,1,'Missing history at the finite limit must not fetch');
ownedRepeated=false;
console.log('Pinned side-publication/repeat composition passed: direct side fields bypass saved generator history, consumed old tail replays, missing in-budget history fetches, out-of-budget history rejects. Owned provider/cursor; no real navigation, HTTP or native-equivalence claim.');

for (const fixture of [
  {name:'side section bypasses backwards alteration', modifiers:['poetry','backwards'],
    section:['fresh','later'], expected:['fresh','later','0deniater']},
  {name:'side section caps its own size rather than remaining global budget', modifiers:['poetry'],
    section:Array.from({length:10},(_,i)=>`side${i}`),
    expected:[...Array.from({length:10},(_,i)=>`side${i}`),'retained0']},
]) {
  config.mode='words';config.words=105;config.language='english';config.showAllLines=false;
  activeNames=fixture.modifiers;ownedRepeated=false;ownedSectionError=undefined;
  ownedSection={words:['setup']};ownedSectionQueue=[];
  await main.namespace.generateWords({name:'english',words:['owned']});
  testWords.words.reset();
  for(let i=0;i<100;i++)testWords.words.push(`owned${i} `,0);
  main.namespace.currentSection.splice(0,main.namespace.currentSection.length,
    ...Array.from({length:5},(_,i)=>`retained${i}`));
  ownedActiveWordIndex=81;ownedSection={words:fixture.section};sectionCalls=0;
  failures.length=0;notices.length=0;displayed.length=0;toggledSources.length=0;
  await addWord();
  assert.equal(sectionCalls,1);
  assert.deepEqual(testWords.words.get().slice(100).map(word=>word.text),fixture.expected,fixture.name);
  assert.equal(testWords.words.length,100+fixture.expected.length);
  assert.deepEqual(Array.from(main.namespace.currentSection),['retained1','retained2','retained3','retained4']);
  assert.deepEqual(failures,[]);assert.deepEqual(toggledSources,[]);
  console.log(`PASS side publication contract: ${fixture.name}`);
}
console.log('2 side-publication contracts passed with complete actual caller and generator: raw side words versus altered generator tail, and finite published oversupply. Authored cursor/provider, no input-completion or navigation reachability claim.');
const finishModule=modules.get('input/helpers/fail-or-finish');
await finishModule.link((id,from)=>moduleFor(resolve(id,from.identifier)));
await finishModule.evaluate();
config.quickEnd=false;config.stopOnError='off';config.deleteOnError='off';
assert.equal(testWords.words.length,111);
assert.equal(main.namespace.areAllWordsGenerated(),true);
for(const index of [104,109,110]) {
  assert.equal(finishModule.namespace.checkIfFinished({goingToNextWord:false,
    testInputWithData:'owned',currentWord:'owned',
    allWordsTyped:index>=testWords.words.length-1,
    allWordsGenerated:main.namespace.areAllWordsGenerated()}),index===110);
}
console.log('Pinned finish helper rejects correct words at configured index 104 and penultimate published index 109; accepts the actual last published index 110. Actual helper/generation predicate; authored handler flags, no complete input-handler execution claim.');

for (const noSpace of [true,false]) for (const terminal of ['last\n', '\n']) {
  config.words=101;activeNames=noSpace?['poetry','nospace']:['poetry'];ownedRepeated=false;
  ownedSection={words:['setup']};ownedSectionQueue=[];ownedSectionError=undefined;
  await main.namespace.generateWords({name:'english',words:['owned']});
  testWords.words.reset();
  for(let i=0;i<100;i++)testWords.words.push(`owned${i}${noSpace?'':' '}`,0);
  main.namespace.currentSection.splice(0,main.namespace.currentSection.length,terminal);
  ownedActiveWordIndex=0;
  await addWord();
  const last=testWords.words.get().at(-1);
  assert.equal(last.textWithCommit,terminal==='\n'?'\n':'last');
  assert.equal(last.commit,terminal==='\n'?'\n':'');
  ownedRepeated=true;
  await main.namespace.generateWords({name:'english',words:['different']});
  const replayed=await main.namespace.getNextWord(100,100,'owned99 ','owned98 ');
  assert.equal(replayed.word,terminal,'Repeat retains the generator LF before final display stripping');
  ownedRepeated=false;
}
console.log('4 pinned final LF contracts passed in ordinary and nospace modes: nonempty final field loses LF commit; empty LF field retains it. Actual caller, generator and TestWords; owned cursor/provider.');

const insertModule=modules.get('input/handlers/insert-text');
await insertModule.link((id,from)=>moduleFor(resolve(id,from.identifier)));
await insertModule.evaluate();
Object.assign(config,{difficulty:'normal',strictSpace:false,oppositeShiftMode:'off',
  minBurst:'off',keymapMode:'off',blindMode:false,stopOnError:'off',deleteOnError:'off'});
ownedActiveWordIndex=100;ownedCurrentInput='';ownedInput='';ownedFinished=0;
ownedInputEvents.length=0;
assert.equal(testWords.words.getCurrent().textWithCommit,'\n');
await insertModule.namespace.emulateInsertText({data:'\n',now:1000});
assert.equal(ownedFinished,1);
assert.equal(ownedInputEvents.length,1);
assert.equal(ownedInputEvents[0].correct,true);
assert.equal(ownedInputEvents[0].commitsWord,true);
console.log('Pinned complete before-insert/onInsertText accepts and finishes a blank final LF under normal/non-strict settings. Actual validation/util/finish helpers; owned input/events/DOM/navigation adapter, not browser end-to-end proof.');

for(const difficulty of ['normal','expert','master'])for(const strictSpace of [false,true])
for(const stopOnError of ['off','word','letter']) {
  Object.assign(config,{difficulty,strictSpace,stopOnError});
  ownedInput='';ownedCurrentInput='';ownedFinished=0;ownedInputEvents.length=0;
  await insertModule.namespace.emulateInsertText({data:'\n',now:1000});
  assert.equal(ownedFinished,1,JSON.stringify({difficulty,strictSpace,stopOnError}));
  assert.equal(ownedInputEvents.length,1);
  assert.equal(ownedInputEvents[0].correct,true);
  assert.equal(ownedInputEvents[0].commitsWord,
    difficulty==='normal'&&!strictSpace?true:undefined);
}
console.log('18 pinned blank-final-LF rule combinations finish correctly; strict/difficulty suppress navigation, not correct final-word completion. Owned navigation/DOM; no browser end-to-end claim.');

for(const quickEnd of [false,true])for(const stopOnError of ['off','word','letter']) {
  Object.assign(config,{difficulty:'normal',strictSpace:false,quickEnd,stopOnError});
  ownedInput='';ownedCurrentInput='';ownedFinished=0;ownedInputEvents.length=0;
  await insertModule.namespace.emulateInsertText({data:'x',now:1000});
  assert.equal(ownedFinished,quickEnd&&stopOnError==='off'?1:0);
  assert.equal(ownedInputEvents.length,1);
  assert.equal(ownedInputEvents[0].correct,false);
  assert.equal(ownedInputEvents[0].inputStopped,stopOnError==='letter'?true:undefined);
}
console.log('6 pinned blank-final-LF wrong-letter quickEnd/stop rules passed: only unrestricted quickEnd finishes. Actual handlers/helpers, owned DOM/navigation.');
