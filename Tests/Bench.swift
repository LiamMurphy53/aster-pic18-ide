import Foundation
@main struct BenchTests {
 static func main() throws {
  let base=URL(fileURLWithPath:CommandLine.arguments[1]),core=IDECore()
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("aster-bench-"+UUID().uuidString).appendingPathExtension("X")
  defer {core.shutdown();try? FileManager.default.removeItem(at:root)}
  try FileManager.default.copyItem(at:base.appendingPathComponent("Resources/Template.X"),to:root)
  _ = try core.open(root.path)
  _ = try core.startDebug(tool:"SIM")
  let numeric=try core.resolveAddress("0x20")
  precondition(numeric == "0x20")
  let address=try core.resolveAddress("WREG")
  precondition(address.lowercased().hasPrefix("0x"))
  do {_ = try core.resolveAddress("bad; command");fatalError("Accepted invalid symbol")}catch{}
  _ = try core.writeRegister(name:"TRISE",value:"0xff")
  let high=try core.setPin("RE3",high:true)
  precondition(high.uppercased().contains("HIGH"))
  let low=try core.setPin("RE3",high:false)
  precondition(low.uppercased().contains("LOW"))
  let inspection=try core.inspect(["T0CON","TMR0H","TMR0L","TBLPTRU","TABLAT"])
  precondition((inspection["registers"] as? [[String:Any]])?.count == 5)
  let memory=try core.memory(type:"p",address:"0x0",count:32)
  precondition(!memory.isEmpty)
  print("PASS: symbol resolution, RE3 high/low, timer/table watches, program memory")
  let result=try core.fullDisassembly()
  let file=try core.requireProject().read(result["path"] as! String)
  let text=file["content"] as! String
  precondition(text.lowercased().contains("goto") && text.contains("0x1FFFE   [final flash word; hex bytes]"))
  precondition(file["readOnly"] as? Bool == true)
  print("PASS: full disassembly opens read-only (\(text.count) characters)")
 }
}
