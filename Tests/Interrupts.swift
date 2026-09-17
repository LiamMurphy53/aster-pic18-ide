import Foundation
@main struct InterruptTests {
    static func main() throws {
        setbuf(stdout,nil)
        let core = IDECore(); var checks: [[String:Any]] = []
        let base = URL(fileURLWithPath:CommandLine.arguments[1])
        defer { core.shutdown(); try? JSONSerialization.data(withJSONObject:checks,options:.prettyPrinted).write(to:base.appendingPathComponent("Tests/interrupt-result.json")) }
        func check(_ name: String, _ ok: Bool) throws { checks.append(["name":name,"ok":ok]); print("\(ok ? "PASS" : "FAIL") \(name)"); if !ok { throw IDEError(name) } }
        do {
            let dest=base.appendingPathComponent("Tests/InterruptProject.X")
            if FileManager.default.fileExists(atPath:dest.path) { try FileManager.default.removeItem(at:dest) }
            try FileManager.default.copyItem(at:base.appendingPathComponent("Resources/InterruptTemplate.X"),to:dest)
            let path=dest.appendingPathComponent("main.asm").path
            let source=try String(contentsOfFile:path,encoding:.utf8)
            func line(_ text: String) -> Int { source.components(separatedBy:"\n").firstIndex{$0.contains(text)}!+1 }
            _ = try core.open(dest.path)
            core.onEvent = {name,data in if name == "debugStopped" { print("STOP \(jsonString(data))") } }
            _ = try core.breakpoint(path:path,line:line("nop     ; idle loop"))
            try check("Queues a breakpoint before debugging",core.breakpoints.count == 1 && core.breakpoints[0]["id"] == nil)
            _ = try core.startDebug(tool:"SIM")
            try check("Installs queued breakpoint in simulator",core.breakpoints[0]["id"] as? Int != nil)
            _ = try core.debugAction("continue",names:["WREG"])
            Thread.sleep(forTimeInterval:0.3)
            try check("Stops after interrupt initialization",core.lastLocation["line"] as? Int == line("nop     ; idle loop"))
            _ = try core.breakpoint(path:path,line:line("nop     ; idle loop"))
            _ = try core.breakpoint(path:path,line:line("incf    irq_count"))
            print(try core.triggerInterrupt("INT0"))
            _ = try core.debugAction("continue",names:["INTCON"])
            Thread.sleep(forTimeInterval:0.3)
            try check("Injected INT0 reaches the actual ISR",core.lastLocation["line"] as? Int == line("incf    irq_count"))
            _ = try core.debugAction("stepi",names:["irq_count"])
            let count=try core.inspect(["irq_count"])
            try check("Steps through ISR and updates interrupt counter",(count["registers"] as? [[String:String]])?.first?["value"] == "01")
            _ = try core.breakpoint(path:path,line:line("incf    irq_count"))
            _ = try core.debugAction("continue",names:[])
            Thread.sleep(forTimeInterval:0.1)
            let halted = try core.debugAction("halt",names:["INTCON"])
            try check("Pause interrupts an otherwise infinite running loop",halted["state"] as? String == "paused")
            print(try core.setPin("RB0",high:false))
            _ = try core.debugAction("stepi",names:[])
            _ = try core.breakpoint(path:path,line:line("incf    irq_count"))
            print(try core.setPin("RB0",high:true))
            _ = try core.debugAction("continue",names:[])
            Thread.sleep(forTimeInterval:0.4)
            if core.debugger?.running == true { _ = try core.debugAction("halt",names:[]) }
            try check("RB0 rising edge triggers external INT0",core.lastLocation["line"] as? Int == line("incf    irq_count"))
            _ = try core.debugAction("stop",names:[])
            try check("Keeps breakpoint after stopping with no stale debugger ID",core.breakpoints.count == 1 && core.breakpoints[0]["id"] == nil)
            _ = try core.startDebug(tool:"SIM")
            try check("Reinstalls breakpoint on restart",core.breakpoints[0]["id"] as? Int != nil)
            _ = try core.breakpoint(path:path,line:line("incf    irq_count"))
            try check("Removes reinstalled breakpoint",core.breakpoints.isEmpty)
            _ = try core.debugAction("stop",names:[])
            print("ALL \(checks.count) INTERRUPT CHECKS PASSED")
        } catch { print("ERROR \(error.localizedDescription)"); checks.append(["name":"Unexpected error","ok":false,"error":error.localizedDescription]); throw error }
    }
}
