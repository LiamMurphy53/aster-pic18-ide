import Foundation

@main struct Integration {
    static func main() throws {
        setbuf(stdout, nil)
        let base = URL(fileURLWithPath:CommandLine.arguments[1])
        let core = IDECore()
        var checks: [[String:Any]] = []
        func check(_ name: String,_ test: Bool) throws { checks.append(["name":name,"ok":test]); print("\(test ? "PASS" : "FAIL") \(name)"); guard test else { throw IDEError(name) } }
        core.onEvent = { name,data in if name == "debugStopped" { print("STOP \(jsonString(data))") } }
        defer { core.shutdown(); try? JSONSerialization.data(withJSONObject:checks,options:.prettyPrinted).write(to:base.appendingPathComponent("Tests/integration-result.json")) }
        let purl=base.appendingPathComponent("Tests/CoreProject.X")
        if FileManager.default.fileExists(atPath:purl.path) { try FileManager.default.removeItem(at:purl) }
        try FileManager.default.copyItem(at:base.appendingPathComponent("Resources/Template.X"),to:purl)
        let info = try core.open(purl.path)
        try check("Opens original MPLAB project metadata",info["configuration"] as? String == "default")
        let p = try core.requireProject(), path=purl.appendingPathComponent("main.asm").path
        let file = try p.read(path); let original=file["content"] as! String
        try check("Reads source losslessly",original.contains("goto    main"))
        do { _ = try p.read("/etc/passwd"); try check("Rejects files outside project",false) } catch { try check("Rejects files outside project",true) }
        _ = try p.save(path,content:original+"\n; test edit\n",expected:file["digest"] as! String,encoding:"utf8")
        do { _ = try p.save(path,content:original,expected:file["digest"] as! String,encoding:"utf8"); try check("Rejects stale editor saves",false) } catch { try check("Rejects stale editor saves",true) }
        var updated = try p.read(path)
        _ = try p.save(path,content:original,expected:updated["digest"] as! String,encoding:"utf8")
        let b = try core.build()
        if b["ok"] as? Bool != true { print(b["log"] ?? "") }
        try check("Builds production image with XC8 2.46",b["ok"] as? Bool == true)
        try check("Produces HEX, ELF, and MAP",["hex","elf","map"].allSatisfy{ext in p.outputs("production").contains{URL(fileURLWithPath:$0["path"] as! String).pathExtension==ext}})
        updated = try p.read(path)
        _ = try p.save(path,content:original.replacingOccurrences(of:"    movlw   0x10",with:"    invalid_instruction 0x10"),expected:updated["digest"] as! String,encoding:"utf8")
        let bad = try core.build(); print("DIAGNOSTICS: \(jsonString(bad["diagnostics"] ?? []))")
        if (bad["diagnostics"] as? [[String:Any]])?.isEmpty != false { print(bad["log"] ?? "") }
        try check("Build failure is not reported as success",bad["ok"] as? Bool == false)
        try check("Parses compiler error file and line",(bad["diagnostics"] as? [[String:Any]])?.contains{$0["path"] as? String == path && ($0["line"] as? Int ?? 0)>0} == true)
        updated = try p.read(path); _ = try p.save(path,content:original,expected:updated["digest"] as! String,encoding:"utf8")
        let debug = try core.startDebug(tool:"SIM")
        print("INITIAL: \(jsonString(debug))")
        try check("Loads ELF into real Microchip simulator",debug["state"] as? String == "paused")
        var state: [String:Any] = [:]
        for _ in 0..<4 { state = try core.debugAction("stepi",names:["WREG","STATUS","BSR","count"]) }
        print("STEPPED: \(jsonString(state))")
        try check("Debugger reports source location",(state["location"] as? [String:Any])?["line"] as? Int != nil)
        let regs = state["registers"] as? [[String:String]] ?? []
        try check("WREG follows compiled instructions",regs.first{$0["name"]=="WREG"}?["value"]?.lowercased() == "11")
        let memory = try core.memory(type:"r",address:"0x0000",count:16); print("MEMORY: \(memory)")
        try check("Reads target data memory",memory.split(whereSeparator:{$0.isWhitespace}).count == 16)
        print("WRITE: \(try core.writeRegister(name:"WREG",value:"0x2A"))")
        let inspection = try core.inspect(["WREG"])
        print("WRITTEN: \(jsonString(inspection))")
        try check("Edits live register",(inspection["registers"] as? [[String:String]])?.first?["value"]?.lowercased() == "2a")
        let loopLine=original.components(separatedBy:"\n").firstIndex{$0.contains("incf    WREG")}!+1
        let bp=try core.breakpoint(path:path,line:loopLine)
        try check("Creates source breakpoint",(bp["breakpoints"] as? [[String:Any]])?.count == 1)
        _ = try core.debugAction("continue",names:["WREG"])
        Thread.sleep(forTimeInterval:0.5)
        try check("Continues to source breakpoint",core.lastLocation["line"] as? Int == loopLine)
        let deleted=try core.breakpoint(path:path,line:loopLine)
        try check("Deletes source breakpoint",(deleted["breakpoints"] as? [[String:Any]])?.isEmpty == true)
        let dis = try core.memory(type:"p",address:"0x0",count:12,format:"i"); print("DISASSEMBLY: \(dis)")
        try check("Reads program disassembly",dis.lowercased().contains("goto"))
        _ = try core.debugAction("reset",names:["WREG"])
        _ = try core.debugAction("stop",names:[])
        try check("Stops debugger session",core.debugger == nil)
        let hardware = try core.build(debug:true,tool:"PICkit3")
        if hardware["ok"] as? Bool != true { print(hardware["log"] ?? "") }
        try check("Builds PICkit 3 debug image",hardware["ok"] as? Bool == true)
        try check("PIC-AS recognizes every supplied build option",!(hardware["log"] as? String ?? "").contains("unrecognized option"))
        _ = try core.build(clean:true); _ = try core.build(clean:true,debug:true)
        try check("Cleans generated images",p.outputs().isEmpty)
        // An additional local project is optional and is never included in the repository.
        if let existingPath = ProcessInfo.processInfo.environment["ASTER_TEST_PROJECT"], !existingPath.isEmpty {
            let source = URL(fileURLWithPath:existingPath).standardizedFileURL.resolvingSymlinksInPath()
            let real = FileManager.default.temporaryDirectory.appendingPathComponent("aster-project-\(UUID().uuidString).X")
            try FileManager.default.copyItem(at:source,to:real)
            defer { try? FileManager.default.removeItem(at:real) }
            _ = try core.open(real.path)
            let result = try core.build(); if result["ok"] as? Bool != true { print(result["log"] ?? "") }
            try check("Builds a copy of the supplied project",result["ok"] as? Bool == true)
        }
        print("ALL \(checks.count) INTEGRATION CHECKS PASSED")
    }
}
