// QA only. Full pinned functions, owned eager query/aggregate adapters, no TanStack/DOM/HTTP.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??''),emit=process.argv[3]==='--emit-fixtures';
assert.ok(process.argv[2]&&(!process.argv[3]||emit));
const pin='91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
function bounded(text,start,end) {
  assert.equal(text.split(start).length,2,start);
  const from=text.indexOf(start),to=text.indexOf(end,from+start.length);assert.ok(to>from,end);
  return text.slice(from,to).replace(/^export /gm,'');
}
verify();process.env.TZ='UTC';
class OwnedQuery {
  rows=[];predicates=[];order;maximum;group;projection;
  from({r}) {this.rows=r instanceof OwnedQuery?r.evaluate():r;return this;}
  where(predicate) {this.predicates.push(predicate);return this;}
  orderBy(field,direction) {this.order={field,direction};return this;}
  limit(value) {this.maximum=value;return this;}
  groupBy(field) {this.group=field;return this;}
  select(projection) {this.projection=projection;return this;}
  evaluate() {
    let rows=this.rows.filter(row=>this.predicates.every(predicate=>predicate({r:row})));
    if(this.order) rows=[...rows].sort((a,b)=>{
      const left=this.order.field({r:a}),right=this.order.field({r:b});
      return (left<right?-1:left>right?1:0)*(this.order.direction==='desc'?-1:1);
    });
    if(this.maximum!==undefined) rows=rows.slice(0,this.maximum);
    if(!this.projection) return rows;
    const groups=new Map();
    for(const row of rows) {
      const key=this.group?this.group({r:row}):'all';
      if(!groups.has(key)) groups.set(key,[]);groups.get(key).push(row);
    }
    // Owned empty aggregate convention; not a claim about TanStack empty rows.
    if(!this.group&&!groups.size) groups.set('all',[]);
    return [...groups.values()].map(group=>{
      const fields=this.projection({r:new Proxy({},{get:(_,key)=>({key})})});
      return Object.fromEntries(Object.entries(fields).map(([key,expression])=>{
        if(expression===undefined) return [key,undefined];
        const values=group.map(row=>row[expression.key]);
        switch(expression.aggregate) {
          case 'sum':return [key,values.reduce((sum,value)=>sum+value,0)];
          case 'count':return [key,values.length];
          case 'avg':return [key,values.length?values.reduce((sum,value)=>sum+value,0)/values.length:undefined];
          case 'max':return [key,values.length?Math.max(...values):undefined];
          default:return [key,values[0]];
        }
      }));
    });
  }
}
const aggregate=name=>field=>({...field,aggregate:name});
const context=vm.createContext({Date,Query:OwnedQuery,resultsCollection:[],authenticated:true,
  isAuthenticated:()=>context.authenticated,useLiveQuery:callback=>callback(new OwnedQuery())?.evaluate(),
  sum:aggregate('sum'),count:aggregate('count'),avg:aggregate('avg'),max:aggregate('max'),
  eq:(a,b)=>a===b,gte:(a,b)=>a>=b,inArray:(value,array)=>array.includes(value),length:array=>array.length,
  not:value=>!value,or:(...values)=>values.some(Boolean)});
const source=fs.readFileSync(path.join(root,'frontend/src/ts/collections/results.ts'),'utf8');
const code=[bounded(source,'export function useResultStatsLiveQuery(',
    '// oxlint-disable-next-line typescript/explicit-function-return-type\nexport async function getResultsQueryOnce'),
  bounded(source,'export function buildResultsQuery(','function calcTimeTyping('),
  bounded(source,'function calcTimeTyping(',
    '// oxlint-disable-next-line typescript/explicit-function-return-type\nexport const getSingleResultQueryOptions'),
  bounded(source,'function normalizeResult(','const resultsCollection =')].join('\n');
new vm.Script(stripTypeScriptTypes(code,{mode:'transform'})).runInContext(context);
assert.equal(context.useResultStatsLiveQuery(()=>undefined),undefined);
context.authenticated=false;assert.equal(context.useResultStatsLiveQuery(()=>({})),undefined);context.authenticated=true;
const ids=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222'];
const fixtures=[],dayFixtures=[],modifierFixtures=[];
for(const size of [0,9,11,25]) for(let bits=0;bits<8;bits++) for(const mode of ['all','time','words']) {
  const input=Array.from({length:size},(_,index)=>{
    const rowMode=['time','words','quote','zen','custom'][index%5];
    const duration=rowMode==='time'?(index%2?30:15):rowMode==='custom'?12.345678:12.25;
    const timestamp=Date.parse('2026-10-07T08:00:00Z')+Math.floor(index/4)*86400000+(index%4)*17000;
    const wpm=Number((40.01+index*1.13).toFixed(2)),rawWpm=Number((wpm+10.1).toFixed(2));
    return {_id:`00000000-0000-4000-8000-${String(index+1).padStart(12,'0')}`,
      mode:rowMode,mode2:rowMode==='time'?String(duration):rowMode==='words'?'25':rowMode==='quote'?'owned-quote':rowMode,
      timestamp,testDuration:duration,wpm,rawWpm,acc:98.31-index/100,consistency:80.11-index/100,
      difficulty:index%2?'expert':'normal',punctuation:!!(index%2),numbers:false,funbox:[],
      language:'english',restartCount:index%3,incompleteTestSeconds:[0,1.25,2.35][index%3],
      tags:index%4===0?[]:index%4===1?[ids[0]]:index%4===2?[ids[1]]:ids};
  });
  context.resultsCollection=input.map(row=>context.normalizeResult(structuredClone(row),new Set(ids)));
  const selectedIDs=ids.filter((_,index)=>bits&(1<<index)),includesNoTags=!!(bits&4);
  const state={timestamp:0,difficulty:['normal','expert','master'],pb:[true,false],
    mode:mode==='all'?['time','words','quote','zen','custom']:[mode],punctuation:[true,false],numbers:[true,false],
    quoteLength:[-1,0,1,2,3],language:['english'],tags:[...selectedIDs,...(includesNoTags?['none']:[])],
    funbox:['none'],time:['15','30','60','120','custom'],words:['10','25','50','100','custom']};
  const all=context.useResultStatsLiveQuery(()=>state)[0],recent=context.useResultStatsLiveQuery(()=>state,{lastTen:true})[0];
  const days=context.useResultStatsLiveQuery(()=>state,{groupByDay:true}).sort((a,b)=>a.dayTimestamp-b.dayTimestamp);
  const matchedIDs=context.buildResultsQuery(state).evaluate().map(row=>row._id);
  const wireRows=input.map(row=>{
    const finished=row.timestamp/1000-978307200,started=finished-row.testDuration;
    const wire={id:row._id,mode:row.mode,language:row.language,wpm:Math.round(row.wpm),rawWpm:Math.round(row.rawWpm),
      accuracy:Math.round(row.acc),preciseAccuracy:row.acc,consistency:row.consistency,errorCount:1,eventCount:75,
      speedPrecision:{version:1,wpm:row.wpm,rawWpm:row.rawWpm},accountTagIDs:row.tags,tags:['owned label'],
      startedAt:started,finishedAt:finished,startedAtReferenceTime:started,finishedAtReferenceTime:finished,
      elapsedTime:{version:1,seconds:row.testDuration},restartCount:row.restartCount,
      practiceTiming:{version:1,terminalEngagedMilliseconds:Math.round((row.testDuration-1)*1000),
        priorAttemptEngagedMilliseconds:Math.round(row.incompleteTestSeconds*1000)},
      personalBestConfiguration:{version:1,difficulty:row.difficulty,punctuation:row.punctuation,numbers:row.numbers,lazyMode:false},
      rankingEvidence:{version:1,stopOnLetter:false,modifiers:[]}};
    if(row.mode==='time') {wire.mode2=row.mode2;wire.durationSeconds=Number(row.mode2);}
    if(row.mode==='words') {wire.mode2=row.mode2;wire.wordLimit=25;}
    if(['custom','zen'].includes(row.mode)) wire.mode2=row.mode;
    return wire;
  });
  fixtures.push({wireRows,selectedIDs,includesNoTags,mode,matchedIDs,all,recent,days});
}
for(const controls of [[],['polyglot'],['polyglot','memory']]) for(const selection of ['none','memory','all']) {
  context.resultsCollection=[context.normalizeResult({_id:'owned',timestamp:1800000000000,
    mode:'time',mode2:'15',testDuration:15,wpm:80,rawWpm:90,acc:98,consistency:80,funbox:controls})];
  const state={timestamp:0,difficulty:['normal'],pb:[true,false],mode:['time'],punctuation:[true,false],
    numbers:[true,false],quoteLength:[-1,0,1,2,3],language:['english'],tags:['none'],
    funbox:selection==='all'?['none','polyglot','memory']:[selection],
    time:['15','30','60','120','custom'],words:['10','25','50','100','custom']};
  modifierFixtures.push({controls,selection,matches:context.buildResultsQuery(state).evaluate().length===1});
}
for(const timeZone of ['UTC','America/Los_Angeles','Europe/Berlin','Asia/Shanghai']) {
  process.env.TZ=timeZone;
  const timestamps=['2026-03-08T07:59:00Z','2026-03-08T08:01:00Z','2026-03-09T06:59:00Z','2026-03-09T07:01:00Z']
    .map(value=>Date.parse(value));
  const expected=timestamps.map(timestamp=>context.normalizeResult({timestamp,testDuration:15,wpm:80}).dayTimestamp);
  dayFixtures.push({timeZone,timestamps,expected});
}
process.env.TZ='UTC';
assert.equal(context.calcTimeTyping({mode:'time',mode2:'15',restartCount:2}),22.5);
assert.equal(context.normalizeResult({mode:'time',mode2:'15',restartCount:2,timestamp:0,wpm:80}).timeTyping,15);
assert.equal(fixtures.length,96);assert.equal(dayFixtures.length,4);assert.equal(modifierFixtures.length,9);verify();
console.log(emit?JSON.stringify({referenceCommit:pin,ids,fixtures,dayFixtures,modifierFixtures}):
  'Account history statistics source passed (96 five-mode filtered collections, all/recent-ten/daily aggregates, 4 timezone samples, 9 polyglot/companion queries and legacy precedence; complete pinned functions; owned eager query/aggregate adapters and empty convention, no TanStack/DOM/HTTP/GUI)');
