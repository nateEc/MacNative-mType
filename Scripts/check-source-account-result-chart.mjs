// QA only: pinned configuration callbacks, not Chart.js, Solid, DOM or HTTP.
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
verify();
const read=file=>fs.readFileSync(path.join(root,file),'utf8');
const source=read('frontend/src/ts/components/pages/account/MiniResultChart.tsx');
function object(start,end) {
  assert.equal(source.split(start).length,2);
  const from=source.indexOf(start)+start.length-1,to=source.indexOf(end,from);
  assert.ok(to>from);
  const expression=source.slice(from,to).trim();
  assert.ok(expression.endsWith('}}'));
  return '('+expression.slice(0,-1)+')';
}
const dataExpression=object('data={{','options={{');
const optionsExpression=object('options={{','\n              />');
const table=read('frontend/src/ts/components/pages/account/Table.tsx');
assert.equal(table.split('const hasChart =').length,2);
const from=table.indexOf('const hasChart =')+'const hasChart ='.length;
const hasChart=new vm.Script(table.slice(from,table.indexOf(';',from)));
const context=vm.createContext({getTheme:()=>({main:'owned-speed',sub:'owned-burst',error:'owned-error'})});
const units=read('frontend/src/ts/utils/typing-speed-units.ts').replace(/^import .*;\n/m,'').replace(/^export /gm,'');
new vm.Script(stripTypeScriptTypes(units,{mode:'transform'})).runInContext(context);
const dataScript=new vm.Script(stripTypeScriptTypes(dataExpression,{mode:'transform'}));
const optionsScript=new vm.Script(stripTypeScriptTypes(optionsExpression,{mode:'transform'}));
const fixtures=[];
for(const size of [0,1,15,122]) for(const unit of ['wpm','cpm','wps','cps','wph']) for(const zero of [false,true]) {
  const wpm=Array.from({length:size},(_,i)=>i===0?0:60.25+i/100);
  const burst=wpm.map((_,i)=>i===0?0:80+i),errors=wpm.map((_,i)=>i%4===1?2:0);
  context.data={wpm,burst,err:errors};context.typingSpeedUnit=()=>context.get(unit);context.beginAtZero=()=>zero;
  const config=dataScript.runInContext(context),options=optionsScript.runInContext(context);
  assert.deepEqual(Array.from(config.datasets,d=>d.label),['wpm','burst','errors']);
  assert.equal(config.datasets[0].yAxisID,'wpm');assert.equal(config.datasets[1].yAxisID,'wpm');
  assert.equal(config.datasets[2].yAxisID,'error');assert.equal(config.datasets[2].type,'scatter');
  assert.equal(config.datasets[2].pointStyle,'crossRot');
  assert.equal(options.scales.wpm.beginAtZero,zero);assert.equal(options.scales.error.beginAtZero,zero);
  assert.equal(options.scales.error.ticks.precision,0);assert.equal(options.plugins.tooltip.mode,'index');
  assert.equal(options.plugins.tooltip.intersect,false);
  const radii=errors.map((_,dataIndex)=>config.datasets[2].pointRadius({dataIndex,dataset:config.datasets[2]}));
  const hover=errors.map((_,dataIndex)=>config.datasets[2].pointHoverRadius({dataIndex,dataset:config.datasets[2]}));
  assert.deepEqual(radii,errors.map(value=>value>0?3:0));assert.deepEqual(hover,errors.map(value=>value>0?5:0));
  fixtures.push({unit,zero,wpm,burst,errors,labels:Array.from(config.labels),
    speeds:Array.from(config.datasets[0].data),bursts:Array.from(config.datasets[1].data),radii});
}
for(const duration of [0,1,15,122,122.001,123]) for(const chartData of [undefined,'toolong',{}]) {
  context.info={row:{original:{testDuration:duration,chartData}}};
  assert.equal(hasChart.runInContext(context),chartData!=='toolong'&&duration<=122);
}
verify();
if(emit) console.log(JSON.stringify(fixtures));
else console.log(`Account result chart source passed (${fixtures.length} unit/zero/sample combinations, 18 duration/sentinel cases; complete data/options objects and callbacks with owned color adapters; no Chart.js/DOM/HTTP/GUI)`);
