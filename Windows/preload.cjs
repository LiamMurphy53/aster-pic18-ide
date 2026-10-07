'use strict';
const { contextBridge, ipcRenderer } = require('electron');
// Keep the existing WKWebView message contract, with no Node APIs in the page.
contextBridge.exposeInMainWorld('webkit', {messageHandlers:{aster:{postMessage:async message=>{
  if(!message || typeof message.id!=='string' || typeof message.op!=='string')return;
  try{const value=await ipcRenderer.invoke('aster:request',message.op,message.args||{});windowResponse(message.id,value,'');}
  catch(e){windowResponse(message.id,null,e.message.replace(/^Error invoking remote method '[^']+': (?:Error: )?/,''));}
}}}});
function windowResponse(id,value,error){ipcRenderer.send('aster:response',{id,value,error});}
