const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const config=require('../../Web/config.js'),defs=require('../../Resources/device.json').configs;
const {IDECore}=require('../core.cjs');
const starter='#pragma config FOSC=HS1, PWRTEN=ON, BOREN=ON, BORV=2, PLLCFG=OFF\n#pragma config WDTEN=OFF, CCP2MX=PORTC, XINST=OFF\n';
test('Lab 5 comma-separated C pragmas retain every field when edited',()=>{
 const values=config.read(starter,defs);assert.equal(Object.keys(values).length,8);values.BORV='1';
 const edited=config.apply(starter,values,new Set(),defs,'#pragma config');assert.deepEqual(config.read(edited,defs),values);assert.equal((edited.match(/BORV/g)||[]).length,1);
 delete values.PWRTEN;const removed=config.apply(edited,values,new Set(['PWRTEN']),defs,'#pragma config');assert.deepEqual(config.read(removed,defs),values);assert.match(removed,/BOREN\s*=\s*ON/);
});
test('configuration ignores commented directives and preserves aliases and comments',()=>{
 const source='/*\n#pragma config WDTEN=ON\n*/\nCONFIG EBRT0 = OFF ; keep this comment\n#pragma config FOSC=HS1 // clock\n';
 const values=config.read(source,defs);assert.equal(values.WDTEN,undefined);assert.equal(values.EBTR0,'OFF');values.EBTR0='ON';
 const result=config.apply(source,values,new Set(),defs,'CONFIG');assert.match(result,/EBRT0 = ON ; keep this comment/);assert.match(result,/FOSC=HS1 \/\/ clock/);assert.match(result,/#pragma config WDTEN=ON/);
 const removed=config.apply(result,{},new Set(['EBTR0']),defs,'CONFIG');assert.match(removed,/; keep this comment/);assert.equal(config.read(removed,defs).EBTR0,undefined);
});
test('PIC18F87K22 CCP stimulation writes PIR3 and preserves other flags',async()=>{
 const core=new IDECore({data:{}},()=>{},()=>{});core.debugTool='SIM';let value=0x80;const commands=[];
 core.debugger={running:false,checked:async cmd=>{commands.push(cmd);return 'PIR3 = 0x'+value.toString(16);}};
 core.writeRegister=async (register,v)=>{assert.equal(register,'PIR3');value=Number(v);};
 await core.triggerInterrupt('CCP1');assert.equal(value,0x82);await core.triggerInterrupt('CCP2');assert.equal(value,0x86);assert.deepEqual(commands,['print /x PIR3','print /x PIR3']);
 core.debugTool='PICkit3';await assert.rejects(core.triggerInterrupt('CCP1'),/Simulator only/);
});
test('all Lab 5 reference PDFs have catalogue entries',()=>{
 const refs=require('../../Resources/references.json');assert.equal(Object.keys(refs).length,15);assert.equal(refs.peatmanRPG,'Peatman CH8 - RPG.pdf');assert.equal(refs.xc8Guide,'MPLAB_XC8_C_Compiler_Users_Guide_for_PIC_50002737.pdf');
});

test('configuration preserves comments between comma-separated settings',()=>{const src='#pragma config FOSC=HS1 /* clock, selected */, WDTEN=OFF // watchdog\n';const v=config.read(src,defs);v.FOSC='HS2';assert.equal(config.apply(src,v,new Set(),defs,'#pragma config'),'#pragma config FOSC=HS2 /* clock, selected */, WDTEN=OFF // watchdog\n');});

const {PICProject,Preferences}=require('../core.cjs'),os=require('node:os');
test('new C/header files join MPLAB metadata, without overwriting or escaping',t=>{const root=fs.mkdtempSync(path.join(os.tmpdir(),'aster-cfiles-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));fs.cpSync(path.resolve(__dirname,'../../Resources/CTemplate.X'),root,{recursive:true});const prefs=new Preferences(path.join(root,'prefs.json')),p=new PICProject(root,prefs);p.addSource('timers.c');p.addSource('timers.h');assert.throws(()=>p.addSource('timers.c'),/already exists/);assert.throws(()=>p.addSource('../escape.c'),/filename/);assert.throws(()=>p.addSource('CON.c'),/filename/);const reopened=new PICProject(root,prefs);assert(reopened.declared.includes(path.join(p.root,'timers.c')));assert(reopened.declared.includes(path.join(p.root,'timers.h')));});
const measurements=require('../../Web/measurements.js');
test('pulse timing and CSV use captured edges and actual rate, ignoring partial pulses',()=>{const c={mode:'logic',sampleRate:1000000,channel:2,values:[[0,1],[50,0],[100,1],[1100,0],[20100,1],[21300,0],[40100,1],[41100,0]]};const rows=measurements.pulses(c);assert.equal(rows.length,2);assert.equal(rows[0].period,.02);assert.equal(rows[0].high,.001);assert.equal(rows[1].high,.0012);assert.equal(rows[1].duty,6);const stats=measurements.summary(c);assert(Math.abs((stats.max-stats.min)-.0002)<1e-12);assert.match(measurements.csv(c),/1,0.0001,0.02,0.001,5,1000000,2/);assert.match(measurements.transitionsCSV(c),/1100,0.0011,0,1000000,2/);assert.equal(measurements.summary({...c,values:[[0,0],[100,1]]}),null);assert.equal(measurements.summary({...c,mode:'scope'}),null);});

test('C hardware debug selects compiler flag for one build and restores generated makefile on failure',async t=>{const root=fs.mkdtempSync(path.join(os.tmpdir(),'aster-cdebug-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));fs.cpSync(path.resolve(__dirname,'../../Resources/CTemplate.X'),root,{recursive:true});const prefs=new Preferences(path.join(root,'prefs.json')),core=new IDECore(prefs,()=>{},()=>{});core.open(root);const file=path.join(root,'nbproject/Makefile-default.mk'),original='debug:\n\txc8-cc -mdebugger=none main.c\n';fs.writeFileSync(file,original);core.runner.run=async()=>{assert.match(fs.readFileSync(file,'utf8'),/-mdebugger=pickit3/);return {code:0,log:'built'};};assert((await core.build({debug:true,tool:'PICkit3'})).ok);assert.equal(fs.readFileSync(file,'utf8'),original);core.runner.run=async()=>{throw Error('Compiler unavailable');};await assert.rejects(core.build({debug:true,tool:'PICkit3'}),/Compiler unavailable/);assert.equal(fs.readFileSync(file,'utf8'),original);});
test('AD2 requests match the native helper arguments and reject invalid settings',()=>{const {ad2Arguments}=require('../core.cjs');
 assert.deepEqual(ad2Arguments({mode:'logic',span:.05,channels:[2,0,5],trigger:5,edge:'fall',level:1.5,position:25,triggerMode:'normal',range:50}),['logic','0.05','channels=2,0,5','trigger=5','edge=fall','level=1.5','position=25','mode=normal','range=50']);
 assert.deepEqual(ad2Arguments({mode:'scope',span:2.2,channels:[1],trigger:-1,range:5}),['scope','2.2','channels=1','trigger=none','edge=rise','level=1.5','position=10','mode=auto','range=5']);
 for(const bad of [{mode:'scope',span:.05,channels:[2]},{mode:'logic',span:.05,channels:[1,1]},{mode:'logic',span:.05,channels:[]},{mode:'logic',span:5,channels:[0]},{mode:'logic',span:.05,channels:[0],trigger:16},{mode:'logic',span:.05,channels:[0],edge:'both'},{mode:'scope',span:.05,channels:[0],range:10},{mode:'scope',span:.05,channels:[0],level:30},{mode:'logic',span:.05,channels:[0],position:120}])assert.throws(()=>ad2Arguments(bad),/Invalid Analog Discovery/);
});
test('instrument cursor helpers handle multi-channel captures',()=>{const c={mode:'logic',sampleRate:1e6,span:.05,traces:[{channel:0,values:[[0,0],[100,1],[1100,0]]},{channel:4,values:[[0,1],[500,0]]}]};
 assert.deepEqual(measurements.edges(c),[.0001,.0005,.0011]);assert.equal(measurements.nearest(measurements.edges(c),.001),.0011);assert.equal(measurements.valueAt(c,c.traces[1],.0006),0);assert.equal(measurements.time(.0011),'1.1000 ms');
});
