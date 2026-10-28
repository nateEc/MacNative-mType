// QA only: execute complete pinned background functions with an owned DOM and
// gated file storage. No reference code, images or CSS enter the application.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';
const root=path.resolve(process.argv[2]??''),pin='91bd24bb8513785c7364cbea29296ff7adafac41';
function verify(){
  assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),pin);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');
}
verify();
const source=fs.readFileSync(path.join(root,'frontend/src/ts/controllers/theme-controller.ts'),'utf8');
const start=source.indexOf('function applyCustomBackgroundSize():'),end=source.indexOf('\nwindow\n',start);
const errorStart=source.indexOf('window.addEventListener("customBackgroundFailed"'),errorEnd=source.indexOf('\nfunction prefersColorSchemeDark()',errorStart);
assert.ok(start>=0&&end>start&&errorStart>end&&errorEnd>errorStart);
const code=stripTypeScriptTypes(source.slice(start,end).replace(/^export /gm,''),{mode:'transform'});
const fixtures=[];
for(const localKind of ['absent','empty','file','reject']) for(const address of ['', 'https://example.invalid/owned.png'])
for(const fit of ['max','cover','contain']) for(const result of ['load','error']) for(const updates of [false,true]) {
  let resolve,reject,image={id:0,attributes:{src:'owned:old'},style:{}},filterVisible=true,noticeCount=0,nextID=0;
  const classes=new Set(['#words','#resultWordsHistory']),listeners=new Map();
  const context=vm.createContext({Config:{customBackground:address,customBackgroundSize:fit},
    getConfig:{customBackgroundFilter:[0.25,2,3,0.5]},Event:class {constructor(type){this.type=type;}},
    fileStorage:{getFile:key=>{assert.equal(key,'LocalBackgroundFile');return new Promise((yes,no)=>{resolve=yes;reject=no;});}},
    qs:selector=>{
      if(selector==='.customBackground img') {
        const current=image;if(!current)return undefined;
        return {remove(){if(image===current)image=null;},setStyle(style){Object.assign(current.style,style);}};
      }
      if(selector.startsWith('.pageSettings'))return {hide(){filterVisible=false;},show(){filterVisible=true;}};
      assert.ok(['#words','#resultWordsHistory'].includes(selector));
      return {addClass(name){assert.equal(name,'noErrorBorder');classes.add(selector);},removeClass(name){assert.equal(name,'noErrorBorder');classes.delete(selector);}};
    },document:{querySelector:selector=>{assert.equal(selector,'.customBackground');return {replaceChildren(value){image=value;}};},
      createElement:tag=>{assert.equal(tag,'img');return {id:++nextID,attributes:{},style:{},setAttribute(key,value){this.attributes[key]=value;}};}},
    window:{addEventListener(type,callback){listeners.set(type,callback);},dispatchEvent(event){listeners.get(event.type)?.();}},
    showNoticeNotification(){noticeCount++;},
  });
  vm.runInContext(code+source.slice(errorStart,errorEnd),context);
  const frames=[],snapshot=()=>({selected:image?.attributes.src??null,id:image?.id??null,style:image?.style??null,
    filterVisible,borders:classes.size,notices:noticeCount,hidden:image?.style.display==='none'});
  const pending=context.applyCustomBackground().then(()=>true,()=>false);
  frames.push(structuredClone(snapshot()));
  assert.equal(image.id,0);assert.equal(filterVisible,true);
  // The address is captured before storage resolves; fit and filter are read
  // after it resolves. Do not replace these with a precomputed config snapshot.
  context.Config.customBackground='https://example.invalid/late.png';
  const finalFit=updates?(fit==='cover'?'contain':'cover'):fit;
  if(updates){context.Config.customBackgroundSize=finalFit;context.getConfig.customBackgroundFilter=[0.5,1,1,0.75];}
  if(localKind==='reject')reject(new Error('owned storage fault'));
  else resolve(localKind==='absent'?undefined:localKind==='empty'?'':'owned:local');
  const fulfilled=await pending;frames.push(structuredClone(snapshot()));
  const selected=localKind==='reject'?'owned:old':localKind==='file'?'owned:local':localKind==='empty'?null:address||null;
  assert.equal(image?.attributes.src??null,selected);assert.equal(fulfilled,localKind!=='reject');
  if(localKind==='reject'){assert.equal(filterVisible,true);assert.equal(image.id,0);}
  else {
    assert.equal(filterVisible,false);assert.equal(classes.size,selected===null?0:2);
    if(image){assert.equal(image.style.objectFit,finalFit==='max'?'':finalFit);assert.equal(image.style.filter,updates?'blur(0.5rem) opacity(0.75) ':'blur(0.25rem) brightness(2) saturate(3) opacity(0.5) ');}
  }
  if(image&&localKind!=='reject'){
    if(result==='load')image.onload();
    else {context.currentImage=image;vm.runInContext('(function(){'+image.attributes.onError.replace(/^javascript:/,'')+'}).call(currentImage)',context);}
  }
  frames.push(structuredClone(snapshot()));
  if(selected!==null&&localKind!=='reject'){
    assert.equal(filterVisible,result==='load');assert.equal(noticeCount,result==='error'?1:0);assert.equal(image.style.display==='none',result==='error');
  }
  fixtures.push({localKind,address,fit,result,updates,fulfilled,frames});
}
verify();process.stdout.write(JSON.stringify({pin,fixtures}));
