import Foundation

@main struct StopwatchTests {
    static func main() throws {
        setbuf(stdout,nil)
        let base=URL(fileURLWithPath:CommandLine.arguments[1]), core=IDECore()
        let project=base.appendingPathComponent("Tests/Stopwatch-\(UUID().uuidString).X")
        defer { core.shutdown(); try? FileManager.default.removeItem(at:project) }
        try FileManager.default.copyItem(at:base.appendingPathComponent("Resources/Template.X"),to:project)
        let file=project.appendingPathComponent("main.asm").resolvingSymlinksInPath()
        let template=try String(contentsOf:file,encoding:.utf8)
        let source=String(template.prefix(upTo:template.range(of:"PSECT code")!.lowerBound))+"""
        PSECT code
        main:
            nop
            movlw 2
            movwf count, a
        again:
            decf count, f, a
            bnz again
            rcall delay
        afterCall:
            nop ; measurement end
        hang:
            bra hang
        delay:
            nop
            return
        END resetVec
        """+"\n"
        try source.write(to:file,atomically:true,encoding:.utf8)
        let configURL=project.appendingPathComponent("nbproject/configurations.xml")
        let config=try XMLDocument(contentsOf:configURL)
        for value in try config.nodes(forXPath:"//Simulator/property[@key='oscillator.frequency']/@value") { value.stringValue="4" }
        try config.xmlData.write(to:configURL)
        _ = try core.open(project.path)
        var checks=0
        func check(_ name:String,_ ok:Bool) throws { guard ok else {throw IDEError("FAIL "+name)};checks+=1;print("PASS "+name) }
        func cycles(_ reading:[String:Any])->Int { Int(reading["cycles"] as? String ?? "") ?? -1 }
        try check("Imports 4 MHz MPLAB instruction clock as 16 MHz Fosc",core.project?.simulatorClockMHz==16)
        try check("Inactive session has no stopwatch reading",core.stopwatchReading()["available"] as? Bool == false)
        do {_ = try core.startDebug(tool:"SIM",clockMHz:0);throw IDEError("Invalid frequency accepted")} catch {try check("Rejects invalid clock before starting",core.debugger == nil)}
        _ = try core.startDebug(tool:"SIM",clockMHz:8,accumulateStopwatch:true)
        try check("New session starts at zero",cycles(core.stopwatchReading()) == 0)
        let expected=[("GOTO",2),("NOP",1),("MOVLW",1),("MOVWF",1),("DECF",1),("BNZ taken",2),("DECF",1),("BNZ not taken",1),("RCALL",2),("NOP in subroutine",1),("RETURN",2)]
        var total=0
        for (name,cost) in expected {
            let state=try core.debugAction("stepi",names:[]);total+=cost
            try check(name+" cycles accumulate correctly",cycles(state["stopwatch"] as? [String:Any] ?? [:]) == total)
        }
        let reading=core.stopwatchReading()
        try check("8 MHz Fosc gives 7.5 microseconds for 15 cycles",abs((reading["seconds"] as? Double ?? -1)-0.0000075)<1e-12)
        let raw=try core.debugger!.command("stopwatch")
        print("MDB STOPWATCH: "+raw)
        let time=match(raw,"\\(([0-9.]+)\\s*(ns|us|µs|ms|s)\\)")
        let scale=["ns":1e-9,"us":1e-6,"µs":1e-6,"ms":1e-3,"s":1.0]
        let measured=time.flatMap { parts in Double(parts[1]).map { $0 * (scale[parts[2]] ?? 0) } } ?? -1
        try check("MDB clock agrees with displayed time",abs(measured-0.0000075)<1e-12)
        Thread.sleep(forTimeInterval:0.15)
        try check("Time spent paused does not count",cycles(core.stopwatchReading()) == total)
        let location=jsonString(core.lastLocation)
        let cleared=try core.resetStopwatch()
        try check("Reset stopwatch zeros cycles without moving CPU",cycles(cleared)==0 && location==jsonString(core.lastLocation))
        _ = try core.debugAction("stepi",names:[])
        try check("Counting resumes from zero",cycles(core.stopwatchReading())==1)
        _ = try core.debugAction("reset",names:[])
        try check("CPU reset also resets stopwatch",cycles(core.stopwatchReading())==0)
        let endLine=source.components(separatedBy:"\n").firstIndex{$0.contains("measurement end")}!+1
        _ = try core.breakpoint(path:file.path,line:endLine)
        _ = try core.debugAction("continue",names:[])
        let deadline=Date().addingTimeInterval(5)
        while core.debugger?.running==true && Date()<deadline {Thread.sleep(forTimeInterval:0.02)}
        try check("Continue measures code through branches and calls to breakpoint",core.lastLocation["line"] as? Int==endLine && cycles(core.stopwatchReading())==15)
        _ = try core.debugAction("stop",names:[])
        try check("Stopping session clears displayed availability",core.stopwatchReading()["available"] as? Bool==false)
        _ = try core.startDebug(tool:"SIM")
        try check("Default session uses project clock",core.simulatorClockMHz==16)
        try check("Default stopwatch resets on Continue",!core.stopwatchAccumulates)
        _ = try core.debugAction("stepi",names:[])
        try check("First step reports two-cycle GOTO",cycles(core.stopwatchReading())==2)
        _ = try core.debugAction("stepi",names:[])
        try check("Steps accumulate within the current run",cycles(core.stopwatchReading())==3)
        _ = try core.debugAction("continue",names:[])
        let runDeadline=Date().addingTimeInterval(5)
        while (core.debugger?.running==true || core.lastLocation["line"] as? Int != endLine) && Date()<runDeadline {Thread.sleep(forTimeInterval:0.02)}
        let interval=core.stopwatchReading()
        try check("Continue excludes cycles before the starting stop",core.lastLocation["line"] as? Int==endLine && cycles(interval)==12)
        try check("Per-run elapsed time uses inherited 4 MHz instruction clock",abs((interval["seconds"] as? Double ?? -1)-3e-6)<1e-12)
        _ = try core.debugAction("stop",names:[])
        print("ALL \(checks) STOPWATCH CHECKS PASSED")
    }
}
