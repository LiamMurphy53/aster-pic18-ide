import Foundation

@main struct Lab4Tests {
    static func main() throws {
        setbuf(stdout,nil)
        let base=URL(fileURLWithPath:CommandLine.arguments[1]), core=IDECore(), fm=FileManager.default
        let root=base.appendingPathComponent("Tests/Lab4-"+UUID().uuidString).appendingPathExtension("X")
        defer {core.shutdown();try? fm.removeItem(at:root)}
        try fm.copyItem(at:base.appendingPathComponent("Resources/Template.X"),to:root)
        var checks=0
        func check(_ name:String,_ ok:Bool) throws {guard ok else {throw IDEError("FAIL "+name)};checks+=1;print("PASS "+name)}
        // Listing offsets differ from relocated symbol addresses; constants are excluded.
        let listing="""
            10   000000                  message:
            11   000000                  buffer:
            12   000000                  duplicate:
            13                           Delay equ 123
        Symbol Table
         message 1AF22 buffer 000A duplicate 0020 Delay 007B
        """
        let parsed=PICProject.listingAddresses(listing,preprocessed:"message: DB 0\nbuffer: DS 1\nDelay EQU 123")
        try check("Uses linker addresses for local labels, excluding EQU",parsed == ["message":0x1AF22,"buffer":10,"duplicate":32])
        let fixtureProject=try PICProject(root)
        let build=root.appendingPathComponent("build/default/debug"),dist=root.appendingPathComponent("dist/default/debug")
        try fm.createDirectory(at:build,withIntermediateDirectories:true)
        try fm.createDirectory(at:dist,withIntermediateDirectories:true)
        try listing.write(to:build.appendingPathComponent("one.lst"),atomically:true,encoding:.utf8)
        try " 1 000000 duplicate:\nSymbol Table\n duplicate 0020".write(to:build.appendingPathComponent("two.lst"),atomically:true,encoding:.utf8)
        try " 1 000000 stale:\nSymbol Table\n stale 0020".write(to:build.appendingPathComponent("stale.lst"),atomically:true,encoding:.utf8)
        try "build/default/debug/one.o\nbuild/default/debug/two.o\n".write(to:dist.appendingPathComponent("fixture.map"),atomically:true,encoding:.utf8)
        let linked=try fixtureProject.localAddressSymbols()
        try check("Rejects duplicate local names and ignores unlinked stale listings",linked == ["message":0x1AF22,"buffer":10])
        try fm.removeItem(at:dist)
        try fm.removeItem(at:build)
        let file=root.appendingPathComponent("main.asm").resolvingSymlinksInPath(),template=try String(contentsOf:file,encoding:.utf8)
        let source=String(template.prefix(upTo:template.range(of:"PSECT code")!.lowerBound))+"""
        PSECT udata_acs
        buffer: DS 4
        PSECT code
        main:
            movlw 0x08
            movwf T0CON,a
            movlw 0xff
            movwf TMR0H,a
            movlw 0xe0
            movwf TMR0L,a
            bcf INTCON,2,a
            bsf T0CON,7,a
        poll:
            btfss INTCON,2,a
            bra poll
        timerDone:
            nop ; timer overflow observed
        hang:
            bra hang
        PSECT romData,space=0,class=CONST
        message:
        IRPC char, ROM
            DB 'char'
        ENDM
            DB 0
        END resetVec
        """+"\n"
        try source.write(to:file,atomically:true,encoding:.utf8)
        _ = try core.open(root.path)
        _ = try core.startDebug(tool:"SIM",clockMHz:16)
        let message=try core.resolveAddress("message"), buffer=try core.resolveAddress("buffer")
        try check("Resolves local ROM and RAM labels in the real simulator",message.hasPrefix("0x") && buffer.hasPrefix("0x"))
        let raw=try core.memory(type:"p",address:message,count:4).split(whereSeparator:{$0.isWhitespace}).map{String($0).lowercased()}
        try check("IRPC-generated ROM bytes are visible by label",raw == ["52","4f","4d","00"])
        _ = try core.writeRegister(name:"buffer",value:"0x50")
        let ram=try core.memory(type:"r",address:buffer,count:1).trimmingCharacters(in:.whitespacesAndNewlines)
        try check("Reads the LCD-style RAM buffer at its local label",ram.lowercased() == "50")
        for (name,value) in [("TBLPTRU","0x01"),("TBLPTRH","0xaf"),("TBLPTRL","0x22"),("FSR0H","0x0a"),("FSR0L","0xbc")] {_ = try core.writeRegister(name:name,value:value)}
        let table=try core.pointerAddress("TBLPTR"), fsr=try core.pointerAddress("FSR0")
        try check("Combines all three table-pointer bytes above 64 KiB",table == "0x1af22")
        try check("Combines both RAM-pointer bytes",fsr == "0xabc")
        do {_ = try core.pointerAddress("TBLPTR;reset");throw IDEError("Invalid pointer accepted")} catch {try check("Rejects unsupported pointer names",error.localizedDescription.contains("Choose TBLPTR or FSR0"))}
        do {_ = try core.resolveAddress("message;reset");throw IDEError("Invalid symbol accepted")} catch {try check("Rejects invalid symbol names",error.localizedDescription.contains("numeric address or a symbol"))}
        let line=source.components(separatedBy:"\n").firstIndex{$0.contains("timer overflow observed")}!+1
        _ = try core.breakpoint(path:file.path,line:line)
        _ = try core.debugAction("continue",names:[])
        let deadline=Date().addingTimeInterval(8)
        while (core.debugger?.running == true || core.lastLocation["line"] as? Int != line) && Date()<deadline {Thread.sleep(forTimeInterval:0.02)}
        try check("Timer0 rolls over and reaches its polled flag without interrupts",core.lastLocation["line"] as? Int == line)
        let registers=try core.inspect(["INTCON","T0CON"])["registers"] as! [[String:String]]
        try check("Timer0 flag is set while interrupt enables remain off",(Int(registers[0]["value"]!,radix:16)! & 0xe4) == 4)
        _ = try core.debugAction("stop",names:[])
        do {_ = try core.pointerAddress("TBLPTR");throw IDEError("Inactive pointer accepted")} catch {try check("Pointer inspection requires a paused session",error.localizedDescription.contains("Start or pause"))}
        _ = try core.open(root.path)
        try check("Opening a project clears old symbol addresses",core.localAddressSymbols.isEmpty)
        print("ALL \(checks) LAB 4 CHECKS PASSED")
    }
}
