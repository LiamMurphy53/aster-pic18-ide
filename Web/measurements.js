(function(root){
 const B64='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
 // helper scope data: base64 little-endian int16, volts = value * scale
 function decode(text,scale){
  const bytes=new Uint8Array(Math.floor(text.replace(/=+$/,'').length*3/4));let bits=0,acc=0,n=0;
  for(const ch of text){const v=B64.indexOf(ch);if(v<0)continue;acc=(acc<<6)|v;bits+=6;if(bits>=8){bits-=8;if(n<bytes.length)bytes[n++]=(acc>>bits)&255;}}
  const out=new Float32Array(bytes.length>>1);for(let i=0;i<out.length;i++){let u=bytes[2*i]|bytes[2*i+1]<<8;if(u&0x8000)u-=0x10000;out[i]=u*scale;}return out;
 }
 // older single-channel captures keep values/channel at the top level; scope traces get raw samples
 function normalize(c){
  if(!c)return c;
  if(!c.traces)c.traces=[{channel:c.channel??0,values:c.values||[],cycles:c.cycles,period:c.period,high:c.high,duty:c.duty}];
  if(c.mode==='scope'){c.dt??=1/c.sampleRate;for(const t of c.traces)if(!t.raw)t.raw=typeof t.data==='string'?decode(t.data,t.scale):Float32Array.from(t.values||[]);}
  return c;
 }
 // scope threshold crossings with hysteresis, interpolated between samples
 function crossings(y,dt,level,hyst){
  const edges=[];let state=null,since=0;
  for(let i=0;i<y.length;i++){
   const next=y[i]>=level+hyst?1:y[i]<=level-hyst?0:state;
   if(state!==null&&next!==state){let j=i;while(j>since+1&&(state?y[j-1]<level:y[j-1]>=level))j--;const a=y[j-1],b=y[j],f=b!==a?(level-a)/(b-a):0;edges.push({t:(j-1+Math.max(0,Math.min(1,f)))*dt,rise:!!next});}
   if(next!==state)since=i;state=next;
  }
  return edges;
 }
 // logic edges keep their sample index so differences are exact sample counts
 function logicEdges(c,t){return (t.values||[]).slice(1).map(([s,level])=>({t:s/c.sampleRate,s,rate:c.sampleRate,rise:!!level}));}
 const gap=(a,b)=>a.s!==undefined&&b.s!==undefined?(b.s-a.s)/a.rate:b.t-a.t;
 // per-trace display data: invert, min/max/average, edge threshold (50% or a level) and edges
 function prepare(c,o={}){
  normalize(c);
  for(const t of c.traces){
   if(c.mode!=='scope'){t.edges=logicEdges(c,t);continue;}
   const inv=!!o.invert?.[t.channel],y=inv?t.raw.map(v=>-v):t.raw;let min=Infinity,max=-Infinity,sum=0;for(const v of y){if(v<min)min=v;if(v>max)max=v;sum+=v;}
   Object.assign(t,{y,inverted:inv,min:y.length?min:0,max:y.length?max:0,avg:y.length?sum/y.length:0});
   t.level=o.threshold?.mode==='level'?o.threshold.level:(t.min+t.max)/2;
   t.edges=t.max-t.min>.05?crossings(y,c.dt,t.level,Math.max(.1*(t.max-t.min),.01)):[];
  }
  return c;
 }
 function trace(c,channel){normalize(c);const t=c?.traces?.find(t=>t.channel===channel)||c?.traces?.[0];return t?{...c,...t}:null;}
 function pulsesFrom(edges){
  const rows=[];let rise=null,fall=null;
  for(const e of edges){if(e.rise){if(rise&&fall){const period=gap(rise,e),high=gap(rise,fall);rows.push({start:rise.t,period,high,duty:100*high/period});}rise=e;fall=null;}else if(rise)fall=e;}
  return rows;
 }
 function pulses(c){if(!c)return [];if(c.edges)return pulsesFrom(c.edges);if(c.mode!=='logic'||!(c.sampleRate>0))return [];return pulsesFrom(logicEdges(c,c));}
 const mean=a=>a.length?a.reduce((s,v)=>s+v,0)/a.length:NaN;
 // 10-90% transition times around each edge, between the average low and high levels
 function transitions(t,dt,rising){
  const y=t.y,mid=(t.min+t.max)/2;let lo=0,hi=0,nl=0,nh=0;for(const v of y)if(v<mid){lo+=v;nl++;}else{hi+=v;nh++;}
  if(!nl||!nh)return NaN;lo/=nl;hi/=nh;const a=lo+.1*(hi-lo),b=lo+.9*(hi-lo),out=[];
  for(const e of t.edges){if(e.rise!==rising)continue;const i=Math.round(e.t/dt);let p=i,q=i;
   while(p>0&&(rising?y[p]>a:y[p]<b))p--;while(q<y.length-1&&(rising?y[q]<b:y[q]>a))q++;
   if(p>0&&q<y.length-1)out.push(Math.max(q-p-1,0)*dt);}
  return mean(out);
 }
 // waveforms-style measurement set for one trace (merged with its capture)
 function measure(t){
  const edges=t.edges||(t.mode==='logic'?logicEdges(t,t):[]),rises=edges.filter(e=>e.rise),rows=pulsesFrom(edges);
  const periods=rises.slice(1).map((r,i)=>gap(rises[i],r)),highs=[],lows=[];
  edges.forEach((e,i)=>{const n=edges[i+1];if(n&&e.rise&&!n.rise)highs.push(gap(e,n));if(n&&!e.rise&&n.rise)lows.push(gap(e,n));});
  const period=mean(periods),high=mean(highs),m={period,frequency:1/period,high,low:mean(lows),duty:100*high/period,cycles:periods.length,edges:edges.length,pulses:rows.length};
  if(t.mode==='scope')Object.assign(m,{rise:transitions(t,t.dt,true),fall:transitions(t,t.dt,false),min:t.min,max:t.max,average:t.avg,peak:t.max-t.min});
  for(const k in m)if(!Number.isFinite(m[k]))m[k]=NaN;return m;
 }
 // same averages as the helper: every rise-to-rise period and every complete high time
 function analyze(c){const m=measure(c);return {cycles:m.cycles,period:m.cycles?m.period:0,high:Number.isFinite(m.high)?m.high:0,duty:m.cycles&&Number.isFinite(m.duty)?m.duty:0};}
 function summary(c){const rows=pulses(c);if(!rows.length)return null;const widths=rows.map(r=>r.high),periods=rows.map(r=>r.period);return {count:rows.length,min:Math.min(...widths),max:Math.max(...widths),periodMin:Math.min(...periods),periodMax:Math.max(...periods)};}
 function csv(c){return 'pulse,start_s,period_s,high_s,duty_percent,sample_rate_hz,channel\n'+pulses(c).map((r,i)=>[i+1,r.start,r.period,r.high,r.duty,c.sampleRate,c.channel].join(',')).join('\n')+'\n';}
 function transitionsCSV(c){
  const rows=c.traces?c.traces.flatMap(t=>(t.values||[]).map(v=>[...v,t.channel])).sort((a,b)=>a[0]-b[0]||a[2]-b[2]):(c.values||[]).map(v=>[...v,c.channel]);
  return 'sample,time_s,logic_level,sample_rate_hz,channel\n'+rows.map(([sample,level,channel])=>[sample,sample/c.sampleRate,level,c.sampleRate,channel].join(',')).join('\n')+'\n';
 }
 function samplesCSV(c){normalize(c);const data=c.traces.map(t=>t.y||t.raw),n=Math.max(...data.map(d=>d.length));return 'time_s,'+c.traces.map(t=>'scope'+(t.channel+1)+'_v').join(',')+'\n'+Array.from({length:n},(_,i)=>[+(i*c.dt).toPrecision(9),...data.map(d=>d[i]===undefined?'':+d[i].toPrecision(6))].join(',')).join('\n')+'\n';}
 // sorted edge times (s) across every trace, for cursor snapping
 function edges(c,rising){normalize(c);return [...new Set(c.traces.flatMap(t=>(t.edges||(c.mode==='logic'?logicEdges(c,t):[])).filter(e=>rising===undefined||e.rise===rising).map(e=>e.t)))].sort((a,b)=>a-b);}
 function nearest(list,t){let lo=0,hi=list.length-1;if(hi<0)return null;while(hi-lo>1){const mid=(lo+hi)>>1;if(list[mid]<t)lo=mid;else hi=mid;}return Math.abs(list[lo]-t)<=Math.abs(list[hi]-t)?list[lo]:list[hi];}
 // next (dir 1) or previous (dir -1) edge strictly beyond t
 function step(list,t,dir){const eps=1e-12;if(dir>0)return list.find(e=>e>t+eps)??null;for(let i=list.length-1;i>=0;i--)if(list[i]<t-eps)return list[i];return null;}
 // logic level or interpolated voltage of one trace at time t
 function valueAt(c,t,time){
  if(c.mode==='logic'){const v=t.values||[];if(!v.length)return null;const s=time*c.sampleRate;let lo=0,hi=v.length-1;if(s<v[0][0])return null;while(lo<hi){const mid=(lo+hi+1)>>1;if(v[mid][0]<=s)lo=mid;else hi=mid-1;}return v[lo][1];}
  const y=t.y||t.raw||t.values||[],x=time/c.dt,i=Math.floor(x);if(i<0||i>=y.length)return null;return i+1<y.length?y[i]+(y[i+1]-y[i])*(x-i):y[i];
 }
 function niceStep(span,divisions=8){const raw=span/divisions,p=Math.pow(10,Math.floor(Math.log10(raw))),m=raw/p;return (m<=1?1:m<=2?2:m<=5?5:10)*p;}
 function unit(abs){return abs<1e-6?[1e9,'ns']:abs<1e-3?[1e6,'µs']:abs<1?[1e3,'ms']:[1,'s'];}
 const places=(res,k)=>Math.max(0,Math.min(9,Math.ceil(-Math.log10(res*k)-1e-9)));
 // readouts: with res (s) the last digit matches the real resolution; otherwise µs 3, ms 4, s 5 decimals
 function time(t,res){if(!Number.isFinite(t))return '—';const [k,u]=unit(Math.abs(t)||res||1);return (t*k).toFixed(res?places(res,k):u==='ns'?1:u==='µs'?3:u==='ms'?4:5)+' '+u;}
 // axis labels: decimals from the tick step
 function tick(t,step,ref=Math.abs(t)){const [k,u]=unit(Math.max(ref,step));const d=Math.max(0,Math.min(6,-Math.floor(Math.log10(step*k)+1e-9)));return (t*k).toFixed(d)+' '+u;}
 // res is the time resolution behind f (frequency uncertainty f²·res)
 function frequency(f,res){if(!Number.isFinite(f)||f<=0)return '—';const [k,u]=f>=1e6?[1e-6,'MHz']:f>=1e3?[1e-3,'kHz']:[1,'Hz'];return (f*k).toFixed(res?places(f*f*res,k):u==='Hz'?3:4)+' '+u;}
 function volts(v,res){if(!Number.isFinite(v))return '—';const mv=Math.abs(v)<1&&(!res||res<.01);return mv?(v*1000).toFixed(res?places(res,1000):1)+' mV':v.toFixed(res?places(res,1):3)+' V';}
 function percent(v,res){return Number.isFinite(v)?v.toFixed(res?places(res,1):2)+'%':'—';}
 const api={decode,normalize,crossings,prepare,trace,pulses,measure,analyze,summary,csv,transitionsCSV,samplesCSV,edges,nearest,step,valueAt,niceStep,time,tick,frequency,volts,percent};if(typeof module!=='undefined')module.exports=api;else root.AsterMeasurements=api;
})(globalThis);
