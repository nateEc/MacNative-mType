// Read-only QA: execute the pinned display expressions; never bundle source assets.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {execFileSync} from 'node:child_process';
const root=path.resolve(process.argv[2]??''),repo=path.resolve(import.meta.dirname,'..');
const mapping=JSON.parse(fs.readFileSync(path.join(repo,'Compatibility/official-layouts.json'),'utf8'));
function verify(){assert.equal(execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),mapping.referenceCommit);
  assert.equal(execFileSync('git',['-C',root,'status','--porcelain'],{encoding:'utf8'}).trim(),'');}
verify();
const read=file=>fs.readFileSync(path.join(root,'frontend/src/ts',file),'utf8');
const ts=text=>stripTypeScriptTypes(text.replace(/^export /gm,''),{mode:'transform'});
function body(text,start,end){const a=text.indexOf(start);assert.ok(a>=0,start);const b=text.indexOf(end,a);assert.ok(b>a,end);return text.slice(a,b);}
let flags=0;
const config={keymapLegendStyle:'dynamic'};
const context=vm.createContext({getConfig:config,getModifierState:()=>({shift:!!(flags&1),alt:!!(flags&2)}),
  isCapsLockOn:()=>!!(flags&4),isMacLike:()=>true});
const display=read('components/pages/test/Keymap.tsx');
vm.runInContext(body(display,'const symbolsPattern =','\n\nexport function'),context);
vm.runInContext(ts('function sourceLayer(){'+body(display,'const { alt, shift } = getModifierState();','\n  });')+'}'),context);
vm.runInContext(ts('function sourceLabel(key,props){'+body(display,'let label = key.legends[props.layer.index];','\n                  };')+'}'),context);
vm.runInContext(ts(read('components/pages/test/keymapConverter.ts').split('const emptyLegends =')[1].replace(/^/, 'const emptyLegends =')),context);
vm.runInContext(ts(read('utils/key-converter.ts').slice(read('utils/key-converter.ts').indexOf('export function mirrorLayoutKeys('))),context);
const styles=['blank','lowercase','uppercase','dynamic'],layouts=[];
for(const [id,native] of Object.entries(mapping.nativeExact)){
  const original=JSON.parse(fs.readFileSync(path.join(root,'frontend/static/layouts',id+'.json'),'utf8'));
  for(const mirrored of [false,true]){
    const layout=mirrored?context.mirrorLayoutKeys(original):original;
    const rows=Object.values(layout.keys).map(row=>row.map(raw=>{
      const key={legends:context.buildLegends(raw)},labels=[];
      for(const style of styles)for(flags=0;flags<8;flags++){
        config.keymapLegendStyle=style;labels.push(context.sourceLabel(key,{layer:context.sourceLayer()}));
      }
      return labels;
    }));
    layouts.push({id,native,mirrored,rows});
  }
}
verify();console.log(JSON.stringify({styles,layouts}));
