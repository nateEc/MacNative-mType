// QA only. Execute complete pinned numeric functions; no original code/assets in the app.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??''),emit=process.argv[3]==='--emit-fixtures';
assert.ok(process.argv[2]&&(!process.argv[3]||emit));
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
function tail(file,start,end) {
  const source=fs.readFileSync(path.join(root,file),'utf8');
  assert.equal(source.split(start).length,2,start);
  const begin=source.indexOf(start),finish=end?source.indexOf(end,begin+start.length):source.length;
  assert.ok(finish>begin);
  return source.slice(begin,finish).replace(/^export /gm,'');
}
verify();
const context=vm.createContext({});
const code=[
  tail('frontend/src/ts/components/pages/account/HistoryChart.tsx','function movingAverage('),
  tail('frontend/src/ts/components/pages/account/HistogramChart.tsx','function groupIntoBuckets('),
  tail('frontend/src/ts/utils/numbers.ts','export function findLineByLeastSquares(','/**\n * Parses a string'),
  fs.readFileSync(path.join(root,'frontend/src/ts/utils/typing-speed-units.ts'),'utf8')
    .replace(/^import .*;\n/m,'').replace(/^export /gm,''),
  tail('packages/util/src/numbers.ts','export function roundTo2(','/**\n * Calculates the mean'),
  'const getTypingSpeedUnit=get; const Numbers={roundTo2};',
  fs.readFileSync(path.join(root,'frontend/src/ts/utils/format.ts'),'utf8')
    .replace(/^import [\s\S]*?;\n/gm,'').replace(/^export /gm,''),
  'globalThis.formatter=(unit,decimals)=>new Formatting({typingSpeedUnit:unit,alwaysShowDecimalPlaces:decimals});',
].join('\n');
new vm.Script(stripTypeScriptTypes(code,{mode:'transform'})).runInContext(context);
const fixtures=[];
const ratioExpression=tail('frontend/src/ts/components/pages/account/TestStats.tsx','stats.completed > 0',': "0.0"')+': "0.0"';
const ratios=[[0,0],[0,1],[5,4],[23,20],[27,20],[21,20],[39,20],[51,20],[53,20],[1000,3]].map(([restarted,completed])=>{
  context.stats={restarted,completed};
  return {value:completed?restarted/completed:0,text:new vm.Script(ratioExpression).runInContext(context)};
});
const sequences=[[],[0],[9.9],[9.5,10.1],[80.49,100.25,90.01],
  ...[9,10,11,99,100,101,125].map(size=>Array.from({length:size},(_,i)=>Number(((i*37.17+0.49)%419.9).toFixed(2))))];
for(const speeds of sequences) for(const unit of ['wpm','cpm','wps','cps','wph']) {
  const settings=context.get(unit),accuracies=speeds.map((_,index)=>Number((80+(index*3.13)%20).toFixed(2)));
  const line=context.findLineByLeastSquares([...speeds].reverse());
  const trend=line?(line[1][1]-line[0][1])*3600/(60*speeds.length):null;
  fixtures.push({unit,speeds,accuracies,
    speed10:context.movingAverage(speeds,10),speed100:context.movingAverage(speeds,100),
    accuracy10:context.movingAverage(accuracies,10),accuracy100:context.movingAverage(accuracies,100),
    envelope:context.pb(speeds),trend:Number.isFinite(trend)?trend:null,
    buckets:context.groupIntoBuckets(speeds.map(value=>settings.fromWpm(value)),settings.histogramDataBucketSize),
    ratios:speeds===sequences[0]&&unit==='wpm'?ratios:[],
    formats:speeds===sequences[0]?[0,1.005,10.125,80.5,98.999,-1.005,-10.125,-80.5,0.125,-0.125,419.99,80.49]
      .flatMap(value=>[false,true].map(decimals=>({value,decimals,text:context.formatter(unit,decimals).typingSpeed(value)}))):[]});
}
assert.deepEqual(JSON.parse(JSON.stringify(context.groupIntoBuckets([9.9],10))),[{x:'0-9',y:0}]);
assert.equal(context.findLineByLeastSquares([]),null);
assert.ok(Number.isNaN(context.findLineByLeastSquares([80])[0][1]));
for(const [value,text] of [[0.49999999999999994,'0'],[-0.5000000000000001,'-1'],[-0,'0']]) {
  assert.equal(context.formatter('wpm',false).typingSpeed(value),text);
}
verify();
if(emit) console.log(JSON.stringify(fixtures));
else console.log(`Account history graphs source passed (${fixtures.length} sequences/unit combinations, 120 formatting boundaries, 10 TestStats ratio expressions; complete moving averages, envelope, least-squares, histogram, five units, roundTo2 and Formatting; numeric only, no Charts/DOM/GUI)`);
