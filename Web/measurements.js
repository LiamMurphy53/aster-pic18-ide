(function(root){
 // older single-channel captures keep values/channel at the top level
 function normalize(c){
  if(!c||c.traces)return c;
  c.traces=[{channel:c.channel??0,values:c.values||[],cycles:c.cycles,period:c.period,high:c.high,duty:c.duty}];return c;
 }
 function trace(c,channel){normalize(c);const t=c?.traces?.find(t=>t.channel===channel)||c?.traces?.[0];return t?{...c,...t}:null;}
 function pulses(c){
  if(c?.mode!=='logic'||!(c.sampleRate>0))return [];
  const rows=[];let rise=null,fall=null,previous=null;
  for(const [sample,level] of c.values||[]){
   if(previous===0&&level===1){if(rise!==null&&fall!==null){const period=(sample-rise)/c.sampleRate,high=(fall-rise)/c.sampleRate;rows.push({start:rise/c.sampleRate,period,high,duty:100*high/period});}rise=sample;fall=null;}
   if(previous===1&&level===0&&rise!==null)fall=sample;
   previous=level;
  }
  return rows;
 }
 // same averages as the helper: every rise-to-rise period and every complete high time
 function analyze(c){
  if(c?.mode!=='logic')return {cycles:c?.cycles||0,period:c?.period||0,high:c?.high||0,duty:c?.duty||0};
  let rise=null,periods=0,periodSum=0,highs=0,highSum=0,previous=null;
  for(const [sample,level] of c.values||[]){if(previous===0&&level===1){if(rise!==null){periodSum+=sample-rise;periods++;}rise=sample;}if(previous===1&&level===0&&rise!==null){highSum+=sample-rise;highs++;}previous=level;}
  const period=periods?periodSum/periods/c.sampleRate:0,high=highs?highSum/highs/c.sampleRate:0;
  return {cycles:periods,period,high,duty:period>0&&high>0?100*high/period:0};
 }
 function summary(c){const rows=pulses(c);if(!rows.length)return null;const widths=rows.map(r=>r.high),periods=rows.map(r=>r.period);return {count:rows.length,min:Math.min(...widths),max:Math.max(...widths),periodMin:Math.min(...periods),periodMax:Math.max(...periods)};}
 function csv(c){return 'pulse,start_s,period_s,high_s,duty_percent,sample_rate_hz,channel\n'+pulses(c).map((r,i)=>[i+1,r.start,r.period,r.high,r.duty,c.sampleRate,c.channel].join(',')).join('\n')+'\n';}
 function transitionsCSV(c){
  const rows=c.traces?c.traces.flatMap(t=>(t.values||[]).map(v=>[...v,t.channel])).sort((a,b)=>a[0]-b[0]||a[2]-b[2]):(c.values||[]).map(v=>[...v,c.channel]);
  return 'sample,time_s,logic_level,sample_rate_hz,channel\n'+rows.map(([sample,level,channel])=>[sample,sample/c.sampleRate,level,c.sampleRate,channel].join(',')).join('\n')+'\n';
 }
 function samplesCSV(c){normalize(c);const n=Math.max(...c.traces.map(t=>t.values.length));return 'time_s,'+c.traces.map(t=>'scope'+(t.channel+1)+'_v').join(',')+'\n'+Array.from({length:n},(_,i)=>[i*c.dt,...c.traces.map(t=>t.values[i]??'')].join(',')).join('\n')+'\n';}
 // sorted edge times (s) across every logic trace, for cursor snapping
 function edges(c){normalize(c);if(c?.mode!=='logic')return [];return [...new Set(c.traces.flatMap(t=>(t.values||[]).slice(1).map(v=>v[0])))].sort((a,b)=>a-b).map(s=>s/c.sampleRate);}
 function nearest(list,t){let lo=0,hi=list.length-1;if(hi<0)return null;while(hi-lo>1){const mid=(lo+hi)>>1;if(list[mid]<t)lo=mid;else hi=mid;}return Math.abs(list[lo]-t)<=Math.abs(list[hi]-t)?list[lo]:list[hi];}
 // logic level or interpolated voltage of one trace at time t
 function valueAt(c,t,time){
  const v=t.values||[];if(!v.length)return null;
  if(c.mode==='logic'){const s=time*c.sampleRate;let lo=0,hi=v.length-1;if(s<v[0][0])return null;while(lo<hi){const mid=(lo+hi+1)>>1;if(v[mid][0]<=s)lo=mid;else hi=mid-1;}return v[lo][1];}
  const x=time/c.dt,i=Math.floor(x);if(i<0||i>=v.length)return null;return i+1<v.length?v[i]+(v[i+1]-v[i])*(x-i):v[i];
 }
 function niceStep(span,divisions=8){const raw=span/divisions,p=Math.pow(10,Math.floor(Math.log10(raw))),m=raw/p;return (m<=1?1:m<=2?2:m<=5?5:10)*p;}
 function unit(abs){return abs<1e-6?[1e9,'ns']:abs<1e-3?[1e6,'µs']:abs<1?[1e3,'ms']:[1,'s'];}
 // readouts: µs with 3 decimals, ms with 4, s with 5
 function time(t){if(!Number.isFinite(t))return '—';const [k,u]=unit(Math.abs(t)||1);return (t*k).toFixed(u==='ns'?1:u==='µs'?3:u==='ms'?4:5)+' '+u;}
 // axis labels: decimals from the tick step
 function tick(t,step,ref=Math.abs(t)){const [k,u]=unit(Math.max(ref,step));const d=Math.max(0,Math.min(6,-Math.floor(Math.log10(step*k)+1e-9)));return (t*k).toFixed(d)+' '+u;}
 function frequency(f){if(!Number.isFinite(f)||f<=0)return '—';return f>=1e6?(f/1e6).toFixed(4)+' MHz':f>=1e3?(f/1e3).toFixed(4)+' kHz':f.toFixed(3)+' Hz';}
 function volts(v){return Number.isFinite(v)?(Math.abs(v)<1?(v*1000).toFixed(1)+' mV':v.toFixed(3)+' V'):'—';}
 const api={normalize,trace,pulses,analyze,summary,csv,transitionsCSV,samplesCSV,edges,nearest,valueAt,niceStep,time,tick,frequency,volts};if(typeof module!=='undefined')module.exports=api;else root.AsterMeasurements=api;
})(globalThis);
