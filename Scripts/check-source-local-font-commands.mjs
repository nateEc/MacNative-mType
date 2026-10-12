// QA only. Execute pinned command definitions with owned storage/UI adapters.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

const [rootArgument, option] = process.argv.slice(2);
assert.ok(rootArgument && (!option || option === '--emit-fixtures'));
const root = path.resolve(rootArgument);
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/commandline/lists/font-family.ts'), 'utf8');
const code = stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace('export default commands;', 'globalThis.result = commands;'), {mode: 'transform'});
const fixtures = [];
for (const scenario of ['absent', 'stored', 'remove', 'delete failure', 'apply failure']) {
  let stored = scenario !== 'absent', applies = 0;
  const notices = [];
  const context = vm.createContext({
    FontNameSchema: {}, withValidation: value => value,
    buildCommandForConfigKey: key => {
      assert.equal(key, 'fontFamily'); return {subgroup: {list: []}};
    },
    FileStorage: {
      hasFile: async key => { assert.equal(key, 'LocalFontFamilyFile'); return stored; },
      deleteFile: async key => {
        assert.equal(key, 'LocalFontFamilyFile');
        if (scenario === 'delete failure') throw new Error('owned delete failure');
        stored = false;
      },
    },
    Config: {fontFamily: 'Owned_Family'}, setConfig: () => { throw new Error('Unexpected config mutation'); },
    applyFontFamily: async () => {
      applies += 1;
      if (scenario === 'apply failure') throw new Error('owned apply failure');
    },
    showNoticeNotification: message => notices.push(message),
  });
  new vm.Script(code).runInContext(context, {timeout: 1000});
  const commands = context.result[0].subgroup.list.find(item => item.id === 'customFont').subgroup.list;
  const upload = commands.find(item => item.id === 'customLocalFont');
  const remove = commands.find(item => item.id === 'removeLocalFont');
  async function capture(phase) {
    const canImport = await upload.available(), canRemove = await remove.available();
    assert.equal(canImport, !stored); assert.equal(canRemove, stored);
    fixtures.push({name: `${scenario}: ${phase}`, stored, canImport, canRemove});
  }
  await capture('before');
  if (['remove', 'delete failure', 'apply failure'].includes(scenario)) {
    await remove.exec();
    await capture('after');
    assert.equal(applies, scenario === 'delete failure' ? 0 : 1);
    assert.equal(notices.length, scenario === 'remove' ? 0 : 1);
    if (notices.length) assert.ok(notices[0].includes('Error removing font:'));
  }
}
verify();
if (option === '--emit-fixtures') process.stdout.write(JSON.stringify(fixtures));
else console.log(`Pinned complete local font commands passed: ${fixtures.length} availability states; owned storage/UI adapters, no real file-picker or registration claim`);
