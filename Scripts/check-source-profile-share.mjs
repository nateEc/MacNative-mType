// QA only: complete pinned copy callback, profile route and profile query module.
// Explicit owned clipboard/router/query/HTTP adapters; not a browser/Solid test.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? '');
assert.equal(process.argv.length, 3);
const pin = '91bd24bb8513785c7364cbea29296ff7adafac41';
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(), pin);
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
const read = file => fs.readFileSync(path.join(root, 'frontend/src/ts', file), 'utf8');
const details = read('components/pages/profile/UserDetails.tsx');
const start = details.indexOf('          const url = `${location.origin}/profile/${props.profile.name}`;');
assert.ok(start > 0); const end = details.indexOf('\n        }}', start); assert.ok(end > start);
let failed = false, copies = [], notices = [], alerts = [], calls = [], response, routes = [];
const context = vm.createContext({
  location: {origin:'https://owned.invalid'}, props: {profile:{name:'Owned'}},
  navigator: {clipboard:{writeText: async link => { copies.push(link); if(failed) throw Error('owned failure'); }}},
  showNoticeNotification: message => notices.push(message), alert: message => alerts.push(message),
  PageController: {change: async (...args) => routes.push(args)},
  queryOptions: value => value, baseKey: value => ['owned', value],
  Ape: {users:{getProfile: async request => { calls.push(request); return response; }}},
  queryClient: {resetQueries: async () => {}}, getSnapshot: () => undefined
});
const copy = new vm.Script('(() => {' + details.slice(start, end) + '\n})').runInContext(context);
for(const name of ['Owned', 'With space', '中文用户', '12345678-1234-1234-1234-123456789abc']) {
  context.props.profile.name = name;
  for(failed of [false, true]) {
    copies=[]; notices=[]; alerts=[]; copy(); await Promise.resolve(); await Promise.resolve();
    assert.deepEqual(copies, ['https://owned.invalid/profile/' + name]);
    assert.equal(notices.length, failed ? 0 : 1); assert.equal(alerts.length, failed ? 1 : 0);
    if(failed) assert.ok(alerts[0].includes(copies[0]));
  }
}
const router = read('controllers/route-controller.ts'), marker = '  {\n    path: "/profile/:uidOrName",';
assert.equal(router.split(marker).length, 2);
const routeStart = router.indexOf(marker), routeEnd = router.indexOf('\n  },', routeStart) + 5;
const route = new vm.Script(stripTypeScriptTypes('(' + router.slice(routeStart, routeEnd).trim().replace(/,$/, '') + ')', {mode:'transform'})).runInContext(context);
await route.load({uidOrName:'Owned'}, {replace:true, data:{owned:true}});
assert.equal(routes.length, 1); assert.equal(routes[0][0], 'profile');
assert.equal(routes[0][1].force, true); assert.equal(routes[0][1].replace, true);
assert.equal(routes[0][1].params.uidOrName, 'Owned'); assert.equal(routes[0][1].data.owned, true);
const query = read('queries/profile.ts').replace(/^import .*;\r?\n/gm, '').replaceAll('export ', '');
new vm.Script(stripTypeScriptTypes(query, {mode:'transform'})).runInContext(context);
const getProfile = new vm.Script('getUserProfile').runInContext(context), options = getProfile('Owned');
assert.equal(options.staleTime, 3_600_000); assert.equal(calls.length, 0);
response = {status:200, body:{data:{name:'Owned', details:{bio:'Owned fixture'}}}};
assert.equal((await options.queryFn()).details.bio, 'Owned fixture');
assert.equal(calls[0].params.uidOrName, 'Owned'); assert.equal(calls[0].query.isUid, false);
for(const status of [404, 429, 500]) {
  response = {status, body:{message:'Owned failure'}};
  await assert.rejects(options.queryFn, /Could not fetch profile/);
}
assert.equal(options.retry(0, Error('User not found')), false);
assert.equal(options.retry(2, Error('Owned network failure')), true);
assert.equal(options.retry(3, Error('Owned network failure')), false);
verify();
console.log('Profile share source passed (8 complete clipboard callbacks; actual profile route and full query module with success/3 HTTP failures/cache/retry; owned adapters, no browser/Solid/HTTP)');
