// QA only: execute pinned background selection with a non-loading DOM adapter.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';
const root = path.resolve(process.argv[2] ?? '');
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(),
    '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
const source = fs.readFileSync(path.join(root, 'frontend/src/ts/controllers/theme-controller.ts'), 'utf8');
const first = source.indexOf('function applyCustomBackgroundSize():');
const last = source.indexOf('export function applyCustomBackgroundFilters(', first);
assert.ok(first >= 0 && last > first);
let local, image, style;
const context = vm.createContext({Config:{}, fileStorage:{getFile:async () => local},
  applyCustomBackgroundFilters() {},
  qs:() => ({hide() {}, addClass() {}, removeClass() {}, remove() {image = null;},
    setStyle(value) {Object.assign(style, value);}}),
  document:{querySelector:() => ({replaceChildren(value) {image = value;}}),
    createElement:() => ({attributes:{}, setAttribute(key, value) {this.attributes[key] = value;}})},
});
vm.runInContext(stripTypeScriptTypes(source.slice(first, last).replace(/^export /gm, ''), {mode:'transform'}), context);
const units = text => Array.from({length:text.length}, (_, i) => text.charCodeAt(i));
const fixtures = [];
for (const address of ['', 'https://example.com/owned.png', 'http://example.com/\ud800.png']) {
  for (const file of [undefined, '', 'data:owned-local', '\ud800']) {
    for (const fit of ['cover', 'contain', 'max']) {
      context.Config = {customBackground:address, customBackgroundSize:fit};
      local = file; image = null; style = {};
      await context.applyCustomBackground();
      fixtures.push({address:units(address), local:file === undefined ? null : units(file), fit,
        selected:image === null ? null : units(image.attributes.src), objectFit:style.objectFit ?? null});
    }
  }
}
verify();
process.stdout.write(JSON.stringify(fixtures));
