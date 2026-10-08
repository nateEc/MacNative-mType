// QA only. Complete pinned notification state/error utility; owned array store/timers.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const root = path.resolve(process.argv[2] ?? ''), emit = process.argv[3] === '--emit-fixtures';
assert.ok(process.argv[2] && (!process.argv[3] || emit));
function verify() {
  assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(), '91bd24bb8513785c7364cbea29296ff7adafac41');
  assert.equal(execFileSync('git', ['-C', root, 'status', '--porcelain'], {encoding:'utf8'}).trim(), '');
}
verify();
let timerID = 0;
const timers = new Map(), delays = [], calls = [], warnings = [];
const context = vm.createContext({
  createStore: () => {
    const store = [];
    return [store, value => { const next = typeof value === 'function' ? value([...store]) : value; store.splice(0, store.length, ...next); }];
  },
  setTimeout: (callback, delay) => { delays.push(delay); timers.set(++timerID, callback); return timerID; },
  clearTimeout: id => timers.delete(id),
  console: {error: (...args) => warnings.push(args.map(String))}
});
for (const file of ['frontend/src/ts/utils/error.ts', 'frontend/src/ts/states/notifications.ts']) {
  const source = fs.readFileSync(path.join(root, file), 'utf8').replace(/^import .*;\r?\n/gm, '');
  new vm.Script(stripTypeScriptTypes(source.replace(/^export /gm, ''), {mode:'transform'})).runInContext(context, {timeout:1000});
}
function read(expression) { return vm.runInContext(expression, context, {timeout:1000}); }
const actions = [
  {op:'post', message:'Owned notice', level:'notice'},
  {op:'post', message:'Owned success', level:'success'},
  {op:'post', message:'Owned error', level:'error'},
  {op:'post', message:'Owned important', level:'error', options:{important:true, customTitle:'Owned title', durationMs:0, details:{nested:[1,true,null,'Owned']}}},
  {op:'post', message:'Owned negative', level:'notice', options:{durationMs:-1}},
  {op:'post', message:'<b>Owned HTML</b>', level:'success', options:{customTitle:'', customIcon:'gift', useInnerHtml:true, durationMs:100}},
  {op:'remove', message:'Owned notice'}, {op:'remove', message:'Owned notice'}, {op:'clear'},
  ...Array.from({length:30}, (_,index) => ({op:'post', message:`Owned ring ${index}`, level:['notice','success','error'][index%3], options:{durationMs:0}})),
  {op:'post', message:'Owned response', level:'error', options:{details:'Owned detail', response:{status:422,body:{message:'Owned body',validationErrors:['field']}},error:'Owned error'}},
  {op:'post', message:'Owned server', level:'error', options:{response:{status:503,body:{message:'Owned body',validationErrors:['omitted']}}}},
  {op:'post', message:'Owned null', level:'notice', options:{durationMs:0,details:null}},
  {op:'clear'}
];
const ids = new Map(), snapshots = [];
function snapshot() {
  const live = read('getNotifications()'), history = read('getNotificationHistory()');
  return JSON.parse(JSON.stringify({
    active:live.map(value => ({message:value.message,level:value.level,important:value.important,duration:value.durationMs,html:value.useInnerHtml})),
    history:history.map(value => ({title:value.title,message:value.message,level:value.level,details:value.details,html:value.useInnerHtml})),
    calls:[...calls], delays:[...delays]
  }));
}
for (const action of actions) {
  if (action.op === 'post') {
    context.options = {...action.options, onDismiss: reason => calls.push(`${action.message}:${reason}`)};
    context.message = action.message; context.level = action.level;
    ids.set(action.message, read('addNotificationWithLevel(message, level, options)'));
  } else if (action.op === 'remove') { context.removeID = ids.get(action.message); read('removeNotification(removeID)'); }
  else read('clearAllNotifications()');
  snapshots.push(snapshot());
}
assert.equal(actions.length, 43); assert.equal(snapshots[38].history.length, 25);
assert.equal(snapshots.at(-1).active.length, 0); assert.equal(timers.size, 0);
assert.deepEqual(delays, [3250,3250,350]);
// Verify the complete real timer callback and default timeout reason separately.
context.options = {durationMs:1,onDismiss:reason => calls.push(`timer:${reason}`)};
read('addNotificationWithLevel("Owned timeout", "notice", options)');
const [id, callback] = [...timers][0]; timers.delete(id); callback();
assert.equal(timers.has(id), false); assert.equal(read('getNotifications().length'), 0);
assert.equal(calls.at(-1), 'timer:timeout');
assert.equal(read('getNotificationHistory().at(-1).message'), 'Owned timeout');
const copied = [], alerts = [];
let rejectClipboard = false;
context.navigator = {clipboard:{writeText: async text => { if (rejectClipboard) throw new Error('Owned clipboard failure'); copied.push(text); }}};
context.window = {alert: message => alerts.push(message)};
const historySource = fs.readFileSync(path.join(root, 'frontend/src/ts/components/popups/alerts/NotificationHistory.tsx'), 'utf8');
const copyStart = historySource.indexOf('async function copyDetails('), copyEnd = historySource.indexOf('\nexport function NotificationHistory()', copyStart);
assert.ok(copyStart >= 0 && copyEnd > copyStart);
new vm.Script(stripTypeScriptTypes(historySource.slice(copyStart, copyEnd), {mode:'transform'})).runInContext(context, {timeout:1000});
context.entry = {title:'Owned title',message:'Owned message',details:{nested:[true,null,1.5]}};
await read('copyDetails(entry)');
assert.deepEqual(JSON.parse(copied[0]), context.entry);
rejectClipboard = true; await read('copyDetails(entry)');
assert.equal(copied.length, 1); assert.equal(alerts.length, 2); assert.notEqual(alerts[0], alerts[1]);
verify();
if (emit) process.stdout.write(JSON.stringify({actions,snapshots}));
else console.log('Local notice source passed (43 full-module state transitions, ring 25, three levels, response/error details, click/clear, real timeout callback and complete history copy success/failure; owned store/clock/clipboard, no Solid/browser/animation/device claim)');
