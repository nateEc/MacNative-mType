// QA only: execute the pinned TTS module against an owned, silent browser boundary.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';
const root = path.resolve(process.argv[2] ?? '');
assert.ok(process.argv[2], 'Pinned reference required');
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding: 'utf8'}).trim(), '');
}
verify();
const Config = {language: 'english', funbox: ['tts', 'polyglot'], customPolyglot: ['english', 'german']};
const rows = [], subscribers = {};
const context = vm.createContext({
  SpeechSynthesisUtterance: class {},
  window: {speechSynthesis: {cancel() {}, speak(voice) {
    rows.push({language: Config.language, locale: voice.lang, text: voice.text});
  }}},
});
const dependencies = {
  '../config/store': {Config},
  '../utils/json-data': {getLanguage: async name => JSON.parse(fs.readFileSync(
    path.join(root, 'frontend/static/languages', `${name}.json`), 'utf8'))},
  '../events/config': {configEvent: {subscribe(fn) { subscribers.config = fn; }}},
  '../events/tts': {ttsEvent: {subscribe(fn) { subscribers.tts = fn; }}},
};
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/test/tts.ts'), 'utf8');
const module = new vm.SourceTextModule(stripTypeScriptTypes(source, {mode: 'transform'}), {context});
await module.link(name => {
  const values = dependencies[name];
  assert.ok(values, `Unexpected dependency ${name}`);
  return new vm.SyntheticModule(Object.keys(values), function() {
    for (const [key, value] of Object.entries(values)) this.setExport(key, value);
  }, {context});
});
await module.evaluate();
for (const language of ['english', 'german', 'french', 'arabic', 'code_python']) {
  Config.language = language;
  await module.namespace.init();
  await module.namespace.speak('owned prompt');
}
Config.language = 'spanish';
subscribers.config({key: 'language', newValue: 'spanish'});
await new Promise(resolve => setImmediate(resolve));
subscribers.tts('owned changed-language prompt');
await new Promise(resolve => setImmediate(resolve));
module.namespace.clear();
Config.language = 'german';
subscribers.config({key: 'funbox', newValue: ['polyglot', 'tts']});
await new Promise(resolve => setImmediate(resolve));
subscribers.tts('owned re-enabled prompt');
await new Promise(resolve => setImmediate(resolve));
assert.equal(rows.length, 7);
verify();
process.stdout.write(JSON.stringify(rows));
