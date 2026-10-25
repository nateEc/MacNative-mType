// QA only: execute the pinned input command, full setter, metadata and full
// test-page config subscriber. Schema/catalog and restart service are adapters.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? '');
function verify() {
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
function body(file, from, until, wrap = value => value) {
  const text = fs.readFileSync(path.join(root,'frontend/src/ts',file),'utf8');
  const start = text.indexOf(from), end = text.indexOf(until,start);
  assert.ok(start >= 0 && end > start);
  return stripTypeScriptTypes(wrap(text.slice(start,end).replace(/^export /gm,'')),{mode:'transform'});
}
const input = body('commandline/commandline-metadata.ts','  customLayoutfluid: {','  customPolyglot: {',
  value => `globalThis.inputProps=({${value}}).customLayoutfluid.input;`);
const metadata = body('config/metadata.tsx','  customLayoutfluid: {','  customPolyglot: {',
  value => `globalThis.configMeta=({${value}}).customLayoutfluid;`);
const builder = body('commandline/util.ts','function buildInputCommand<','export const __testing');
const setter = body('config/setters.ts','export function setConfig<','export function setQuoteLengthAll(');
const subscriber = body('test/test-logic.ts','configEvent.subscribe(','timerEvent.subscribe(');
const names = new Set(['qwerty','dvorak','colemak','workman']);
const accepts = values => values.length >= 2 && values.length <= 15 && values.every(name => names.has(name));
const fixtures = [];
for (const raw of ['colemak qwerty colemak','qwerty qwerty',' qwerty dvorak ',
  'qwerty  dvorak','qwerty\ndvorak','unknown qwerty','\ufeffcolemak qwerty\u00a0','',
  Array(16).fill('qwerty').join(' ')]) {
  for (const enabled of [false,true]) for (const active of [false,true])
    for (const noQuit of [false,true]) for (const page of ['test','settings']) {
      let saves = 0, restarts = 0, listener;
      const notices = [], config = {customLayoutfluid:['qwerty','dvorak','colemak'],
        funbox:[...(enabled ? ['layoutfluid'] : []),...(noQuit ? ['no_quit'] : [])], language:'english'};
      const context = vm.createContext({Config:config, getActivePage:() => page, isTestActive:() => active,
        capitalizeFirstLetter:value => value[0].toUpperCase()+value.slice(1),
        ConfigSchemas:{ConfigSchema:{shape:{customLayoutfluid:{}}}},
        isConfigValueValid:(_label,value) => accepts(value),
        canSetConfigWithCurrentFunboxes:() => true, canSetFunboxWithConfig:() => true,
        saveToLocalStorage:() => { saves++; }, setConfigStore:() => {},
        showNoticeNotification:(_message,options) => notices.push(options?.important ?? false),
        configEvent:{subscribe:callback => { listener = callback; }, dispatch:event => listener(event)},
        restart:() => { restarts++; }, console:{warn:() => {}},
      });
      vm.runInContext(`${input}\n${metadata}\n${builder}\n${setter}\n${subscriber}`,context);
      context.configMetadata = {customLayoutfluid:context.configMeta};
      assert.equal(context.configMeta.changeRequiresRestart,true);
      assert.equal(context.inputProps.afterExec,undefined);
      const command = context.buildInputCommand({key:'customLayoutfluid',isPartOfSubgroup:false,
        inputProps:context.inputProps,configMeta:context.configMeta,schema:{}});
      assert.equal(command.id,'setCustomLayoutfluidCustom');
      assert.equal(command.defaultValue(),'qwerty dvorak colemak');
      const converted = [...command.inputValueConvert(raw)], canSubmit = accepts(converted);
      if (canSubmit) command.exec({input:converted});
      const accepted = canSubmit && accepts([...new Set(converted)]) && !(active && noQuit);
      assert.equal(saves,Number(accepted));
      assert.equal(restarts,Number(accepted && enabled && page === 'test'));
      assert.equal(notices.length,canSubmit && active && noQuit ? 1 : 0);
      assert.ok(notices.every(Boolean));
      fixtures.push({raw,converted,canSubmit,enabled,active,noQuit,page,accepted,saves,restarts,
        saved:config.customLayoutfluid});
    }
}
assert.equal(fixtures.length,144);
verify();
process.stdout.write(JSON.stringify({fixtures}));
