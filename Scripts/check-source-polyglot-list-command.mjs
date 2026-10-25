// QA only: actual input command, conversion/afterExec, value override and
// No Quit restart guard. Catalog/schema and ordinary restart are owned adapters.
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
const input = body('commandline/commandline-metadata.ts','  customPolyglot: {','  //input',
  value => `globalThis.inputProps=({${value}}).customPolyglot.input;`);
const metadata = body('config/metadata.tsx','  customPolyglot: {','  // input',
  value => `globalThis.configMeta=({${value}}).customPolyglot;`);
const builder = body('commandline/util.ts','function buildInputCommand<','export const __testing');
const restart = body('test/test-logic.ts','export async function restart(','let lastInitError:');
const acceptedNames = new Set(['english','german','spanish','arabic','code_python']);
const accepts = values => values.length >= 2 && values.every(name => acceptedNames.has(name));
const fixtures = [];
for (const raw of ['german english german','english english',' english german ',
  'english  german','english\ngerman','unknown english','\ufeffgerman english\u00a0','', 'arabic code_python']) {
  for (const active of [false,true]) for (const noQuit of [false,true]) for (const page of ['test','settings']) {
    let saves = 0, restartRequests = 0, blocked = 0, returned;
    const notices = [], config = {customPolyglot:['english','german']};
    const context = vm.createContext({Config:config, getActivePage:() => page,
      capitalizeFirstLetter:value => value[0].toUpperCase() + value.slice(1),
      isFunboxActive:name => name === 'no_quit' && noQuit, isTestActive:() => active,
      showNoticeNotification:(_message,options) => { notices.push({important:options?.important ?? false}); blocked++; },
    });
    vm.runInContext(`${input}\n${metadata}\n${builder}\n${restart}`,context);
    assert.equal(context.configMeta.changeRequiresRestart,false);
    context.setConfig = (key,value) => {
      assert.equal(key,'customPolyglot');
      const normalized = context.configMeta.overrideValue({value});
      returned = accepts(normalized);
      if (returned) { config.customPolyglot = [...normalized]; saves++; }
      return returned;
    };
    context.TestLogic = {restart:() => {
      restartRequests++;
      // Execute the complete real caller in its early No Quit branch only.
      // The ordinary generation/restart service is deliberately not simulated.
      return active && noQuit ? context.restart() : Promise.resolve();
    }};
    const schema = {};
    const command = context.buildInputCommand({key:'customPolyglot',isPartOfSubgroup:false,
      inputProps:context.inputProps,configMeta:context.configMeta,schema});
    assert.equal(command.validation.schema,schema);
    assert.equal(command.defaultValue(),'english german');
    const converted = [...command.inputValueConvert(raw)], canSubmit = accepts(converted);
    if (canSubmit) command.exec({input:converted});
    assert.equal(saves,canSubmit && accepts([...new Set(converted)]) ? 1 : 0);
    assert.equal(restartRequests,canSubmit && page === 'test' ? 1 : 0);
    assert.equal(blocked,canSubmit && page === 'test' && active && noQuit ? 1 : 0);
    assert.ok(notices.every(notice => notice.important));
    fixtures.push({raw,converted,canSubmit,active,noQuit,page,saves,restartRequests,blocked,
      saved:config.customPolyglot,returned:returned ?? null});
  }
}
assert.equal(fixtures.length,72);
verify();
process.stdout.write(JSON.stringify({fixtures}));
