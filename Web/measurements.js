(function(root){
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
 function summary(c){const rows=pulses(c);if(!rows.length)return null;const widths=rows.map(r=>r.high),periods=rows.map(r=>r.period);return {count:rows.length,min:Math.min(...widths),max:Math.max(...widths),periodMin:Math.min(...periods),periodMax:Math.max(...periods)};}
 function csv(c){return 'pulse,start_s,period_s,high_s,duty_percent,sample_rate_hz,channel\n'+pulses(c).map((r,i)=>[i+1,r.start,r.period,r.high,r.duty,c.sampleRate,c.channel].join(',')).join('\n')+'\n';}
 function transitionsCSV(c){return 'sample,time_s,logic_level,sample_rate_hz,channel\n'+(c.values||[]).map(([sample,level])=>[sample,sample/c.sampleRate,level,c.sampleRate,c.channel].join(',')).join('\n')+'\n';}
 const api={pulses,summary,csv,transitionsCSV};if(typeof module!=='undefined')module.exports=api;else root.AsterMeasurements=api;
})(globalThis);
