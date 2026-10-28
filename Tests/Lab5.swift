import Foundation
@main struct Lab5Check {
 static func main() throws {
  setbuf(stdout,nil)
  let base=URL(fileURLWithPath:CommandLine.arguments[1]),fm=FileManager.default,core=IDECore()
  let root=base.appendingPathComponent("Tests/Lab5Check-"+UUID().uuidString+".X")
  defer { core.shutdown();try? fm.removeItem(at:root) }
  try fm.copyItem(at:base.appendingPathComponent("Resources/CTemplate.X"),to:root)
  let source="""
  #include <xc.h>
  #pragma config FOSC=HS1, PWRTEN=ON, BOREN=ON, BORV=2, PLLCFG=OFF
  #pragma config WDTEN=OFF, CCP2MX=PORTC, XINST=OFF
  volatile unsigned int Alive_count = 0;
  void __interrupt(low_priority) LoPriISR(void) {
      if (INTCONbits.TMR0IF) {
          Alive_count++;
          INTCONbits.TMR0IF = 0;
      }
  }
  void main(void) {
      Alive_count = 0x1234;
      RCONbits.IPEN=1;
      INTCON2bits.TMR0IP=0;
      INTCONbits.TMR0IE=1;
      INTCONbits.GIEL=1;
      INTCONbits.GIEH=1;
      while(1) { asm("nop"); }
  }
  """
  let file=root.appendingPathComponent("main.c")
  try source.write(to:file,atomically:true,encoding:.utf8)
  _ = try core.open(root.path)
  let project=try core.requireProject()
  let header=try project.addSource("timer_support.h"),helper=try project.addSource("timer_support.c")
  try "unsigned int initial_count(void);\n".write(to:header,atomically:true,encoding:.utf8)
  try "#include \"timer_support.h\"\nunsigned int initial_count(void) { return 0x1234; }\n".write(to:helper,atomically:true,encoding:.utf8)
  let main=source.replacingOccurrences(of:"#include <xc.h>",with:"#include <xc.h>\n#include \"timer_support.h\"").replacingOccurrences(of:"Alive_count = 0x1234;",with:"Alive_count = initial_count();")
  try main.write(to:file,atomically:true,encoding:.utf8)
  for bad in ["../escape.c","main.c","timer_support.c","bad name.c"] {
      do {_ = try project.addSource(bad);throw IDEError("Accepted invalid filename")}catch let e as IDEError {precondition(e.message != "Accepted invalid filename")}
  }
  _ = try core.regenerate()
  let generated=root.appendingPathComponent("nbproject/Makefile-default.mk"),beforeDebug=try Data(contentsOf:root.appendingPathComponent("nbproject/Makefile-default.mk"))
  let hardware=try core.build(debug:true,tool:"PICkit3")
  let afterDebug=try Data(contentsOf:generated);precondition(beforeDebug == afterDebug,"Debug build restores generated makefile")
  precondition(hardware["ok"] as? Bool == true,"\(hardware)")
  precondition((hardware["log"] as? String)?.lowercased().contains("-mdebugger=pickit3") == true)
  print("PASS multiple C files link and PICkit 3 C debug flags are generated")
  let build=try core.build();precondition(build["ok"] as? Bool == true,"\(build)");print("PASS C production build")
  let line=main.components(separatedBy:"\n").firstIndex{$0.contains("while(1)")}!+1
  _ = try core.breakpoint(path:file.path,line:line)
  _ = try core.startDebug(tool:"SIM"); _ = try core.debugAction("continue",names:[])
  for _ in 0..<100 { if core.debugger?.running == false {break};Thread.sleep(forTimeInterval:0.05) }
  precondition(core.debugger?.running == false)
  let watched=try core.inspect(["Alive_count"]);precondition((watched["registers"] as? [[String:String]])?.first?["value"] == "0x1234")
  print("PASS full-width XC8 unsigned int watch")
  _ = try core.writeRegister(name:"PIR3",value:"0x80")
  _ = try core.triggerInterrupt("CCP1");let ccp1=try core.inspect(["PIR3"]);precondition((ccp1["registers"] as? [[String:String]])?.first?["value"] == "82")
  _ = try core.triggerInterrupt("CCP2");let ccp2=try core.inspect(["PIR3"]);precondition((ccp2["registers"] as? [[String:String]])?.first?["value"] == "86");print("PASS CCP1/CCP2 flags preserve other PIR3 bits")
  _ = try core.triggerInterrupt("TMR0")
  _ = try core.breakpoint(path:file.path,line:line)
  let handler=main.components(separatedBy:"\n").firstIndex{$0.contains("Alive_count++")}!+1
  _ = try core.breakpoint(path:file.path,line:handler)
  _ = try core.debugAction("continue",names:[])
  for _ in 0..<100 { if core.debugger?.running == false {break};Thread.sleep(forTimeInterval:0.05) }
  precondition(core.lastLocation["line"] as? Int == handler)
  print("PASS C timer interrupt reaches low-priority ISR")
  _ = try core.debugAction("stop",names:[])
  if CommandLine.arguments.count > 2 {
   let assembly=root.deletingLastPathComponent().appendingPathComponent("Lab5Assembly-"+UUID().uuidString+".X")
   defer {core.shutdown();try? fm.removeItem(at:assembly)}
   try fm.copyItem(at:base.appendingPathComponent("Resources/Template.X"),to:assembly)
   let starter=URL(fileURLWithPath:CommandLine.arguments[2]).appendingPathComponent("lab5a_orig.asm")
   try fm.removeItem(at:assembly.appendingPathComponent("main.asm"))
   try fm.copyItem(at:starter,to:assembly.appendingPathComponent("main.asm"))
   _ = try core.open(assembly.path)
   _ = try core.regenerate()
   let built=try core.build();precondition(built["ok"] as? Bool == true,"\(built)")
   _ = try core.startDebug(tool:"SIM")
   let regs=try core.inspect(["TMR1X","CCPR1X","DTIMEX","CCPTMRS0","PIR3"])
   precondition((regs["registers"] as? [[String:String]])?.allSatisfy { $0["value"]?.range(of:"^[0-9a-fA-F]{1,2}$",options:.regularExpression) != nil } == true)
   print("PASS unmodified course assembly production/debug build and extension-byte watches")
  }
 }
}
