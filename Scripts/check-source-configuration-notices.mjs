// QA only: complete pinned producers and helpers; owned config/schema/event boundary.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {createRequire} from 'node:module';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
function verify() {
  assert.equal(execFileSync('git', ['-C',root,'rev-parse','HEAD'], {encoding:'utf8'}).trim(), '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C',root,'status','--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
const dependencies = process.env.TYPEBAR_CONFIG_LINK_SOURCE_DEPENDENCIES;
assert.ok(dependencies, 'Readiness supplies an isolated pinned lz-ts runtime');
const require = createRequire(path.join(dependencies, 'package.json'));
assert.equal(require('lz-ts/package.json').version, '1.1.2');
const {compressToURI, decompressFromURI} = require('lz-ts');
function source(file) { return fs.readFileSync(path.join(root,file), 'utf8'); }
function complete(file, name) {
  const text = source(file), start = text.search(new RegExp(`export function ${name}(?=[(<])`)), end = text.indexOf('\n}', start);
  assert.ok(start >= 0 && end > start);
  return text.slice(start, end+2).replace(/^export /, '');
}
const notices = [], changes = [], custom = [];
let restarts = 0, conflict = false, blocked = false, rejectsSetting = false;
const context = vm.createContext({
  Config:{mode:'words',funbox:[]}, location:{search:''}, TestSettingsSchema:{},
  decompressFromURI, parseJsonWithSchema: text => JSON.parse(text),
  tryCatchSync: fn => { try { return {data:fn()}; } catch(error) { return {error}; } },
  setConfig:(key,value) => { if (rejectsSetting) return false; changes.push([key,value]); context.Config[key] = value; return true; },
  restartTest:() => { restarts += 1; }, setSelectedQuoteId:id => changes.push(['selectedQuote',id]),
  CustomText:Object.fromEntries(['setText','setMode','setLimitMode','setLimitValue','setPipeDelimiter'].map(key => [key,value => custom.push([key,value])])),
  showSuccessNotification:(message,options={}) => notices.push({message,options,level:'success'}),
  showNoticeNotification:(message,options={}) => notices.push({message,options,level:'notice'}),
  showErrorNotification:(message,options={}) => notices.push({message,options,level:'error'}),
  isTestActive:() => blocked,
  canSetFunboxWithConfig:() => ({ok:!conflict, errors:[{key:'mode',value:'Owned < & " \' / `'}, {key:'numbers',value:true}]}),
  isConfigValueValid:()=>true, ConfigSchemas:{FunboxSchema:{}},
  saveToLocalStorage:()=>{}, configEvent:{dispatch:()=>{}}, setConfigStore:()=>{}, console:{log:()=>{},error:()=>{}}
});
function evaluate(text) { return new vm.Script(stripTypeScriptTypes(text, {mode:'transform'})).runInContext(context, {timeout:1000}); }
for (const name of ['findGetParameter','escapeHTML']) evaluate(complete('frontend/src/ts/utils/misc.ts',name));
for (const name of ['camelCaseToWords','capitalizeFirstLetter']) evaluate(complete('frontend/src/ts/utils/strings.ts',name));
context.Misc = {findGetParameter:context.findGetParameter,escapeHTML:context.escapeHTML};
evaluate(complete('frontend/src/ts/controllers/url-handler.tsx','loadTestSettingsFromUrl'));
evaluate(complete('frontend/src/ts/config/setters.ts','toggleFunbox'));
const tuples = [
  [null,null,null,null,null,null,null,null],
  ['words','25',null,false,true,'english','expert',['capitals']],
  [null,null,null,null,false,null,null,null],
  ['custom',null,{text:['Owned private < & " \' / `'],mode:'repeat',limit:{mode:'word',value:7},pipeDelimiter:true},false,false,'english','normal',[]],
  [null,null,null,null,null,null,null,[]],
  ['time',null,null,null,null,null,null,null],
  [null,'120',null,null,null,null,null,null],
  [null,null,null,null,null,null,null,'capitals']
];
const legacy = [], rendered = [];
const keys = ['mode','mode2','custom text settings','punctuation','numbers','language','difficulty','funbox'];
for (const tuple of tuples) {
  // Fixed results.ts schema declares custom text as a nonempty string array.
  if (tuple[2] !== null) assert.ok(Array.isArray(tuple[2].text) && tuple[2].text.length > 0 && tuple[2].text.every(value=>typeof value==='string'));
  notices.length=0; changes.length=0; custom.length=0; restarts=0; context.Config.mode='words';
  const compressed = compressToURI(JSON.stringify(tuple));
  context.query = '?testSettings='+encodeURIComponent(compressed);
  evaluate('loadTestSettingsFromUrl(query)');
  const fields = tuple.flatMap((value,index) => value===null ? [] : [index]);
  assert.equal(restarts,1); assert.equal(notices.length,fields.length ? 1 : 0);
  if (fields.length) {
    const notice = notices[0]; assert.equal(notice.level,'success');
    assert.deepEqual(JSON.parse(JSON.stringify(notice.options)),{durationMs:10000,useInnerHtml:true});
    const lines = fields.map(index => {
      const value = tuple[index];
      const text = index===2 ? '' : index===3 || index===4 ? (value?'on':'off') : index===7 ? (Array.isArray(value)?value.join(', '):value.split('#').join(', ')) : String(value);
      return keys[index]+(text ? ': '+text : '');
    });
    const prefix = notice.message.split('<br />')[0];
    assert.equal(notice.message, prefix+'<br /><br />'+lines.map(context.escapeHTML).join('<br />'));
    rendered.push({html:notice.message,plain:prefix+'\n\n'+lines.join('\n')});
  }
  legacy.push({link:'https://example.invalid/?testSettings='+encodeURIComponent(compressed),fields});
}
// The original URL producer ignores setter Bool results and describes attempted entries.
// Native application deliberately reports success only for a confirmed accepted callback.
rejectsSetting=true; changes.length=0; notices.length=0;
context.query='?testSettings='+encodeURIComponent(compressToURI(JSON.stringify(['words','25',null,null,null,null,null,null])));
evaluate('loadTestSettingsFromUrl(query)'); assert.equal(changes.length,0); assert.equal(notices[0].level,'success');
rejectsSetting=false;
notices.length=0; context.query='?testSettings=invalid'; evaluate('loadTestSettingsFromUrl(query)');
assert.equal(notices[0].level,'notice');
notices.length=0; context.query='?unrelated=owned'; evaluate('loadTestSettingsFromUrl(query)'); assert.equal(notices.length,0);
conflict=true; evaluate('toggleFunbox("owned_funbox")');
assert.equal(notices[0].level,'notice'); assert.deepEqual(JSON.parse(JSON.stringify(notices[0].options)),{durationMs:5000,useInnerHtml:true});
assert.ok(notices[0].message.includes(context.escapeHTML('Owned < & " \' / `')));
const conflictLines = ['Mode cannot be set to Owned < & " \' / `.', 'Numbers cannot be set to true.'];
rendered.push({html:notices[0].message,plain:notices[0].message.split('<br />')[0]+'\n'+conflictLines.join('\n')});
notices.length=0; blocked=true; context.Config.funbox=['no_quit']; evaluate('toggleFunbox("owned_funbox")');
assert.equal(notices[0].options.important,true);
// Execute the complete real developer notification callback with owned collectors.
const dev = source('frontend/src/ts/components/modals/DevOptionsModal.tsx');
const marker = dev.indexOf('showSuccessNotification("This is a test"');
const callbackStart = dev.lastIndexOf('onClick: () => {',marker), callbackEnd = dev.indexOf('\n      },',marker);
assert.ok(callbackStart>=0 && callbackEnd>callbackStart);
context.hideModal=()=>{}; notices.length=0;
evaluate('('+dev.slice(callbackStart+'onClick: '.length,callbackEnd)+'})()');
assert.equal(notices.length,4); assert.equal(notices[3].options.useInnerHtml,true);
const devLines=notices[3].message.split('<br>'); rendered.push({html:notices[3].message,plain:devLines.join('\n')});
verify();
if (emit) process.stdout.write(JSON.stringify({legacy,rendered}));
else console.log('Configuration notice source passed (8 actual URL producer cases, complete funbox rejection/no-quit and developer callback, 9 owned HTML presentations; real pinned lz-ts, owned schema/config/events, no DOM/Solid/HTTP claim)');
