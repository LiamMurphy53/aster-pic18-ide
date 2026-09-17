import {EditorState, StateEffect, StateField, Compartment} from '@codemirror/state';
import {EditorView, keymap, lineNumbers, highlightActiveLineGutter, highlightActiveLine, drawSelection, rectangularSelection, crosshairCursor, gutter, GutterMarker, Decoration} from '@codemirror/view';
import {defaultKeymap, history, historyKeymap, indentWithTab} from '@codemirror/commands';
import {searchKeymap, highlightSelectionMatches, openSearchPanel} from '@codemirror/search';
import {autocompletion, completionKeymap, closeBrackets, closeBracketsKeymap} from '@codemirror/autocomplete';
import {StreamLanguage, HighlightStyle, syntaxHighlighting, bracketMatching, indentOnInput, foldGutter, foldKeymap} from '@codemirror/language';
import {tags} from '@lezer/highlight';
import {cpp} from '@codemirror/lang-cpp';

const instructions='ADDLW ADDWF ADDWFC ANDLW ANDWF BC BCF BN BNC BNN BNOV BNZ BOV BRA BSF BTFSC BTFSS BTG BZ CALL CLRF CLRWDT COMF CPFSEQ CPFSGT CPFSLT DAW DCFSNZ DECF DECFSZ GOTO INCF INCFSZ INFSNZ IORLW IORWF LFSR MOVF MOVFF MOVLB MOVLW MOVWF MULLW MULWF NEGF NOP POP PUSH RCALL RESET RETFIE RETLW RETURN RLCF RLNCF RRCF RRNCF SETF SLEEP SUBFWB SUBLW SUBWF SUBWFB SWAPF TBLRD TBLWT TSTFSZ XORLW XORWF'.split(' ');
const directives='PROCESSOR CONFIG PSECT END EQU SET DS DB DW ORG BANKSEL BANKMASK GLOBAL EXTRN MACRO ENDM IF IFDEF IFNDEF ELSE ENDIF REPT ENDR INCLUDE RADIX'.split(' ');
const asm=StreamLanguage.define({startState:()=>({comment:false}),token(stream,state){
  if(state.comment){if(stream.skipTo('*/')){stream.match('*/');state.comment=false;}else stream.skipToEnd();return 'comment';}
  if(stream.eatSpace())return null;
  if(stream.match('/*')){state.comment=true;return 'comment';}
  if(stream.match('//')||stream.match(';')){stream.skipToEnd();return 'comment';}
  if(stream.match(/^#[A-Za-z]+/))return 'meta';
  if(stream.match(/^(?:"[^"\n]*"|'[^'\n]*')/))return 'string';
  if(stream.match(/^(?:0x[\da-f]+|0b[01]+|\d+[hHbBdD]?|[\da-f]+h\b)/i))return 'number';
  if(stream.match(/^[A-Za-z_.$][\w.$]*/)){const t=stream.current().toUpperCase();if(stream.peek()===':')return 'labelName';if(instructions.includes(t))return 'keyword';if(directives.includes(t))return 'meta';if(/^(WREG|STATUS|BSR|PORT[A-J]|LAT[A-J]|TRIS[A-J]|[AWFB])$/.test(t))return 'variableName';return 'name';}
  stream.next();return null;
},languageData:{commentTokens:{line:';'}}});
const theme=EditorView.theme({
 '&':{height:'100%',color:'#d6dde7',backgroundColor:'#10151c',fontSize:'13px'},
 '.cm-content':{fontFamily:'"SFMono-Regular", Menlo, monospace',padding:'18px 0',caretColor:'#89e8c5'},
 '.cm-line':{padding:'0 22px 0 8px',lineHeight:'1.75'},
 '.cm-scroller':{fontFamily:'"SFMono-Regular", Menlo, monospace',overflow:'auto'},
 '.cm-gutters':{backgroundColor:'#10151c',color:'#536171',border:'none',padding:'0 0 0 10px'},
 '.cm-lineNumbers .cm-gutterElement':{minWidth:'35px',padding:'0 8px'},
 '.cm-activeLine,.cm-activeLineGutter':{backgroundColor:'#ffffff04'},
 '&.cm-focused .cm-selectionBackground,.cm-selectionBackground':{backgroundColor:'#6fa68e35'},
 '.cm-cursor':{borderLeftColor:'#9eebc9'},
 '.cm-panels':{backgroundColor:'#19222c',color:'#dae3ef'},
 '.cm-textfield':{backgroundColor:'#10151c',border:'1px solid #354450',borderRadius:'4px'},
 '.cm-button':{backgroundImage:'none',backgroundColor:'#24313a',color:'#d8e1eb',border:'1px solid #354450'},
 '.cm-tooltip':{backgroundColor:'#1a2430',border:'1px solid #354450',borderRadius:'6px'},
 '.cm-tooltip-autocomplete > ul > li[aria-selected]':{backgroundColor:'#2d5047',color:'#baf4df'},
 '.cm-breakpoint':{color:'#ef817f',fontSize:'10px',width:'14px',textAlign:'center'},
 '.cm-breakpoint-gutter':{width:'16px',cursor:'pointer'},
 '.cm-execution':{backgroundColor:'#89e8c516',boxShadow:'inset 2px 0 #89e8c5'},
 '.cm-problem-line':{backgroundColor:'#e6746b0c'},
 '.cm-foldGutter':{width:'12px'},
 '&.cm-focused':{outline:'none'},
},{dark:true});
const syntax=HighlightStyle.define([{tag:tags.keyword,color:'#9bc8fa'},{tag:tags.meta,color:'#c7adf3'},{tag:tags.comment,color:'#697d80'},{tag:tags.number,color:'#efc78c'},{tag:tags.string,color:'#a9d9a6'},{tag:tags.variableName,color:'#d4e1ea'},{tag:tags.labelName,color:'#8ee0c3'}]);
class Dot extends GutterMarker{toDOM(){let e=document.createElement('span');e.className='cm-breakpoint';e.textContent='●';return e;}}
const dot=new Dot(),setMarks=StateEffect.define();
const marks=StateField.define({create:()=>({breaks:[],execution:0,errors:[]}),update(v,tr){for(const e of tr.effects)if(e.is(setMarks))return e.value;return v;}});
const decorations=EditorView.decorations.compute([marks],state=>{const m=state.field(marks),all=[];if(m.execution>0&&m.execution<=state.doc.lines)all.push(Decoration.line({class:'cm-execution'}).range(state.doc.line(m.execution).from));for(const n of m.errors)if(n>0&&n<=state.doc.lines)all.push(Decoration.line({class:'cm-problem-line'}).range(state.doc.line(n).from));return Decoration.set(all,true);});
let view,activePath='',states=new Map(),device=[],callbacks={},readonly=new Compartment(),language=new Compartment();
function completions(ctx){const word=ctx.matchBefore(/[\w.]+/);if(!word||(word.from===word.to&&!ctx.explicit))return null;return {from:word.from,options:[...instructions.map(label=>({label,type:'keyword',detail:'PIC18 instruction'})),...directives.map(label=>({label,type:'keyword',detail:'pic-as directive'})),...device.map(r=>({label:r.name,type:'variable',detail:r.address,info:r.description||r.bits.join(' · ')}))]};}
function makeState(content,path,readOnly){return EditorState.create({doc:content,extensions:[lineNumbers(),highlightActiveLineGutter(),history(),drawSelection(),rectangularSelection(),crosshairCursor(),highlightActiveLine(),highlightSelectionMatches(),indentOnInput(),bracketMatching(),closeBrackets(),foldGutter(),language.of(/\.(c|h|cpp)$/.test(path)?cpp():asm),theme,syntaxHighlighting(syntax),readonly.of(EditorState.readOnly.of(readOnly)),autocompletion({override:[completions]}),keymap.of([{key:'Mod-s',run:()=>{callbacks.save?.();return true;}},...closeBracketsKeymap,...defaultKeymap,...searchKeymap,...historyKeymap,...completionKeymap,...foldKeymap,indentWithTab]),EditorState.tabSize.of(4),marks,decorations,gutter({class:'cm-breakpoint-gutter',lineMarker:(v,line)=>v.state.field(marks).breaks.includes(v.state.doc.lineAt(line.from).number)?dot:null,domEventHandlers:{mousedown:(v,line,event)=>{event.preventDefault();callbacks.breakpoint?.(activePath,v.state.doc.lineAt(line.from).number);return true;}}}),EditorView.updateListener.of(update=>{if(update.docChanged)callbacks.change?.(activePath,update.state.doc.toString());if(update.selectionSet||update.docChanged){const pos=update.state.selection.main.head,line=update.state.doc.lineAt(pos);callbacks.cursor?.(line.number,pos-line.from+1);}})]});}
window.AsterEditor={
 init(parent,options){callbacks=options;view=new EditorView({parent,state:makeState('','',true)});},
 setDevice(regs){device=regs;},
 open(path,content,readOnly=false){if(activePath)states.set(activePath,view.state);activePath=path;view.setState(states.get(path)||makeState(content,path,readOnly));view.dispatch({effects:readonly.reconfigure(EditorState.readOnly.of(readOnly))});},
 close(path){states.delete(path);if(activePath===path)activePath='';},
 content:()=>view.state.doc.toString(),
 replace(content){view.dispatch({changes:{from:0,to:view.state.doc.length,insert:content}});},
 go(line,column=1){const l=view.state.doc.line(Math.max(1,Math.min(line,view.state.doc.lines))),pos=Math.min(l.to,l.from+column-1);view.dispatch({selection:{anchor:pos},effects:EditorView.scrollIntoView(pos,{y:'center'})});view.focus();},
 marks(breaks=[],execution=0,errors=[]){view.dispatch({effects:setMarks.of({breaks,execution,errors})});},
 readOnly(value){view.dispatch({effects:readonly.reconfigure(EditorState.readOnly.of(value))});},
 find(){openSearchPanel(view);},
 focus(){view.focus();},
 reset(){states.clear();activePath='';view.setState(makeState('','',true));}
};
