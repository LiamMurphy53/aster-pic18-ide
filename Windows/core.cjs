'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const { XMLParser, XMLValidator } = require('fast-xml-parser');
const slash = p => p.replaceAll('\\', '/');
const digest = data => crypto.createHash('sha256').update(data).digest('hex');
const array = v => v == null ? [] : Array.isArray(v) ? v : [v];
const symbol = /^[A-Za-z_][A-Za-z0-9_.$]*$/;
function safeLine(s) { if (typeof s !== 'string' || /[\r\n\0]/.test(s)) throw Error('A debugger command must fit on one line.'); return s; }
function quoteMDB(s) { safeLine(s); if (s.includes('"')) throw Error('Debugger paths cannot contain double quotes.'); return '"' + slash(s) + '"'; }
function inside(root, file) { const r = path.relative(root, file); return r === '' || (!r.startsWith('..' + path.sep) && r !== '..' && !path.isAbsolute(r)); }
function walk(root) {
  if (!fs.existsSync(root)) return [];
  return fs.readdirSync(root, { withFileTypes: true }).flatMap(e => {
    const p = path.join(root, e.name);
    if (e.isSymbolicLink() || e.name.startsWith('.')) return [];
    return e.isDirectory() ? walk(p) : e.isFile() ? [p] : [];
  });
}
// Public fs APIs also work for templates stored inside Electron's app.asar.
// Native fs.cpSync uses internal filesystem calls that bypass the ASAR adapter.
function copyTree(source, target) {
  fs.mkdirSync(target, { recursive: true });
  for (const entry of fs.readdirSync(source, { withFileTypes: true })) {
    const from = path.join(source, entry.name), to = path.join(target, entry.name);
    if (entry.isDirectory()) copyTree(from, to);
    else if (entry.isFile()) fs.writeFileSync(to, fs.readFileSync(from), { flag: 'wx' });
    else throw Error('Unexpected link in project template.');
  }
}
class Preferences {
  constructor(file) { this.file = file; try { this.data = JSON.parse(fs.readFileSync(file)); } catch { this.data = {}; } }
  set(key, value) { this.data[key] = value; fs.mkdirSync(path.dirname(this.file), { recursive: true }); const tmp = this.file + '.tmp'; fs.writeFileSync(tmp, JSON.stringify(this.data)); fs.renameSync(tmp, this.file); }
}
class Toolchain {
  constructor(mplab = 'C:/Program Files/Microchip/MPLABX/v6.20', xc8 = 'C:/Program Files/Microchip/xc8/v2.46') { this.mplab = slash(mplab); this.xc8 = slash(xc8); }
  get platform() { return this.mplab + '/mplab_platform'; }
  get assembler() { return this.xc8 + '/pic-as/bin/pic-as.exe'; }
  get make() { return [this.mplab + '/gnuBins/GnuWin32/bin/make.exe', this.platform + '/bin/make.exe'].find(fs.existsSync) || this.mplab + '/gnuBins/GnuWin32/bin/make.exe'; }
  get pack() { return this.mplab + '/packs/Microchip/PIC18F-K_DFP/1.13.292'; }
  get java() {
    let conf = ''; try { conf = fs.readFileSync(this.platform + '/etc/mplab_ide.conf', 'utf8'); } catch {}
    const jdk = conf.match(/^\s*jdkhome\s*=\s*"([^"]+)"/m)?.[1];
    const candidates = [jdk && path.resolve(this.platform, jdk) + '/bin/java.exe', this.mplab + '/sys/java/zulu8.64.0.19-ca-fx-jre8.0.345-win_x64/bin/java.exe'];
    const sys = this.mplab + '/sys/java';
    if (fs.existsSync(sys)) for (const e of fs.readdirSync(sys)) candidates.push(sys + '/' + e + '/bin/java.exe');
    return slash(candidates.filter(Boolean).find(fs.existsSync) || this.mplab + '/sys/java/bin/java.exe');
  }
  get environment() {
    const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => k.toLowerCase() !== 'path'));
    return { ...env, PATH: [path.dirname(this.make), this.platform + '/bin', this.xc8 + '/bin', this.xc8 + '/pic-as/bin', process.env.PATH || process.env.Path || ''].join(path.delimiter), MPLABX_THIRDPARTY_LIB_PATH: this.platform + '/thirdparty/', netbeans_dir: this.platform, mplabx_dir: this.platform };
  }
  status() { return [['MPLAB X','6.20',this.make],['PIC assembler','2.46',this.assembler],['MDB debugger','6.20',this.platform+'/lib/mdb.jar'],['PIC18F-K device pack','1.13.292',this.pack],['Java runtime','MPLAB bundled',this.java]].map(([name,version,p]) => ({ name,version,path:p,available:fs.existsSync(p) })); }
}
class CommandRunner {
  cancel() { this.cancelled = true; this.process?.kill(); }
  run(executable, args, options = {}, output = () => {}) {
    this.cancelled = false;
    return new Promise((resolve, reject) => {
      const child = spawn(executable, args, { ...options, windowsHide: true, shell: false }); this.process = child;
      let log = '', expired = false;
      const timer = setTimeout(() => { expired = true; child.kill(); }, options.timeout || 120000);
      const receive = d => { const s = d.toString(); log += s; output(s); };
      child.stdout.on('data', receive); child.stderr.on('data', receive);
      child.on('error', e => { clearTimeout(timer); this.process = null; reject(e); });
      child.on('close', code => { clearTimeout(timer); this.process = null;
        if (this.cancelled || expired) reject(Error(this.cancelled ? 'Build cancelled.' : 'The tool exceeded its time limit.'));
        else resolve({ code, log });
      });
    });
  }
}
class PICProject {
  constructor(input, preferences) {
    this.preferences = preferences; this.configuration = 'default'; this.configurations = []; this.declared = [];
    const real = fs.realpathSync(input); this.prebuilt = /\.(hex|elf)$/i.test(real) ? real : null;
    this.root = this.prebuilt ? path.dirname(real) : real;
    if (this.prebuilt) { this.files = [real]; return; }
    const xml = fs.readFileSync(path.join(real, 'nbproject/configurations.xml'), 'utf8');
    if (XMLValidator.validate(xml) !== true) throw Error('Invalid MPLAB project XML.');
    const doc = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '', parseTagValue: false, processEntities: false }).parse(xml);
    const desc = doc.configurationDescriptor;
    this.configurations = array(desc.confs?.conf).map(c => ({name:c.name,device:c.toolsSet?.targetDevice,compiler:c.toolsSet?.languageToolchain,version:c.toolsSet?.languageToolchainVersion,tool:c.toolsSet?.platformTool,
      instructionFrequency:array(c.Simulator?.property).find(p=>p.key==='oscillator.frequency')?.value,
      instructionFrequencyUnit:array(c.Simulator?.property).find(p=>p.key==='oscillator.frequencyunit')?.value}));
    if (!this.configurations.some(c => c.device?.toUpperCase() === 'PIC18F87K22')) throw Error('Choose a PIC18F87K22 MPLAB .X project.');
    this.configuration = this.configurations[0].name;
    const collect = node => { if (!node || typeof node !== 'object') return; for (const [key,value] of Object.entries(node)) {
      if (key === 'itemPath') for (const item of array(value)) this.declared.push(path.resolve(real, String(item)));
      else for (const item of array(value)) collect(item);
    } }; collect(desc.logicalFolder);
    for (const item of ['Makefile','nbproject/configurations.xml','nbproject/project.xml']) if (fs.existsSync(path.join(real,item))) this.declared.push(path.join(real,item));
    this.refresh();
  }
  refresh() {
    if (this.prebuilt) return;
    const scan = dir => fs.readdirSync(dir,{withFileTypes:true}).flatMap(e => {
      if (e.isSymbolicLink() || e.name.startsWith('.')) return [];
      const p = path.join(dir,e.name);
      if (e.isDirectory()) return ['nbproject','build','dist','disassembly'].includes(e.name) || /\.x$/i.test(e.name) ? [] : scan(p);
      return /\.(asm|s|inc|c|h|cpp)$/i.test(e.name) ? [p] : [];
    });
    this.files = [...new Set([...this.declared,...scan(this.root)].map(p=>fs.existsSync(p)?fs.realpathSync(p):p))].sort();
  }
  get watchKey() { return 'watches.' + digest(slash(this.prebuilt || this.root).toLowerCase()); }
  get clockMHz() { const c = this.configurations.find(c=>c.name===this.configuration); const f = Number(c?.instructionFrequency)*({Mega:1,Kilo:.001,None:.000001}[c?.instructionFrequencyUnit || 'Mega'] || 1)*4; return f>=.001 && f<=64 ? f : 16; }
  allowed(input) {
    const resolved = fs.realpathSync(input);
    if (this.files.includes(resolved)) return resolved;
    if (['dist','build','disassembly'].some(d=>inside(path.join(this.root,d),resolved))) return resolved;
    throw Error('That file is outside the open project.');
  }
  readonly(file) { return !this.files.includes(file) || ['dist','build','disassembly'].some(d=>inside(path.join(this.root,d),file)) || path.basename(file)==='configurations.xml'; }
  read(input) {
    const file = this.allowed(input), data = fs.readFileSync(file);
    if (data.length>8000000 || /\.(elf|o|cof)$/i.test(file)) throw Error('This is a binary or large output file. Use Explorer to inspect it.');
    let content, encoding = 'utf8'; try { content = new TextDecoder('utf-8',{fatal:true}).decode(data); } catch { content = data.toString('latin1'); encoding = 'latin1'; }
    return {path:slash(file),content,encoding,digest:digest(data),readOnly:this.readonly(file)};
  }
  save(input, content, expected, encoding) {
    const file = this.allowed(input); if (this.readonly(file)) throw Error('This generated file is read-only.');
    if (digest(fs.readFileSync(file))!==expected) throw Error('This file changed on disk. Copy your edits or reload it before saving.');
    if (encoding==='latin1' && [...content].some(c=>c.codePointAt(0)>255)) throw Error('This file uses Latin-1. Remove unsupported characters before saving.');
    const data = Buffer.from(content,encoding==='latin1'?'latin1':'utf8'); const tmp = file+'.aster-'+crypto.randomUUID()+'.tmp';
    try { fs.writeFileSync(tmp,data,{flag:'wx'}); fs.renameSync(tmp,file); } finally { fs.rmSync(tmp,{force:true}); }
    return {digest:digest(data)};
  }
  outputs(image) { const files = this.prebuilt ? [this.prebuilt] : ['dist','build'].flatMap(d=>walk(path.join(this.root,d,this.configuration,image||''))); return files.map(p=>({path:slash(p),name:path.basename(p),size:fs.statSync(p).size})); }
  artifact(ext,image) { if (this.prebuilt) { if (path.extname(this.prebuilt).toLowerCase()!=='.'+ext && ext!=='hex') throw Error('Source debugging requires an ELF image.'); return this.prebuilt; } const f=this.outputs(image).find(f=>f.path.endsWith('.'+ext)); if(!f)throw Error('No '+image+' .'+ext+' was produced. Check Output.');return f.path; }
  select(name) { if (!/^[A-Za-z0-9_.-]+$/.test(name) || !this.configurations.some(c=>c.name===name && c.device==='PIC18F87K22')) throw Error('Unsupported project configuration.'); this.configuration=name; }
  saveWatches(names) { if(!Array.isArray(names)||!names.every(n=>symbol.test(n)))throw Error('Use register or assembly symbol names for watches.');this.preferences.set(this.watchKey,[...new Set(names)]); }
  info() { this.refresh();return {name:path.basename(this.prebuilt||this.root).replace(/\.X$/i,''),path:slash(this.root),prebuilt:!!this.prebuilt,configuration:this.configuration,configurations:this.configurations,clockMHz:this.clockMHz,watches:this.preferences.data[this.watchKey]||[],files:this.files.map(p=>({path:slash(p),name:path.basename(p),relative:slash(path.relative(this.root,p)),exists:fs.existsSync(p)})),outputs:this.outputs()}; }
}
// MDB dialogs and command prompts both use a leading >. Preserve partial lines.
class PromptReader {
  constructor(){this.reset();}
  reset(){this.text='';this.lineStart=true;}
  receive(chunk){const result=[];for(const c of chunk){if(c==='>'&&this.lineStart){const message=this.text.trim(),question=message.split(/\r?\n/).at(-1)||'';result.push(/[?]$|\[yes\/no(?:\/cancel)?\]\s*$/i.test(question)?{confirmation:message}:{ready:true});this.reset();}else{this.text+=c;if(c==='\n'||c==='\r')this.lineStart=true;else if(c!==' '&&c!=='\t')this.lineStart=false;}}return result;}
}
class MDBSession {
  constructor(tc,event,confirmation,stop){this.tc=tc;this.event=event;this.confirmation=confirmation;this.onStop=stop;this.reader=new PromptReader();this.running=false;this.locationBuffer='';}
  async start(executable=this.tc.java,args=['-Dfile.encoding=UTF-8','-Djava.awt.headless=true','-jar',this.tc.platform+'/lib/mdb.jar']) {
    this.process=spawn(executable,args,{env:this.tc.environment,windowsHide:true,shell:false});
    this.process.stdout.setEncoding('utf8');this.process.stderr.setEncoding('utf8');
    this.process.stdout.on('data',s=>this.receive(s));this.process.stderr.on('data',s=>this.event('debugOutput',s));
    this.process.on('error',e=>this.fail(e));this.process.on('close',()=>{this.process=null;this.running=false;this.fail(Error('MDB exited. See Debug console.'));});
    await this.wait(25000);
  }
  wait(timeout){return new Promise((resolve,reject)=>{this.pending={resolve,reject};this.timer=setTimeout(()=>{this.fail(Error('MDB timed out. Check tool paths; the session was closed.'));this.stop();},timeout);});}
  fail(error){if(this.pending){clearTimeout(this.timer);this.pending.reject(error);this.pending=null;}}
  receive(s){
    this.event('debugOutput',s);this.buffer=(this.buffer||'')+s;this.locationBuffer=(this.locationBuffer+s).slice(-14000);
    const m=this.locationBuffer.match(/address:\s*(0x[0-9a-f]+)\s*\r?\n\s*file:([^\r\n]+)\s*\r?\n\s*source line:(\d+)/i);
    if(m){this.running=false;this.onStop({address:m[1],file:slash(m[2].trim()),line:Number(m[3])});this.locationBuffer='';}else if(/Target halted/i.test(s))this.running=false;
    for(const prompt of this.reader.receive(s)){
      if(prompt.ready&&this.pending){clearTimeout(this.timer);const p=this.pending;this.pending=null;p.resolve((this.buffer||'').replace(/[>\r\n ]+$/g,'').trim());}
      else if(prompt.confirmation&&this.pending){clearTimeout(this.timer);const p=this.pending;Promise.resolve(this.confirmation(prompt.confirmation)).then(accepted=>{if(this.pending!==p)return;if(!accepted){this.fail(Error('Device operation cancelled; programmer session closed.'));this.stop();return;}this.timer=setTimeout(()=>{this.fail(Error('MDB timed out after confirmation.'));this.stop();},this.commandTimeout||30000);this.process?.stdin.write('yes\n');}).catch(e=>{this.fail(e);this.stop();});}
    }
  }
  async command(line,timeout=30000){safeLine(line);if(!this.process)throw Error('Start debugging first.');if(this.pending)throw Error('A debugger command is already in progress.');this.buffer='';this.reader.reset();this.commandTimeout=timeout;const response=this.wait(timeout);this.process.stdin.write(line+'\n');return response;}
  async checked(line,timeout){const output=await this.command(line,timeout);if(/(^Error:|failed|not supported|not found|does not exist|Unknown command|Invalid command|Unable to|No tool|not connected)/im.test(output))throw Error(output);return output;}
  stop(){this.fail(Error('Debugger session closed.'));const p=this.process;this.process=null;this.running=false;p?.stdin.end();p?.kill();}
}
class IDECore {
  constructor(preferences,event,confirmation){this.preferences=preferences;this.event=event;this.confirmation=confirmation;this.tc=new Toolchain(preferences.data.mplab,preferences.data.xc8);this.runner=new CommandRunner();this.breakpoints=[];this.location={};this.debugTool='SIM';}
  requireProject(){if(!this.project)throw Error('Open or create a project first.');return this.project;}
  open(input){const p=new PICProject(input,this.preferences);this.debugger?.stop();this.debugger=null;this.project=p;this.breakpoints=[];this.location={};return p.info();}
  async build({clean=false,debug=false,tool='SIM'}={}){
    const p=this.requireProject();if(p.prebuilt)throw Error('Open a source project to build.');if(this.debugger)throw Error('Stop debugging before building.');
    const conf=p.configurations.find(c=>c.name===p.configuration);p.select(p.configuration);
    const makefile='nbproject/Makefile-'+p.configuration+'.mk';if(!fs.existsSync(path.join(p.root,makefile)))throw Error('Use Project → Regenerate Makefiles before building.');
    const args=['-f',makefile,clean?'.clean-conf':'.build-conf','SUBPROJECTS=','CONF='+p.configuration];if(debug){args.push('TYPE_IMAGE=DEBUG_RUN');if(!clean)args.push('-B');}
    if(conf.compiler==='pic-as')args.push('MP_AS="'+this.tc.assembler+'" -Wa,-a','MP_LD="'+this.tc.assembler+'"');
    else if(debug&&tool==='PICkit3'&&conf.tool!=='PICkit3')throw Error('Select PICkit 3 in the MPLAB C project configuration first.');
    this.event('buildStart',{clean,debug});const started=Date.now();
    const {code,log}=await this.runner.run(this.tc.make,args,{cwd:p.root,env:this.tc.environment},s=>this.event('buildOutput',s));
    const diagnostics=log.split(/\r?\n/).flatMap(line=>{const m=line.match(/^(.+?):(\d+)(?::(\d*))?:\s*(fatal error|error|warning|note):\s*(.*)$/)||line.match(/^(.+?)\((\d+)\)\s*:\s*(?:(\d+):)?\s*(error|warning|note):?\s*(.*)$/);return m?[{path:slash(path.resolve(p.root,m[1])),line:Number(m[2]),column:Number(m[3])||1,severity:m[4],message:m[5]}]:[];});
    const result={ok:code===0,exitCode:code,elapsed:(Date.now()-started)/1000,log,diagnostics,outputs:p.outputs(),clean};this.event('buildEnd',result);return result;
  }
  async regenerate(){if(this.debugger)throw Error('Stop debugging first.');const p=this.requireProject();const r=await this.runner.run(this.tc.java,['-Djava.awt.headless=true','-jar',this.tc.platform+'/lib/PrjMakefilesGenerator.jar',slash(p.root)],{cwd:p.root,env:this.tc.environment},s=>this.event('buildOutput',s));if(r.code!==0)throw Error(r.log);return r.log;}
  async newSession(){const s=new MDBSession(this.tc,this.event,this.confirmation,loc=>{this.location=loc;this.event('debugStopped',loc);});try{await s.start();return s;}catch(e){s.stop();throw e;}}
  clearBindings(){for(const b of this.breakpoints)delete b.id;}
  async installBreakpoint(s,b){const r=await s.checked('break '+quoteMDB(b.path+':'+b.line));const m=r.match(/Breakpoint\s+(\d+)\s+at/i);if(!m)throw Error('Cannot set breakpoint on that instruction.\n'+r);return Number(m[1]);}
  async startDebug({tool='SIM',index=0,clockMHz,accumulateStopwatch=false}={}){
    if(!['SIM','PICkit3'].includes(tool)||!Number.isInteger(index)||index<0)throw Error('Choose Simulator or PICkit 3.');const p=this.requireProject();this.clockMHz=clockMHz??p.clockMHz;if(!Number.isFinite(this.clockMHz)||this.clockMHz<.001||this.clockMHz>64)throw Error('Enter an oscillator frequency from 0.001 to 64 MHz.');this.accumulate=accumulateStopwatch;
    this.debugger?.stop();this.debugger=null;if(!p.prebuilt&&!(await this.build({debug:true,tool})).ok)throw Error('Fix build errors before debugging.');const elf=p.artifact('elf','debug');this.loadLocalSymbols();this.clearBindings();
    const s=await this.newSession();this.debugger=s;this.debugTool=tool;this.location={};try{
      await s.checked('device PIC18F87K22');if(tool==='SIM'){await s.checked('set oscillator.frequency '+this.clockMHz/4);await s.checked('set oscillator.frequencyunit Mega');}else await s.checked('set poweroptions.powerenable false');
      await s.checked('hwtool '+tool+(tool==='SIM'?'':' '+index),60000);const r=await s.checked('program '+quoteMDB(elf),90000);if(!/program succeeded/i.test(r))throw Error('MDB did not confirm that the image loaded.\n'+r);await s.checked('reset');
      if(tool==='SIM'){await s.checked(accumulateStopwatch?'stopwatch nror':'stopwatch ror');await s.checked('stopwatch clear');}
      for(const b of this.breakpoints)b.id=await this.installBreakpoint(s,b);this.location={address:'0x0000'};this.event('debugState',{state:'paused',tool});return await this.inspect(['WREG','STATUS','BSR','TRISD','LATD','PORTD']);
    }catch(e){s.stop();this.debugger=null;this.clearBindings();this.event('debugState',{state:'disconnected'});throw e;}
  }
  paused(){if(!this.debugger||this.debugger.running)throw Error('Start or pause a debug session first.');return this.debugger;}
  loadLocalSymbols(){this.localSymbols={};const p=this.project;if(p.prebuilt)return;let map='';try{map=fs.readFileSync(p.artifact('map','debug'),'utf8');}catch{return;}
    const candidates={},seen=new Set();for(const m of map.matchAll(/^([^\r\n]+\.o)\s*$/gm)){const object=path.resolve(p.root,m[1].trim());if(!inside(path.join(p.root,'build'),object)||seen.has(object))continue;seen.add(object);let text='',pre='';try{text=fs.readFileSync(object.replace(/\.o$/,'.lst'),'utf8');pre=fs.readFileSync(object.replace(/\.o$/,'.i'),'utf8');}catch{}
      const at=text.lastIndexOf('Symbol Table');if(at<0)continue;const names=new Set([...text.slice(0,at).matchAll(/^\s*\d+\s+[0-9a-f]{4,8}\s+([A-Za-z_][A-Za-z0-9_.$]*)\s*:/gmi),...pre.matchAll(/^\s*([A-Za-z_][A-Za-z0-9_.$]*)\s*:/gm)].map(m=>m[1]));
      for(const name of names){const escaped=name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');const entry=text.slice(at).match(new RegExp('(?:^|\\s)'+escaped+'\\s+([0-9a-fA-F]{4,8})(?=\\s|$)'));if(entry)(candidates[name]??=[]).push(parseInt(entry[1],16));}}
    for(const [name,values]of Object.entries(candidates))if(values.length===1)this.localSymbols[name]=values[0];
  }
  async inspect(names){const s=this.paused();const registers=[];for(const name of names.slice(0,80)){if(!symbol.test(name))continue;const r=await s.command('print /x /datasize:1 '+name);let value=r.split('=').slice(1).join('=').trim()||r;if(/Symbol does not exist/.test(r)&&this.localSymbols?.[name]<0x1000){const raw=await s.command('x /r1xb 0x'+this.localSymbols[name].toString(16));value=raw.match(/^\s*([a-f0-9]{2})\s*$/i)?.[1]||value;}registers.push({name,value});}return {registers,location:this.location,tool:this.debugTool,state:s.running?'running':'paused',breakpoints:this.breakpoints,stopwatch:await this.stopwatch()};}
  async stopwatch(){if(!this.debugger||this.debugTool!=='SIM'||this.debugger.running)return {available:false};try{const r=await this.debugger.checked('stopwatch');const cycles=r.match(/cycle count\s*=\s*([0-9]+)/i)?.[1],elapsed=r.match(/\(([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)\s*(ns|us|µs|μs|ms|s)\)/);if(!cycles||!elapsed)throw Error('The simulator did not return timing.');return {available:true,cycles,seconds:Number(elapsed[1])*({ns:1e-9,us:1e-6,'µs':1e-6,'μs':1e-6,ms:.001,s:1}[elapsed[2]]),elapsedText:elapsed[1]+' '+elapsed[2],clockMHz:this.clockMHz,accumulate:this.accumulate};}catch(e){return {available:false,error:e.message};}}
  async resetStopwatch(){if(this.debugTool!=='SIM')throw Error('Simulator only.');await this.paused().checked('stopwatch clear');return this.stopwatch();}
  async debugAction(action,names=[]){const s=this.debugger;if(!s)throw Error('Start debugging first.');if(action==='stop'){s.stop();this.debugger=null;this.location={};this.clearBindings();this.event('debugState',{state:'disconnected'});return {state:'disconnected',breakpoints:this.breakpoints};}if(!['stepi','step','next','continue','halt','reset'].includes(action))throw Error('Unknown debug action.');if(action!=='halt'&&s.running)throw Error('Pause the target first.');if(action==='continue')s.running=true;try{await s.checked(action);}catch(e){s.running=false;throw e;}if(['halt','reset'].includes(action))s.running=false;if(action==='reset'){this.location={address:'0x0000'};if(this.debugTool==='SIM')await s.checked('stopwatch clear');}this.event('debugState',{state:s.running?'running':'paused',tool:this.debugTool});return s.running?{state:'running'}:this.inspect(names);}
  async breakpoint(input,line){if(this.debugger?.running)throw Error('Pause before changing breakpoints.');const file=slash(this.requireProject().allowed(input));if(!Number.isInteger(line)||line<1)throw Error('Invalid line number.');const i=this.breakpoints.findIndex(b=>b.path===file&&b.line===line);if(i>=0){if(this.debugger&&this.breakpoints[i].id!=null)await this.debugger.checked('delete '+this.breakpoints[i].id);this.breakpoints.splice(i,1);}else{const b={path:file,line};if(this.debugger)b.id=await this.installBreakpoint(this.debugger,b);this.breakpoints.push(b);}return {breakpoints:this.breakpoints};}
  async resolveAddress(input){const s=this.paused();if(/^(0x[0-9a-f]+|[0-9]+)$/i.test(input))return input;if(!symbol.test(input))throw Error('Enter an address or symbol name.');const r=await s.command('print /a '+input);const addr=r.match(/The Address of .+:\s*(0x[0-9a-f]+)/i)?.[1];if(addr)return addr;if(this.localSymbols?.[input]!=null)return '0x'+this.localSymbols[input].toString(16);throw Error('Unable to find a unique address for that symbol.');}
  async pointerAddress(name){const registers={TBLPTR:['TBLPTRL','TBLPTRH','TBLPTRU'],FSR0:['FSR0L','FSR0H']}[name];if(!registers)throw Error('Choose TBLPTR or FSR0.');let address=0;for(const [i,reg]of registers.entries()){const r=await this.paused().checked('print /x /datasize:1 '+reg);const b=r.match(/=\s*(?:0x)?([0-9a-f]{1,2})(?=\s|$)/i)?.[1];if(!b)throw Error('Could not read '+reg);address|=parseInt(b,16)<<(8*i);}return '0x'+address.toString(16);}
  async memory(type,address,count,format='xb'){if(!['r','p','e','c','u','D'].includes(type)||!['xb','i'].includes(format)||!/^(0x[0-9a-f]+|\d+)$/i.test(address)||!Number.isInteger(count)||count<1||count>512)throw Error('Enter a valid address and count between 1 and 512.');return this.paused().checked('x /'+type+count+format+' '+address);}
  async fullDisassembly(){const s=this.paused();const r=await s.checked('x /p65535i 0x0',90000)+'\n0x1FFFE [final flash word; hex bytes] '+await s.checked('x /p2xb 0x1FFFE');const dir=path.join(this.requireProject().root,'disassembly');fs.mkdirSync(dir,{recursive:true});const file=path.join(dir,'full-flash.txt');fs.writeFileSync(file,r);return {path:slash(file)};}
  async writeRegister(name,value){if(!symbol.test(name)||!/^(0x[0-9a-f]{1,2}|\d{1,3})$/i.test(value)||Number(value)>255)throw Error('Use a register name and a byte value (0–255).');const address=await this.resolveAddress(name);return this.paused().checked('write /r '+address+' 0x'+Number(value).toString(16));}
  async setPin(pin,high){if(this.debugTool!=='SIM'||!/^R[A-J][0-7]$/.test(pin))throw Error('Choose a simulator input pin, such as RB0.');const s=this.paused();await s.checked('write pin '+pin+(high?' high':' low'));return s.checked('print pin '+pin);}
  async triggerInterrupt(source){if(this.debugTool!=='SIM')throw Error('Simulator only.');const pair={INT0:['INTCON',2],INT1:['INTCON3',1],INT2:['INTCON3',2],TMR0:['INTCON',4],TMR1:['PIR1',1],TMR2:['PIR1',2],ADC:['PIR1',64]}[source];if(!pair)throw Error('Unknown interrupt source.');const r=await this.paused().checked('print /x '+pair[0]);const v=r.match(/=\s*(?:0x)?([a-f0-9]+)/i)?.[1];if(!v)throw Error('Could not read flag register.');await this.writeRegister(pair[0],'0x'+(parseInt(v,16)|pair[1]).toString(16));return 'Raised '+source+' flag. Step or continue; firmware must enable the interrupt.';}
  async detectTools(){if(this.debugger)return this.debugger.command('hwtool');const s=await this.newSession();try{return await s.command('hwtool');}finally{s.stop();}}
  async program(index=0){if(this.debugger)throw Error('Stop debugging before programming.');if(!Number.isInteger(index)||index<0)throw Error('Invalid tool index.');const p=this.requireProject();if(!p.prebuilt&&!(await this.build()).ok)throw Error('Fix build errors before programming.');const image=p.artifact('hex','production'),s=await this.newSession();try{await s.checked('device PIC18F87K22');await s.checked('set poweroptions.powerenable false');await s.checked('hwtool PICkit3 -p '+index,60000);const log=await s.checked('program '+quoteMDB(image),120000);if(!/program succeeded/i.test(log))throw Error('Programming was not confirmed.\n'+log);return {ok:true,log,image};}finally{s.stop();}}
  shutdown(){this.debugger?.stop();this.runner.cancel();if(this.serial?.isOpen)this.serial.close();}
}
module.exports={copyTree,Preferences,Toolchain,CommandRunner,PICProject,PromptReader,MDBSession,IDECore,digest,quoteMDB,slash,inside};
