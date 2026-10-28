// Shared by the desktop editor and regression tests.
(function(root){
 const canonical=(name,defs)=>{name=name.toUpperCase();return defs.find(d=>d.name===name||(d.aliases||[]).includes(name))?.name||name;};
 // Mask comments without moving offsets, including commented-out directives.
 function masked(source){return source.replace(/\/\*[\s\S]*?\*\/|\/\/[^\r\n]*|;[^\r\n]*/g,s=>s.replace(/[^\r\n]/g,' '));}
 function statements(source){return [...masked(source).matchAll(/^[ \t]*(?:#pragma[ \t]+config|CONFIG)[ \t]+([^\r\n]+)/gim)];}
 function read(source,defs){const values={};for(const line of statements(source))for(const m of line[1].matchAll(/\b(\w+)\s*=\s*(\w+)/g))values[canonical(m[1],defs)]=m[2].toUpperCase();return values;}
 function apply(source,selected,removed,defs,directive){
  const found=new Set();
  for(const line of statements(source).reverse()){
   const offset=line.index+line[0].indexOf(line[1]);
   const original=source.slice(offset,offset+line[1].length);
   // Preserve trailing comments and spacing while editing individual assignments.
   const fields=[],comments=[];let start=0;
   const bounds=[...line[1].matchAll(/,/g)].map(m=>m.index);bounds.push(line[1].length);
   for(const end of bounds){
    let text=original.slice(start,end);const code=line[1].slice(start,end),m=/\b(\w+)\s*=\s*(\w+)/.exec(code);start=end+1;
    if(!m){if(text.trim())fields.push(text);continue;}
    const key=canonical(m[1],defs);found.add(key);
    if(removed.has(key)){
     const remaining=text.slice(0,m.index)+text.slice(m.index+m[0].length);
     if(remaining.trim())comments.push(remaining.trim());
    }else{
     if(Object.hasOwn(selected,key))text=text.slice(0,m.index)+m[0].replace(/\w+$/,selected[key])+text.slice(m.index+m[0].length);
     fields.push(text);
    }
   }
   const replacement=(fields.length?source.slice(line.index,offset)+fields.join(','):'')+(comments.length?' '+comments.join(' '):'');
   source=source.slice(0,line.index)+replacement+source.slice(offset+line[1].length);
  }
  const added=Object.entries(selected).filter(([key])=>!found.has(key)).map(([k,v])=>`${directive} ${k} = ${v}`);
  if(added.length)source=added.join('\n')+'\n'+source;
  return source;
 }
 const api={read,apply};if(typeof module!=='undefined')module.exports=api;else root.AsterConfig=api;
})(globalThis);
