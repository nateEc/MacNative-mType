// QA only: execute the verified pinned dependency outside the native product.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const [rootArgument, archiveArgument, option] = process.argv.slice(2);
assert.ok(rootArgument && archiveArgument && (!option || option === '--emit-fixtures'),
  'usage: node check-source-account-daily-activity.mjs reference verified-archive [--emit-fixtures]');
const root = path.resolve(rootArgument), archive = path.resolve(archiveArgument);
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
const integrity = 'sha512-gGujVUWTigENcNUnXexObqxhcsedX9rS/iBemM5A1eJlE6GAno8rlNTUzZXV5fu8EpzsE7OQQvbkfaauUA5Y7g==';
const lock = fs.readFileSync(path.join(root, 'pnpm-lock.yaml'), 'utf8');
assert.ok(lock.includes('chartjs-plugin-trendline@3.2.4:') && lock.includes(integrity));
assert.ok(fs.statSync(archive).size < 2_000_000);
assert.equal('sha512-' + createHash('sha512').update(fs.readFileSync(archive)).digest('base64'), integrity);
const read = file => execFileSync('tar', ['-xzOf', archive, 'package/' + file], {encoding:'utf8', maxBuffer:2_000_000});
assert.equal(JSON.parse(read('package.json')).version, '3.2.4');
const context = vm.createContext({});
const source = [read('src/utils/lineFitter.js'), read('src/components/trendline.js')]
  .join('\n').replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '');
new vm.Script(source + `
  const unexpected = () => { throw new Error('unexpected non-linear/fill/label branch'); };
  const ExponentialFitter = unexpected, fillBelowTrendline = unexpected, addTrendlineLabel = unexpected;
  const setLineStyle = (ctx, style) => { if (style !== 'dotted') throw new Error('style changed'); };
  let captured;
  const drawTrendline = ({x1,y1,x2,y2}) => { captured = [x1,y1,x2,y2]; };
  globalThis.evaluate = (dates, minutes, upper) => {
    const fitter = new LineFitter();
    minutes.forEach((value,index) => { if (value != null) fitter.add(dates[index], value); });
    const raw = fitter.count < 2 ? [] : [[fitter.minx,fitter.f(fitter.minx)],[fitter.maxx,fitter.f(fitter.maxx)]];
    const first = dates[0] ?? 1, span = (dates.at(-1) ?? first) - first || 86400000;
    // Owned affine adapters, not a real Chart.js scale, layout, canvas or browser.
    const x = {options:{type:'time'},getPixelForValue:v=>(v-first)/span*1000,getValueForPixel:p=>first+p/1000*span};
    const y = {getPixelForValue:v=>200-v/upper*200,getValueForPixel:p=>(200-p)/200*upper};
    const chart = {scales:{count:y}, options:{}, data:{labels:dates}, chartArea:{left:0,right:1000,top:0,bottom:200}};
    captured = null;
    addFitter({controller:{chart}}, {}, {data:minutes,yAxisID:'count',trendlineLinear:{lineStyle:'dotted',width:2}},x,y);
    const clipped = captured ? [[x.getValueForPixel(captured[0]),y.getValueForPixel(captured[1])],
      [x.getValueForPixel(captured[2]),y.getValueForPixel(captured[3])]] : [];
    return {raw,clipped};
  };
`).runInContext(context, {timeout:1000});
const base = Date.UTC(2026,2,7,8), day = 86400000;
const cases = [
  [[],[],1], [[0],[1],2], [[0,1],[1,2],2], [[0,1,2],[2,2,2],5],
  [[0,1,2],[10,.25,.25],10], [[0,1,2],[.25,.25,10],10],
  [[0,1,2],[.25,10,10],10], [[0,1,2],[10,10,.25],10],
  [[0,1,3],[1,2,4],5], [[0,1,3],[1,null,4],5], [[0,1,3],[null,2,null],5],
  [[0,1,1+23/24],[1,2,3],5], [[0,1,1+25/24],[1,2,3],5],
  [[0,3,15,90],[.25,30,2,100],100], [[0,1,2],[0,0,0],1],
];
const fixtures = cases.map(([offsets,minutes,upper]) => {
  const dates = offsets.map(offset => base + offset*day);
  return {dates,minutes,upper,...JSON.parse(JSON.stringify(context.evaluate(dates,minutes,upper)))};
});
assert.equal(fixtures[0].clipped.length,0);
assert.equal(fixtures[1].clipped.length,0);
assert.ok(fixtures[4].clipped[1][0] < base+2*day, 'negative endpoint must move its date to the zero crossing');
assert.ok(fixtures[6].clipped[1][0] < base+2*day, 'upper clipping must move its date');
assert.equal(fixtures[10].clipped.length,0);
verify();
if (option) console.log(JSON.stringify(fixtures));
else console.log(`Account daily activity source passed (${fixtures.length} fixtures; verified 3.2.4 archive; complete LineFitter, addFitter and clipping; owned affine scale adapters, no Chart.js layout/GUI)`);
