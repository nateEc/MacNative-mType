// QA only: execute fixed command handlers with owned configuration/unit adapters.
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
const defaults = fs.readFileSync(path.join(root, 'frontend/src/ts/constants/default-config.ts'), 'utf8');
const keys = ['minWpm', 'minWpmCustomSpeed', 'minAcc', 'minAccCustom', 'minBurst', 'minBurstCustomSpeed'];
const Config = {typingSpeedUnit: 'wpm'};
for (const key of keys) {
  const value = defaults.match(new RegExp(`^  ${key}: ("[^"\\n]*"|[0-9]+),$`, 'm'));
  assert.ok(value, `Missing fixed default ${key}`);
  Config[key] = JSON.parse(value[1]);
}
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/commandline/lists/min-burst.ts'), 'utf8');
const code = stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace('export default commands;', 'globalThis.commands = commands;'), {mode: 'transform'});
let writes = [];
const context = vm.createContext({Config,
  setConfig: (key, value) => {
    assert.ok(['minBurst', 'minBurstCustomSpeed'].includes(key));
    Config[key] = value;
    writes.push(key);
    return true;
  },
  getTypingSpeedUnit: unit => {
    assert.ok(['wpm', 'cpm'].includes(unit));
    return {toWpm: value => unit === 'cpm' ? value / 5 : value};
  },
});
new vm.Script(code).runInContext(context, {timeout: 1000});
const commands = context.commands[0].subgroup.list;
function state() {
  return {minimumWpmMode: Config.minWpm, minimumWpmCustomValue: Config.minWpmCustomSpeed,
    minimumAccuracyMode: Config.minAcc, minimumAccuracyCustomValue: Config.minAccCustom,
    minimumWordBurstMode: Config.minBurst, minimumWordBurstCustomValue: Config.minBurstCustomSpeed};
}
const fixtures = [{choice: 'initial', input: null, unit: 'wpm', state: state()}];
for (const [choice, input, unit] of [
  ['fixed', '301', 'cpm'], ['off', null, 'wpm'], ['flex', '0', 'wpm'],
  ['off', null, 'wpm'], ['fixed', '0', 'wpm'], ['flex', '50', 'wpm'],
]) {
  Config.typingSpeedUnit = unit;
  writes = [];
  const id = {off: 'setMinBurstOff', fixed: 'setMinBurstFixed', flex: 'setMinBurstFlex'}[choice];
  const command = commands.find(value => value.id === id);
  assert.ok(command);
  command.exec({input});
  assert.deepEqual(writes, choice === 'off' ? ['minBurst'] : ['minBurst', 'minBurstCustomSpeed']);
  fixtures.push({choice, input, unit, state: state()});
}
assert.equal(fixtures[2].state.minimumWordBurstCustomValue, 60.2);
assert.equal(fixtures[3].state.minimumWordBurstMode, 'flex');
assert.equal(fixtures[3].state.minimumWordBurstCustomValue, 0);
assert.equal(fixtures[5].state.minimumWordBurstMode, 'fixed');
assert.equal(fixtures[5].state.minimumWordBurstCustomValue, 0);
verify();
if (option === '--emit-fixtures') process.stdout.write(JSON.stringify(fixtures));
else console.log(`Pinned threshold configuration passed: ${fixtures.length} states; owned Config/unit adapters, not a browser setter or persistence test`);
