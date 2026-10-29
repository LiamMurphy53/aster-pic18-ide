'use strict';
const { app, BrowserWindow, ipcMain, dialog, shell, Menu } = require('electron');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const { execFile, spawn } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const { SerialPort } = require('serialport');
const { ad2Arguments, copyTree, Preferences, Toolchain, IDECore, slash } = require('./core.cjs');
app.setName('Aster');
app.setName('Aster');
let window,core,preferences,approved=false,busy=false,ad2Process=null,ad2Run=0;
const assets=path.join(__dirname,'assets'),entry=path.join(assets,'Web/index.html'),entryURL=pathToFileURL(entry).href;
const smoke=process.argv.includes('--smoke-test');
function smokeReport(result){if(smoke&&process.env.ASTER_SMOKE_REPORT)fs.writeFileSync(process.env.ASTER_SMOKE_REPORT,JSON.stringify(result,null,2));}
function failed(error){smokeReport({ok:false,error:String(error.stack||error)});console.error(error);app.exit(1);}
function event(name,data){if(window&&!window.isDestroyed())window.webContents.executeJavaScript('window.asterEvent?.('+JSON.stringify(name)+','+JSON.stringify(data)+')').catch(()=>{});}
async function confirm(title,message,accept='Continue'){return (await dialog.showMessageBox(window,{type:'warning',title,message,buttons:[accept,'Cancel'],defaultId:1,cancelId:1,noLink:true})).response===0;}
function trusted(e){if(e.sender!==window.webContents || e.senderFrame!==window.webContents.mainFrame || e.senderFrame.url!==entryURL)throw Error('Untrusted application frame.');}
async function perform(op,a){
  switch(op){
    case 'ad2Status':case 'ad2Capture':{const helper=ad2Helper();let args=['status'];if(op==='ad2Capture'){args=['capture',...ad2Arguments(a)];await ad2Stop();}const output=await new Promise((resolve,reject)=>execFile(helper,args,{timeout:16000,maxBuffer:4*1024*1024,windowsHide:true},(error,stdout,stderr)=>error?reject(Error((stderr||error.message).trim())):resolve(stdout)));return JSON.parse(output);}
    case 'bootstrap':{const root=path.join(os.homedir(),'MPLABXProjects');const found=fs.existsSync(root)?fs.readdirSync(root).filter(n=>n.endsWith('.X')).map(n=>slash(path.join(root,n))):[];return {tools:core.tc.status(),recent:[...new Set([...(preferences.data.recent||[]),...found])],device:JSON.parse(fs.readFileSync(path.join(assets,'Resources/device.json'))),ports:await ports(),initialProject:'',testMode:false};}
    case 'open':{const result=core.open(a.path);preferences.set('recent',[a.path,...(preferences.data.recent||[]).filter(p=>p!==a.path)].slice(0,12));window.setTitle(result.name+' — Aster');return result;}
    case 'new':{let dest=path.resolve(a.path);if(!/\.X$/i.test(dest))dest+='.X';if(!/^[A-Za-z][A-Za-z0-9_-]*$/.test(path.basename(dest,'.X')))throw Error('Use letters, numbers, underscores, or hyphens for the project name.');if(fs.existsSync(dest))throw Error('A folder already exists there.');const kind=a.template||'blank';if(!['blank','basic','interrupt','c'].includes(kind))throw Error('Unknown template.');copyTree(path.join(assets,'Resources',kind==='interrupt'?'InterruptTemplate.X':kind==='c'?'CTemplate.X':'Template.X'),dest);const xml=path.join(dest,'nbproject/project.xml');fs.writeFileSync(xml,fs.readFileSync(xml,'utf8').replaceAll('Template.X',path.basename(dest)).replaceAll('<name>Template</name>','<name>'+path.basename(dest,'.X')+'</name>'));if(kind==='blank')fs.writeFileSync(path.join(dest,'main.asm'),'');core.open(dest);try{await core.regenerate();}catch(e){event('buildOutput','Project created. Regenerate Makefiles after setting up the Microchip tools.\n'+e.message+'\n');}return core.project.info();}
    case 'project':return core.requireProject().info();
    case 'configuration':if(core.debugger)throw Error('Stop debugging before changing configuration.');core.requireProject().select(a.name);return core.project.info();
    case 'addSource':{if(core.debugger)throw Error('Stop debugging before adding files.');const file=core.requireProject().addSource(a.name);let warning='';try{await core.regenerate();}catch(e){warning='File added. Use Regenerate Makefiles before building: '+e.message;}return {project:core.project.info(),path:slash(file),warning};}
    case 'setWatches':if(slash(core.requireProject().root)!==a.projectPath)throw Error('The project changed before watches could be saved.');core.project.saveWatches(a.watches);return true;
    case 'read':return core.requireProject().read(a.path);
    case 'save':return core.requireProject().save(a.path,a.content,a.digest,a.encoding||'utf8');
    case 'build':return core.build({debug:!!a.debug});
    case 'clean':await core.build({clean:true});return core.build({clean:true,debug:true});
    case 'regenerate':return core.regenerate();
    case 'debugStart':return core.startDebug(a);
    case 'debugAction':return core.debugAction(a.action,a.names);
    case 'inspect':return core.inspect(a.names||[]);
    case 'resetStopwatch':return core.resetStopwatch();
    case 'breakpoint':return core.breakpoint(a.path,a.line);
    case 'resolveAddress':return core.resolveAddress(a.address);
    case 'pointerAddress':return core.pointerAddress(a.pointer);
    case 'fullDisassembly':return core.fullDisassembly();
    case 'memory':return core.memory(a.type||'r',a.address||'0x0',a.count??64,a.format||'xb');
    case 'writeRegister':return core.writeRegister(a.name,a.value);
    case 'debugCommand':if(!core.debugger)throw Error('Start debugging first.');return core.debugger.command(a.command);
    case 'stack':return core.paused().command('backtrace');
    case 'setPin':return core.setPin(a.pin,!!a.high);
    case 'triggerInterrupt':return core.triggerInterrupt(a.source);
    case 'detectTools':return core.detectTools();
    case 'program':return core.program(a.index??0);
    case 'serialPorts':return ports();
    case 'serialConnect':{if(!(await ports()).includes(a.path)||![1200,2400,4800,9600,19200,38400,57600,115200,230400].includes(a.baud??19200))throw Error('Select an available serial port and baud rate.');await disconnect();const port=new SerialPort({path:a.path,baudRate:a.baud??19200,dataBits:8,stopBits:1,parity:'none',rtscts:false,autoOpen:false});core.serial=port;port.on('data',d=>event('serialData',d.toString()));port.on('error',e=>event('serialData','\n'+e.message+'\n'));port.on('close',()=>{if(core.serial===port){core.serial=null;event('serialData','\n[Serial device disconnected]\n');}});await new Promise((resolve,reject)=>port.open(e=>e?reject(e):resolve()));return true;}
    case 'serialDisconnect':await disconnect();return true;
    case 'serialSend':if(!core.serial?.isOpen)throw Error('Connect a serial port first.');await new Promise((resolve,reject)=>core.serial.write(a.text,e=>e?reject(e):resolve()));return true;
    case 'settings':{if(core.debugger)throw Error('Stop debugging before changing tools.');const tc=new Toolchain(a.mplab,a.xc8);if(!tc.status().every(t=>t.available))throw Error('Some tool files are missing from these paths.');core.tc=tc;preferences.set('mplab',tc.mplab);preferences.set('xc8',tc.xc8);return tc.status();}
    case 'openDoc':{const names=JSON.parse(fs.readFileSync(path.join(assets,'Resources/references.json'),'utf8'));const filename=names[a.key];if(typeof filename!=='string')throw Error('Unknown reference.');
      const folders=[preferences.data.referenceFolder,core.project?.root,core.project&&path.dirname(core.project.root),core.project&&path.dirname(path.dirname(core.project.root)),path.join(os.homedir(),'Downloads'),path.join(assets,'Resources/References')].filter(Boolean);
      if(a.key==='assembler')folders.unshift(core.tc.xc8+'/docs');
      let file=folders.flatMap(dir=>['','lab1','lab2','lab3','lab4','lab5'].map(sub=>path.join(dir,sub,filename))).find(f=>fs.existsSync(f));
      if(!file){const r=await dialog.showOpenDialog(window,{title:'Locate '+filename,properties:['openFile'],filters:[{name:'PDF reference',extensions:['pdf']}]});if(r.canceled)return false;file=r.filePaths[0];preferences.set('referenceFolder',path.dirname(file));}
      const error=await shell.openPath(file);if(error)throw Error(error);return true;}

    default:throw Error('Unknown operation: '+op);
  }
}
function ad2Helper(){const packaged=path.join(process.resourcesPath,'ad2','aster-ad2.exe'),local=path.join(__dirname,'ad2','aster-ad2.exe'),helper=fs.existsSync(packaged)?packaged:local;if(!fs.existsSync(helper))throw Error('Analog Discovery capture helper is missing. Rebuild with Visual Studio C tools.');return helper;}
// run: the helper prints one json frame per line until its stdin closes
async function ad2Start(a){const args=['run',...ad2Arguments(a)],helper=ad2Helper();await ad2Stop();const id=++ad2Run,child=spawn(helper,args,{windowsHide:true});ad2Process=child;let buffer='',error='';
  child.stdout.setEncoding('utf8');child.stdout.on('data',chunk=>{buffer+=chunk;let nl;while((nl=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,nl).trim();buffer=buffer.slice(nl+1);if(line)try{event('ad2Frame',{run:id,frame:JSON.parse(line)});}catch{}}});
  child.stderr.setEncoding('utf8');child.stderr.on('data',chunk=>error+=chunk);child.on('error',e=>error+=e.message);
  child.on('close',code=>{if(ad2Process===child)ad2Process=null;event('ad2Stopped',{run:id,error:code===0?'':error.trim()||'Analog Discovery capture stopped.'});});
  return {run:id};}
function ad2Stop(){const child=ad2Process;ad2Process=null;if(!child||child.exitCode!==null)return Promise.resolve();return new Promise(resolve=>{const timer=setTimeout(()=>{child.kill();resolve();},3000);child.once('close',()=>{clearTimeout(timer);resolve();});child.stdin.end();});}
async function ports(){return (await SerialPort.list()).map(p=>p.path).sort();}
async function disconnect(){const port=core.serial;core.serial=null;if(port?.isOpen)await new Promise(resolve=>port.close(()=>resolve()));}
app.whenReady().then(async()=>{
  if(process.platform!=='win32'&&!smoke){dialog.showErrorBox('Windows edition','Use the native Aster.app on macOS. This edition is for Windows.');app.quit();return;}
  preferences=new Preferences(path.join(app.getPath('userData'),'settings.json'));
  core=new IDECore(preferences,event,message=>confirm('Confirm the connected device',message));
  window=new BrowserWindow({width:1440,height:930,minWidth:1000,minHeight:700,title:'Aster — PIC18 workspace',backgroundColor:'#19222e',show:!smoke,webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true}});
  window.webContents.setWindowOpenHandler(()=>({action:'deny'}));window.webContents.on('will-navigate',(e,url)=>{if(url!==entryURL)e.preventDefault();});window.webContents.session.setPermissionRequestHandler((_wc,_permission,callback)=>callback(false));
  const command=(label,op,accelerator)=>({label,accelerator,click:()=>event('menu',op)});
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {label:'File',submenu:[command('Open Project…','open','Ctrl+O'),command('New Project…','new','Ctrl+N'),command('Save','save','Ctrl+S'),command('Save All','saveAll','Ctrl+Shift+S'),{role:'quit'}]},
    {label:'Edit',submenu:[{role:'undo'},{role:'redo'},{type:'separator'},{role:'cut'},{role:'copy'},{role:'paste'},{role:'selectAll'},command('Find','find','Ctrl+F')]},
    {label:'Project',submenu:[command('Build','build','Ctrl+B'),command('Clean','clean'),command('Regenerate Makefiles','regenerate'),command('Reveal in Explorer','reveal'),command('Toolchain Settings','settings','Ctrl+,')]},
    {label:'Debug',submenu:[command('Start Session','debug','Ctrl+D'),command('Continue / Pause','toggleRun'),command('Step Instruction','stepi'),command('Step Over','next'),command('Reset','reset'),command('Stop Session','stop')]}
  ]));
  ipcMain.on('aster:response',(e,response)=>{trusted(e);window.webContents.executeJavaScript('window.asterResponse?.('+JSON.stringify(response.id)+','+JSON.stringify(response.value??null)+','+JSON.stringify(response.error||'')+')').catch(()=>{});});
  ipcMain.handle('aster:request',async(e,op,a)=>{
    trusted(e);
    if(op==='cancel'){core.runner.cancel();return true;}
    if(op==='ad2Run')return ad2Start(a);
    if(op==='ad2Stop'){await ad2Stop();return true;}
    if(op==='confirm')return confirm(a.title||'Continue?',a.message||'',a.accept||'Continue');
    if(op==='closeApproved'){approved=true;ad2Stop();core.shutdown();app.quit();return true;}
    if(op==='chooseProject'){const choice=await dialog.showMessageBox(window,{message:'What would you like to open?',buttons:['Project folder','HEX / ELF image','Cancel'],cancelId:2});if(choice.response===2)return '';const r=await dialog.showOpenDialog(window,{title:'Open MPLAB project or image',properties:[choice.response===0?'openDirectory':'openFile'],filters:[{name:'PIC images',extensions:['hex','elf']}]});return r.canceled?'':slash(r.filePaths[0]);}
    if(op==='chooseSource'){const r=await dialog.showOpenDialog(window,{title:'Import starter into current tab',properties:['openFile'],filters:[{name:'Source files',extensions:['c','h','asm','s','inc']}]});if(r.canceled)return null;const file=r.filePaths[0],data=fs.readFileSync(file);if(data.length>2000000)throw Error('Source file is too large.');let content;try{content=new TextDecoder('utf-8',{fatal:true}).decode(data);}catch{content=data.toString('latin1');}return {name:path.basename(file),content};}
    if(op==='exportText'){if(typeof a.content!=='string'||Buffer.byteLength(a.content)>4000000||typeof a.name!=='string')throw Error('Invalid export.');const r=await dialog.showSaveDialog(window,{title:'Export',defaultPath:path.basename(a.name)});if(r.canceled)return false;fs.writeFileSync(r.filePath,a.content,'utf8');return true;}
    if(op==='chooseNew'){const r=await dialog.showSaveDialog(window,{title:'Create PIC18 Project',defaultPath:path.join(os.homedir(),'MPLABXProjects','MyProject.X')});return r.canceled?'':slash(r.filePath);}
    if(op==='reveal'){const file=a.path?core.requireProject().allowed(a.path):core.project?.root||assets;shell.showItemInFolder(file);return true;}
    if(busy)throw Error('An operation is already in progress.');busy=true;try{return await perform(op,a);}finally{busy=false;}
  });
  window.on('close',e=>{if(!approved&&!smoke){e.preventDefault();event('requestClose',true);}});
  await window.loadFile(entry);
  if(smoke){const smokeDir=fs.mkdtempSync(path.join(os.tmpdir(),'aster-smoke-'));const smokeProject=path.join(smokeDir,'Smoke.X');copyTree(path.join(assets,'Examples/FirstLight.X'),smokeProject);try{const result=await window.webContents.executeJavaScript(`(async()=>{for(let i=0;i<100;i++){if(document.querySelector('#toolStatus')?.textContent!=='Checking tools…'&&document.querySelector('.cm-editor')){await loaded(await api('open',{path:${JSON.stringify(slash(smokeProject))}}));const file=S.active;if(!file)throw Error('No source opened');const original=await api('read',{path:file});const content=original.content+'\\n; packaged bridge save check\\n';await api('save',{path:file,content,digest:original.digest,encoding:original.encoding});const saved=await api('read',{path:file});if(saved.content!==content)throw Error('Bridge save mismatch');return {title:document.title,editor:true,bridge:!!window.webkit?.messageHandlers?.aster,node:typeof require,project:true,save:true};};await new Promise(r=>setTimeout(r,100));}throw Error(document.querySelector('#toast')?.textContent||'Editor did not initialize');})()`);if(!result.editor||!result.bridge||result.node!=='undefined')throw Error(JSON.stringify(result));smokeReport({ok:true,...result});console.log('ASTER_SMOKE_OK '+JSON.stringify(result));fs.rmSync(smokeDir,{recursive:true,force:true});approved=true;app.exit(0);}catch(e){fs.rmSync(smokeDir,{recursive:true,force:true});failed(e);}}
}).catch(e=>{failed(e);});
app.on('before-quit',e=>{if(!approved&&!smoke&&window&&!window.isDestroyed()){e.preventDefault();event('requestClose',true);}else{ad2Stop();core?.shutdown();}});
app.on('window-all-closed',()=>app.quit());
