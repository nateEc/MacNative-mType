// Read-only QA. Actual timer callers and pinned engine; scalar DOM binding only.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {stripTypeScriptTypes} from 'node:module';
const root=path.resolve(process.argv[2]??'');
function verify(){assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');}
verify();
const archive=process.env.TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE;assert.ok(archive);
const integrity='sha512-'+createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
assert.equal(integrity,'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
assert.ok(fs.readFileSync(path.join(root,'pnpm-lock.yaml'),'utf8').includes(integrity));
const bundle=execFileSync('tar',['-xOf',archive,'package/dist/bundles/anime.esm.js'],{encoding:'utf8',maxBuffer:2**21});
const anime=await import('data:text/javascript;base64,'+Buffer.from(bundle).toString('base64'));
const frontend=path.join(root,'frontend/src/ts');
const misc=fs.readFileSync(path.join(frontend,'utils/misc.ts'),'utf8');
const reduced=misc.match(/export function (?:prefersReducedMotion|applyReducedMotion)\([^]*?\n}/g);
assert.equal(reduced.length,2);
const timer=fs.readFileSync(path.join(frontend,'test/funbox/layoutfluid-funbox-timer.ts'),'utf8');
const fixtures=[];
for(const reduceMotion of [false,true])for(const from of [0,0.375,1])for(const target of [0,1]){
  let parameters;
  const context=vm.createContext({matchMedia:()=>({matches:reduceMotion}),qs:()=>({animate:params=>{parameters=params}})});
  vm.runInContext(stripTypeScriptTypes(reduced.join('\n').replaceAll('export function','function'),{mode:'transform'}),context);
  vm.runInContext(stripTypeScriptTypes(timer.slice(timer.indexOf('const timerEl =')).replaceAll('export function','function'),{mode:'transform'}),context);
  vm.runInContext(target===1?'show()':'hide()',context);
  assert.equal(parameters.opacity,target);
  const object={opacity:from};
  const animation=anime.animate(object,{...parameters,autoplay:false,precision:8});
  const samples=[];
  for(const elapsed of [0,0.001,0.015625,0.03125,0.0625,0.09375,0.125,0.25]){
    animation.seek(elapsed*1000);samples.push({elapsed,opacity:object.opacity});
  }
  animation.cancel();fixtures.push({reduceMotion,from,target,duration:parameters.duration,samples});
}
verify();console.log(JSON.stringify({fixtures}));
