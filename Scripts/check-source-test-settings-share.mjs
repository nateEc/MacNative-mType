import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {stripTypeScriptTypes} from 'node:module';

const root=process.argv[2];
assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),'91bd24bb8513785c7364cbea29296ff7adafac41');
assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
const dependencies=process.env.TYPEBAR_CONFIG_LINK_SOURCE_DEPENDENCIES;
assert.ok(dependencies,'Requires the existing pinned config-link dependency preparation');
const require=createRequire(path.join(dependencies,'package.json'));
assert.equal(require('lz-ts/package.json').version,'1.1.2');
const {compressToURI,decompressFromURI}=require('lz-ts');
const read=file=>fs.readFileSync(path.join(root,'frontend/src/ts',file),'utf8');
const component=read('components/modals/ShareTestSettings.tsx');
const start=component.indexOf('export function ShareTestSettings(');
const end=component.indexOf('\n  return (',start);
assert.ok(start>=0&&end>start);
const misc=read('utils/misc.ts');
const modeStart=misc.indexOf('export function getMode2<');
const modeEnd=misc.indexOf('\n}',modeStart)+2;
assert.ok(modeStart>=0&&modeEnd>modeStart);
let values;
let custom={text:['Own','字😀','e\u0301'],mode:'repeat',limit:{value:3,mode:'word'},pipeDelimiter:false};
const runtime={mode:'words',time:30,words:17,punctuation:true,numbers:false,language:'english',difficulty:'expert',funbox:['no_quit']};
const context=vm.createContext({compressToURI,location:{origin:'https://owned.invalid'},getConfig:runtime,
  getCurrentQuote:()=>({id:42}),CustomText:{getData:()=>custom},
  // Owned value-store adapter: this does not execute Solid/TanStack or JSX.
  createForm:factory=>{values=factory().defaultValues;return{useStore:select=>()=>select({values})}}});
vm.runInContext(stripTypeScriptTypes(misc.slice(modeStart,modeEnd).replace(/^export /,''),{mode:'transform'}),context);
vm.runInContext(stripTypeScriptTypes(component.slice(start,end).replace(/^export /,'')+'\nreturn {url};\n}',{mode:'transform'}),context);
const producer=context.ShareTestSettings();
const keys=['mode','mode2','customText','punctuation','numbers','language','difficulty','funbox'];
assert.deepEqual(Object.keys(values),keys);
assert.ok(Object.values(values).every(value=>value===false));
if(process.argv[3]==='--native-captures'){
  const captures=JSON.parse(fs.readFileSync(0,'utf8')), fixtures=[];
  captures.forEach((capture,index)=>{
    Object.assign(runtime,capture.runtime);custom=capture.custom;
    for(let mask=0;mask<256;mask++){
      if(runtime.mode==='quote'&&(mask&2))continue; // Native quote IDs are explicitly unavailable.
      keys.forEach((key,bit)=>values[key]=Boolean(mask&(1<<bit)));
      const url=producer.url();
      fixtures.push({capture:index,mask,tupleJSON:decompressFromURI(url.slice(url.indexOf('=')+1))});
    }
  });
  fs.writeFileSync(1,JSON.stringify({fixtures}));process.exit(0);
}
const fixtures=[];
for(const mode of ['time','words','custom','zen','quote']) {
  runtime.mode=mode;
  for(let mask=0;mask<256;mask++) {
    keys.forEach((key,index)=>values[key]=Boolean(mask&(1<<index)));
    Object.assign(runtime,{minWpmCustomSpeed:50,minBurstCustomSpeed:75});
    const url=producer.url();
    Object.assign(runtime,{minWpmCustomSpeed:Infinity,minBurstCustomSpeed:Infinity});
    assert.equal(producer.url(),url);
    const token=url.slice(url.indexOf('=')+1);
    fixtures.push({mask,runtimeJSON:JSON.stringify({...runtime,minWpmCustomSpeed:50,minBurstCustomSpeed:75}),
      customJSON:JSON.stringify(custom),quoteID:42,tupleJSON:decompressFromURI(token)});
  }
}
// These are owned inputs to the real library, not bundled reference assets.
const compression=['', 'a', 'aaaaaa', 'ABABABA', JSON.stringify([null,null,null,null,null,null,null,null]),
  '汉字😀e\u0301\ud800\udfff+-$\n\t',Array.from({length:4096},(_,i)=>String.fromCharCode(i)).join(''),
  'own test '.repeat(5000)].map(text=>({text,compressed:compressToURI(text)}));
assert.ok(compression.every(({text,compressed})=>decompressFromURI(compressed)===text));
custom={text:['😀'.repeat(10000)],mode:'repeat',limit:{value:1,mode:'word'},pipeDelimiter:false};
runtime.mode='custom'; keys.forEach(key=>values[key]=key==='mode'||key==='customText');
const unicodeURL=producer.url();
const emoji={customJSON:JSON.stringify(custom),tupleJSON:decompressFromURI(unicodeURL.slice(unicodeURL.indexOf('=')+1))};
assert.ok(emoji.tupleJSON.length<65536);
process.stdout.write(JSON.stringify({fixtures,compression,emoji}));
