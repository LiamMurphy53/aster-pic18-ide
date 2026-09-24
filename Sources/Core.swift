import Foundation
import CryptoKit
import Darwin

struct IDEError: LocalizedError { let message: String; var errorDescription: String? { message }; init(_ message: String) { self.message = message } }
func jsonString(_ value: Any) -> String { (try? String(data: JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), encoding: .utf8)) ?? "null" }
func match(_ text: String, _ pattern: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
}
func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func safeLine(_ text: String) throws -> String { guard !text.contains("\n"), !text.contains("\r"), !text.contains("\0") else { throw IDEError("A command must fit on one line.") }; return text }
func quoteMDB(_ path: String) throws -> String { _ = try safeLine(path); guard !path.contains("\"") else { throw IDEError("Debugger paths cannot contain double quotes.") }; return "\"\(path)\"" }

struct Toolchain {
    var mplab = "/Applications/microchip/mplabx/v6.20"
    var xc8 = "/Applications/microchip/xc8/v2.46"
    var platform: String { mplab + "/mplab_platform" }
    var assembler: String { xc8 + "/pic-as/bin/pic-as" }
    var make: String { platform + "/bin/make" }
    var pack: String { mplab + "/packs/Microchip/PIC18F-K_DFP/1.13.292" }
    var java: String {
        let conf = (try? String(contentsOfFile: platform + "/etc/mplab_ide.conf", encoding: .utf8)) ?? ""
        let root = match(conf, "(?m)^jdkhome=\"([^\"]+)\"")?[1] ?? ""
        return root + "/bin/java"
    }
    var environment: [String:String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = platform + "/bin:" + xc8 + "/bin:" + xc8 + "/pic-as/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["DYLD_LIBRARY_PATH"] = platform + "/bin"
        env["MPLABX_THIRDPARTY_LIB_PATH"] = platform + "/thirdparty/"
        env["netbeans_dir"] = platform
        env["mplabx_dir"] = platform
        env["LANG"] = "en_US.UTF-8"
        return env
    }
    func status() -> [[String:Any]] {
        [("MPLAB X", "6.20", make), ("PIC assembler", "2.46", assembler), ("MDB debugger", "6.20", platform + "/lib/mdb.jar"), ("PIC18F-K device pack", "1.13.292", pack), ("Java runtime", "MPLAB bundled", java)].map { ["name":$0.0,"version":$0.1,"path":$0.2,"available":FileManager.default.fileExists(atPath:$0.2)] }
    }
}

final class CommandRunner {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; let p = process; lock.unlock(); if let p, p.isRunning { p.interrupt(); DispatchQueue.global().asyncAfter(deadline:.now()+2) { if p.isRunning { p.terminate() } } } }
    func run(_ executable: String, _ arguments: [String], cwd: URL? = nil, env: [String:String]? = nil, timeout: TimeInterval = 120, output: @escaping (String)->Void = {_ in}) throws -> (Int32,String) {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath:executable); p.arguments = arguments; p.currentDirectoryURL = cwd; p.environment = env
        p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
        lock.lock(); process = p; cancelled = false; lock.unlock()
        defer { lock.lock(); process = nil; lock.unlock() }
        try p.run()
        let deadline = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline:.now()+timeout, execute:deadline)
        var data = Data()
        while true { let chunk = pipe.fileHandleForReading.availableData; if chunk.isEmpty { break }; data.append(chunk); output(String(decoding:chunk,as:UTF8.self)) }
        p.waitUntilExit(); deadline.cancel()
        lock.lock(); let wasCancelled = cancelled; lock.unlock()
        if wasCancelled { throw IDEError("Build cancelled.") }
        if p.terminationReason == .uncaughtSignal { throw IDEError("The tool stopped or exceeded its time limit. See Output for details.") }
        return (p.terminationStatus, String(decoding:data,as:UTF8.self))
    }
}

final class PICProject {
    let root: URL
    var configuration = "default"
    var files: [URL] = []
    var configurations: [[String:String]] = []
    var prebuilt: URL?
    var name: String { root.deletingPathExtension().lastPathComponent }
    init(_ url: URL) throws {
        if ["hex","elf"].contains(url.pathExtension.lowercased()) { root = url.deletingLastPathComponent(); prebuilt = url; files = [url]; return }
        root = url.standardizedFileURL.resolvingSymlinksInPath()
        let configURL = root.appendingPathComponent("nbproject/configurations.xml")
        guard FileManager.default.fileExists(atPath:configURL.path) else { throw IDEError("Choose an MPLAB .X project folder, or a prebuilt .hex or .elf file.") }
        let doc = try XMLDocument(contentsOf:configURL)
        let nodes = try doc.nodes(forXPath:"//conf")
        configurations = nodes.compactMap { node in
            guard let el = node as? XMLElement else { return nil }
            func value(_ path: String) -> String { (try? el.nodes(forXPath:path).first?.stringValue) ?? "" }
            return ["name":el.attribute(forName:"name")?.stringValue ?? "default", "device":value("toolsSet/targetDevice"), "compiler":value("toolsSet/languageToolchain"), "version":value("toolsSet/languageToolchainVersion"), "tool":value("toolsSet/platformTool"),"instructionFrequency":value("Simulator/property[@key='oscillator.frequency']/@value"),"instructionFrequencyUnit":value("Simulator/property[@key='oscillator.frequencyunit']/@value")]
        }
        if let first = configurations.first { configuration = first["name"] ?? "default" }
        guard configurations.contains(where:{$0["device"]?.uppercased() == "PIC18F87K22"}) else { throw IDEError("This version of Aster supports PIC18F87K22 projects.") }
        let items = try doc.nodes(forXPath:"//logicalFolder//itemPath")
        var paths = Set<String>()
        for node in items {
            guard let item = node.stringValue else { continue }
            let url = URL(fileURLWithPath:item, relativeTo:root).standardizedFileURL.resolvingSymlinksInPath()
            if paths.insert(url.path).inserted { files.append(url) }
        }
        // Generated project files are useful in the explorer, but private IDE state is omitted.
        for item in ["Makefile","nbproject/configurations.xml","nbproject/project.xml"] {
            let u = root.appendingPathComponent(item)
            if FileManager.default.fileExists(atPath:u.path), paths.insert(u.path).inserted { files.append(u) }
        }
        files.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
    func select(_ conf: String) throws {
        guard let c = configurations.first(where:{$0["name"] == conf}), c["device"]?.uppercased() == "PIC18F87K22", conf.range(of:"^[A-Za-z0-9_.-]+$",options:.regularExpression) != nil else { throw IDEError("Unsupported project configuration.") }
        configuration = conf
    }
    func allowed(_ path: String) throws -> URL {
        let u = URL(fileURLWithPath:path).standardizedFileURL.resolvingSymlinksInPath()
        let generated = u.path.hasPrefix(root.path + "/dist/") || u.path.hasPrefix(root.path + "/build/") || u.path.hasPrefix(root.path + "/disassembly/")
        guard files.contains(where:{$0.path == u.path}) || generated else { throw IDEError("That file is outside the open project.") }
        return u
    }
    func read(_ path: String) throws -> [String:Any] {
        let u = try allowed(path), data = try Data(contentsOf:u)
        guard data.count <= 8_000_000, !["elf","o","cof"].contains(u.pathExtension.lowercased()) else { throw IDEError("This is a binary or large output file. Use Reveal in Finder to inspect it with another tool.") }
        let encoding = String(data:data,encoding:.utf8) != nil ? "utf8" : "latin1"
        let content = String(data:data,encoding:encoding == "utf8" ? .utf8 : .isoLatin1) ?? ""
        return ["path":u.path,"content":content,"digest":digest(data),"encoding":encoding,"readOnly":u.path.contains("/dist/") || u.path.contains("/build/") || u.lastPathComponent == "configurations.xml"]
    }
    func save(_ path: String, content: String, expected: String, encoding: String) throws -> [String:Any] {
        let u = try allowed(path)
        guard files.contains(where:{$0.path == u.path}), !u.path.contains("/dist/"), !u.path.contains("/build/"), u.lastPathComponent != "configurations.xml" else { throw IDEError("This generated file is read-only.") }
        let old = try Data(contentsOf:u)
        guard digest(old) == expected else { throw IDEError("This file changed on disk. Your edits are still here. Copy them or reload the file before saving.") }
        guard let data = content.data(using:encoding == "latin1" ? .isoLatin1 : .utf8, allowLossyConversion:false) else { throw IDEError("This file uses Latin-1. Remove unsupported characters before saving.") }
        try data.write(to:u,options:.atomic)
        return ["digest":digest(data)]
    }
    func outputs(_ image: String? = nil) -> [[String:Any]] {
        if let prebuilt { return [["path":prebuilt.path,"name":prebuilt.lastPathComponent,"size":(try? prebuilt.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0]] }
        let dir = root.appendingPathComponent("dist/\(configuration)" + (image.map{"/"+$0} ?? ""))
        let buildDir = root.appendingPathComponent("build/\(configuration)" + (image.map{"/"+$0} ?? ""))
        var results: [[String:Any]] = []
        for directory in [dir,buildDir] {
            guard let e = FileManager.default.enumerator(at:directory,includingPropertiesForKeys:[.fileSizeKey,.isRegularFileKey]) else { continue }
            for case let u as URL in e {
                guard let v = try? u.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey]), v.isRegularFile == true else { continue }
                results.append(["name":u.lastPathComponent,"path":u.path,"size":v.fileSize ?? 0])
            }
        }
        return results.sorted { ($0["path"] as! String) < ($1["path"] as! String) }
    }

    func artifact(_ ext: String, image: String) throws -> URL {
        if let prebuilt { guard prebuilt.pathExtension.lowercased() == ext || ext == "hex" else { throw IDEError("Source debugging requires an ELF image. Open a project or a prebuilt .elf.") }; return prebuilt }
        let urls = outputs(image).compactMap { $0["path"] as? String }.filter { URL(fileURLWithPath:$0).pathExtension == ext }
        guard let path = urls.first else { throw IDEError("No \(image) .\(ext) was produced. Check the build output.") }
        return URL(fileURLWithPath:path)
    }
    func localDataSymbols() throws -> [String:Int] {
        var declared = Set<String>()
        let declaration = try NSRegularExpression(pattern:"(?im)^\\s*([A-Za-z_][A-Za-z0-9_.$]*)\\s*:\\s*DS\\b")
        for file in files where ["asm","s"].contains(file.pathExtension.lowercased()) {
            guard let text = try? String(contentsOf:file,encoding:.utf8) else { continue }
            for m in declaration.matches(in:text,range:NSRange(text.startIndex...,in:text)) { if let r = Range(m.range(at:1),in:text) { declared.insert(String(text[r])) } }
        }
        var candidates: [String:Set<Int>] = [:]
        let root = self.root.appendingPathComponent("build/\(configuration)/debug")
        if let en = FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil) {
            for case let url as URL in en where url.pathExtension == "lst" {
                guard let text = try? String(contentsOf:url,encoding:.utf8), let range = text.range(of:"Symbol Table",options:.backwards) else { continue }
                let table = String(text[range.upperBound...])
                for name in declared {
                    let pattern = "(?:^|\\s)"+NSRegularExpression.escapedPattern(for:name)+"\\s+([0-9A-Fa-f]{4,8})(?=\\s|$)"
                    if let m = match(table,pattern), let address = Int(m[1],radix:16), address < 0x1000 { candidates[name,default:[]].insert(address) }
                }
            }
        }
        return candidates.compactMapValues { $0.count == 1 ? $0.first : nil }
    }
    var simulatorClockMHz: Double {
        guard let conf = configurations.first(where:{$0["name"] == configuration}),
              let frequency = Double(conf["instructionFrequency"] ?? "") else { return 4 }
        let units: [String:Double] = ["Mega":1.0,"Kilo":0.001,"None":0.000001]
        let scale: Double = units[conf["instructionFrequencyUnit"] ?? "Mega"] ?? 1.0
        // MPLAB's Simulator oscillator.frequency is the instruction clock, not Fosc.
        let fosc = frequency * scale * 4
        return fosc.isFinite && (0.001...64).contains(fosc) ? fosc : 4
    }
    func info() -> [String:Any] {
        ["clockMHz":simulatorClockMHz,"name":prebuilt?.lastPathComponent ?? name,"path":root.path,"configuration":configuration,"configurations":configurations,"prebuilt":prebuilt != nil,"files":files.map { ["name":$0.lastPathComponent,"path":$0.path,"relative":$0.path.hasPrefix(root.path+"/") ? String($0.path.dropFirst(root.path.count+1)) : $0.path,"exists":FileManager.default.fileExists(atPath:$0.path)] },"outputs":outputs()]
    }
}

// MDB uses the same bare prompt for its command reader and its dialog reader.
// Keep text across pipe chunks so a dialog cannot consume the next command.
struct MDBPromptReader {
    enum Prompt { case ready, confirmation(String) }
    private var text = ""
    private var lineStart = true
    mutating func reset() { text = ""; lineStart = true }
    mutating func receive(_ chunk: String) -> [Prompt] {
        var result: [Prompt] = []
        for character in chunk {
            if character == ">", lineStart {
                let message = text.trimmingCharacters(in:.whitespacesAndNewlines)
                let question = message.components(separatedBy:.newlines).last ?? ""
                let isConfirmation = question.hasSuffix("?") || match(question,"(?i)\\[yes/no(?:/cancel)?\\]\\s*$") != nil
                result.append(isConfirmation ? .confirmation(message) : .ready)
                reset()
            } else {
                text.append(character)
                if character.isNewline { lineStart = true }
                else if character != " " && character != "\t" { lineStart = false }
            }
        }
        return result
    }
}

final class MDBSession {
    let tc: Toolchain
    let condition = NSCondition()
    private let commandLock = NSLock()
    private var process: Process?
    private var input: Pipe?
    private var buffer = ""
    private var prompts = 0
    private var promptReader = MDBPromptReader()
    private var confirmations: [String] = []
    var onOutput: (String)->Void = {_ in}
    var onStop: ([String:Any])->Void = {_ in}
    var onConfirmation: (String)->Bool = {_ in false}
    var running = false
    private var locationBuffer = ""
    init(_ tc: Toolchain) { self.tc = tc }
    // Optional launch overrides allow protocol tests without connecting hardware.
    func start(executable: URL? = nil, arguments: [String]? = nil) throws {
        let p = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.executableURL = executable ?? URL(fileURLWithPath:tc.java)
        p.arguments = arguments ?? ["-Dfile.encoding=UTF-8","-Djava.awt.headless=true","-jar",tc.platform+"/lib/mdb.jar"]
        p.environment = tc.environment; p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
        process = p; input = stdin
        stdout.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData; guard !d.isEmpty else { h.readabilityHandler = nil; return }
            self?.receive(String(decoding:d,as:UTF8.self))
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData; guard !d.isEmpty else { h.readabilityHandler = nil; return }
            self?.onOutput(String(decoding:d,as:UTF8.self))
        }
        p.terminationHandler = { [weak self] _ in self?.condition.lock(); self?.condition.broadcast(); self?.condition.unlock() }
        try p.run()
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(25)
        while prompts == 0 && p.isRunning { if !condition.wait(until:deadline) { throw IDEError("MDB did not start. Check the toolchain paths.") } }
        guard p.isRunning else { throw IDEError("MDB exited during startup.") }
    }
    private func receive(_ s: String) {
        condition.lock()
        buffer += s
        for prompt in promptReader.receive(s) {
            switch prompt {
            case .ready: prompts += 1
            case .confirmation(let message): confirmations.append(message)
            }
        }
        locationBuffer += s
        if locationBuffer.count > 14000 { locationBuffer = String(locationBuffer.suffix(14000)) }
        var stop: [String:Any]?
        if let m = match(locationBuffer, "address:\\s*(0x[0-9a-fA-F]+)\\s*\\n\\s*file:([^\\r\\n]+)\\s*\\n\\s*source line:(\\d+)") {
            running = false; stop = ["address":m[1],"file":m[2].trimmingCharacters(in:.whitespaces),"line":Int(m[3]) ?? 1]; locationBuffer = ""
        } else if s.contains("Target halted") || s.contains("Target Halted") { running = false }
        condition.broadcast(); condition.unlock()
        onOutput(s)
        if let stop { onStop(stop) }
    }
    func command(_ line: String, timeout: TimeInterval = 30) throws -> String {
        _ = try safeLine(line)
        commandLock.lock(); defer { commandLock.unlock() }
        condition.lock()
        guard let p = process, p.isRunning, let input else { condition.unlock(); throw IDEError("Start a debug session first.") }
        let count = prompts; buffer = ""; promptReader.reset()
        do { try input.fileHandleForWriting.write(contentsOf:Data((line+"\n").utf8)) } catch { condition.unlock(); throw error }
        var deadline = Date().addingTimeInterval(timeout)
        while prompts == count && p.isRunning {
            if !confirmations.isEmpty {
                let message = confirmations.removeFirst()
                condition.unlock()
                let accepted = onConfirmation(message)
                condition.lock()
                guard accepted else {
                    condition.unlock(); stop()
                    throw IDEError("Device operation cancelled at the confirmation. The programmer session was closed.")
                }
                guard p.isRunning, process === p else {
                    condition.unlock(); throw IDEError("MDB closed while waiting for confirmation.")
                }
                do { try input.fileHandleForWriting.write(contentsOf:Data("yes\n".utf8)) }
                catch { condition.unlock(); stop(); throw error }
                // Time spent reading the dialog is not a tool timeout.
                deadline = Date().addingTimeInterval(timeout)
                continue
            }
            if !condition.wait(until:deadline) { condition.unlock(); stop(); throw IDEError("MDB timed out on ‘\(line)’. The session was closed so commands cannot get out of sync.") }
        }
        let result = buffer; condition.unlock()
        guard p.isRunning || line.lowercased() == "quit" else { throw IDEError("MDB exited. See Debug console for details.") }
        return result.trimmingCharacters(in:CharacterSet(charactersIn:">\r\n "))
    }
    func checked(_ line: String, timeout: TimeInterval = 30) throws -> String {
        let output = try command(line,timeout:timeout)
        if match(output,"(?im)(^Error:|failed|not supported|not found|does not exist|Unknown command|Invalid command|Unable to|No tool|not connected)") != nil { throw IDEError(output) }
        return output
    }
    func stop() {
        condition.lock(); let p = process; process = nil; let pipe = input; input = nil; running = false; condition.broadcast(); condition.unlock()
        try? pipe?.fileHandleForWriting.close()
        if let p, p.isRunning { p.terminate(); DispatchQueue.global().asyncAfter(deadline:.now()+2) { if p.isRunning { kill(p.processIdentifier,SIGKILL) } } }
    }
    deinit { stop() }
}

final class SerialConnection {
    private var handle: FileHandle?
    var onData: (String)->Void = {_ in}
    var port: String?
    private let portProvider: (() -> [String])?
    init(portProvider: (() -> [String])? = nil) { self.portProvider = portProvider }
    func ports() -> [String] { if let portProvider { return portProvider() }; return ((try? FileManager.default.contentsOfDirectory(atPath:"/dev")) ?? []).filter { $0.hasPrefix("cu.") }.map { "/dev/"+$0 }.sorted() }
    func connect(_ path: String, baud: Int) throws {
        guard ports().contains(path), [1200,2400,4800,9600,19200,38400,57600,115200,230400].contains(baud) else { throw IDEError("Select an available serial port and baud rate.") }
        disconnect()
        let fd = Darwin.open(path,O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw IDEError("Cannot open \(path): \(String(cString:strerror(errno)))") }
        let h = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        let result = try CommandRunner().run("/bin/stty",["-f",path,String(baud),"raw","cs8","-parenb","-cstopb","-echo","-ixon","-ixoff","-crtscts","-hupcl"],timeout:5)
        guard result.0 == 0 else { try? h.close(); throw IDEError(result.1) }
        _ = fcntl(fd,F_SETFL,0)
        handle = h; port = path
        h.readabilityHandler = { [weak self] h in
            var bytes = [UInt8](repeating:0,count:4096)
            let n = Darwin.read(h.fileDescriptor,&bytes,bytes.count)
            if n > 0 { self?.onData(String(decoding:bytes.prefix(n),as:UTF8.self)) }
            else if n == 0 || (errno != EAGAIN && errno != EINTR) {
                self?.disconnect(); self?.onData("\n[Serial device disconnected]\n")
            }
        }
    }

    func send(_ text: String) throws { guard let handle else { throw IDEError("Connect a serial port first.") }; try handle.write(contentsOf:Data(text.utf8)) }
    func disconnect() { handle?.readabilityHandler = nil; try? handle?.close(); handle = nil; port = nil }
    deinit { disconnect() }
}

final class IDECore {
    var tc = Toolchain()
    var project: PICProject?
    var debugger: MDBSession?
    let runner = CommandRunner()
    let serial = SerialConnection()
    var onEvent: (String,Any)->Void = {_,_ in}
    var onConfirmation: (String)->Bool = {_ in false}
    var debugTool = "SIM"
    var simulatorClockMHz = 4.0
    var stopwatchAccumulates = false
    var lastLocation: [String:Any] = [:]
    var lastBuild: [String:Any] = [:]
    var breakpoints: [[String:Any]] = []
    var localDataSymbols: [String:Int] = [:]
    func open(_ path: String) throws -> [String:Any] {
        let p = try PICProject(URL(fileURLWithPath:path))
        debugger?.stop(); debugger = nil; breakpoints = []; lastLocation = [:]; lastBuild = [:]; project = p
        return p.info()
    }
    func requireProject() throws -> PICProject { guard let project else { throw IDEError("Open or create a project first.") }; return project }
    func build(clean: Bool = false, debug: Bool = false, tool: String = "SIM") throws -> [String:Any] {
        let p = try requireProject()
        guard p.prebuilt == nil else { throw IDEError("Prebuilt images are ready to program. Open a source project to build.") }
        guard debugger == nil else { throw IDEError("Stop debugging before building or cleaning this project.") }
        let c = p.configurations.first { $0["name"] == p.configuration }
        guard c?["device"] == "PIC18F87K22" else { throw IDEError("Choose a PIC18F87K22 configuration.") }
        let makefile = "nbproject/Makefile-\(p.configuration).mk"
        guard FileManager.default.fileExists(atPath:p.root.appendingPathComponent(makefile).path) else { throw IDEError("Generated makefiles are missing. Use Project → Regenerate makefiles, then build again.") }
        var args = ["-f",makefile,clean ? ".clean-conf" : ".build-conf","SUBPROJECTS=", "CONF="+p.configuration]
        if debug { args.append("TYPE_IMAGE=DEBUG_RUN"); if !clean { args.append("-B") } }
        if c?["compiler"] == "pic-as" {
            // MPLAB 6.20 generates the same PIC-AS flags for SIM and PICkit 3 on this device.
            // PIC-AS 2.46 does not implement XC8 C's -mdebugger option.
            args += ["MP_AS=\"\(tc.assembler)\" -Wa,-a", "MP_LD=\"\(tc.assembler)\""]
        } else if tool == "PICkit3" && debug && c?["tool"] != "PICkit3" {
            throw IDEError("For a C hardware debug build, select PICkit 3 in the MPLAB project configuration first.")
        }
        onEvent("buildStart",["clean":clean,"debug":debug]); lastBuild = [:]
        let started = Date()
        onEvent("buildOutput","\(clean ? "Cleaning" : "Building") \(p.name) · \(p.configuration) · \(debug ? "debug" : "production")\n")
        let (code,log) = try runner.run(tc.make,args,cwd:p.root,env:tc.environment,output:{self.onEvent("buildOutput",$0)})
        let result: [String:Any] = ["ok":code == 0,"exitCode":code,"elapsed":Date().timeIntervalSince(started),"log":log,"diagnostics":diagnostics(log,root:p.root),"outputs":p.outputs(),"clean":clean]
        lastBuild = result; onEvent("buildEnd",result)
        return result
    }
    func diagnostics(_ text: String, root: URL) -> [[String:Any]] {
        text.components(separatedBy:.newlines).compactMap { line in
            let patterns = ["^(.+?):(\\d+)(?::(\\d*))?:\\s*(fatal error|error|warning|note):\\s*(.*)$", "^(.+?)\\((\\d+)\\)\\s*:\\s*(?:(\\d+):)?\\s*(error|warning|note):?\\s*(.*)$"]
            for pattern in patterns { if let m = match(line,pattern) { return ["path":URL(fileURLWithPath:m[1],relativeTo:root).standardizedFileURL.path,"line":Int(m[2]) ?? 1,"column":Int(m[3]) ?? 1,"severity":m[4],"message":m[5]] } }
            return nil
        }
    }
    func newSession() throws -> MDBSession {
        let s = MDBSession(tc)
        s.onConfirmation = { self.onConfirmation($0) }
        s.onOutput = { self.onEvent("debugOutput",$0) }
        s.onStop = { location in self.lastLocation = location; self.onEvent("debugStopped",location) }
        try s.start(); return s
    }
    func startDebug(tool: String, index: Int = 0, clockMHz: Double? = nil, accumulateStopwatch: Bool = false) throws -> [String:Any] {
        guard ["SIM","PICkit3"].contains(tool), index >= 0 else { throw IDEError("Choose Simulator or PICkit 3.") }
        let p = try requireProject()
        let clockMHz = clockMHz ?? p.simulatorClockMHz
        guard clockMHz.isFinite, (0.001...64).contains(clockMHz) else { throw IDEError("Enter an oscillator frequency from 0.001 to 64 MHz.") }
        simulatorClockMHz = clockMHz
        stopwatchAccumulates = accumulateStopwatch
        debugger?.stop(); debugger = nil
        if p.prebuilt == nil { let b = try build(debug:true,tool:tool); guard b["ok"] as? Bool == true else { throw IDEError("Fix the build errors before starting the debugger.") } }
        let elf = try p.artifact("elf",image:"debug")
        localDataSymbols = try p.localDataSymbols()
        clearBreakpointBindings()
        let s = try newSession(); debugger = s; debugTool = tool; lastLocation = [:]
        do {
            _ = try s.checked("device PIC18F87K22")
            if tool == "SIM" {
                // MDB expects instruction frequency; PIC18 instruction clock is Fosc / 4.
                _ = try s.checked("set oscillator.frequency \(clockMHz / 4)")
                _ = try s.checked("set oscillator.frequencyunit Mega")
            }
            if tool == "PICkit3" { _ = try s.checked("set poweroptions.powerenable false") }
            _ = try s.checked("hwtool \(tool)\(tool == "SIM" ? "" : " \(index)")",timeout:60)
            let result = try s.checked("program \(quoteMDB(elf.path))",timeout:90)
            guard result.lowercased().contains("program succeeded") else { throw IDEError("MDB did not confirm that the image loaded.\n"+result) }
            _ = try s.checked("reset")
            if tool == "SIM" { _ = try s.checked(accumulateStopwatch ? "stopwatch nror" : "stopwatch ror"); _ = try s.checked("stopwatch clear") }
            for i in breakpoints.indices {
                let path = breakpoints[i]["path"] as! String, line = breakpoints[i]["line"] as! Int
                breakpoints[i]["id"] = try installBreakpoint(s,path:path,line:line)
            }
            lastLocation = ["address":"0x0000"]
            onEvent("debugState",["state":"paused","tool":tool])
            return try inspect(["WREG","STATUS","BSR","TRISD","LATD","PORTD"])
        } catch { s.stop(); debugger = nil; clearBreakpointBindings(); onEvent("debugState",["state":"disconnected"]); throw error }
    }
    func inspect(_ names: [String]) throws -> [String:Any] {
        guard let s = debugger else { throw IDEError("Start a debug session first.") }
        guard !s.running else { throw IDEError("Pause execution to inspect registers.") }
        var values: [[String:String]] = []
        for name in names.prefix(80) {
            guard name.range(of:"^[A-Za-z_][A-Za-z0-9_.$]*$",options:.regularExpression) != nil else { continue }
            let output = try s.command("print /x /datasize:1 \(name)")
            var value = output.components(separatedBy:"=").dropFirst().joined(separator:"=").trimmingCharacters(in:.whitespacesAndNewlines)
            if output.contains("Symbol does not exist"), let address = localDataSymbols[name] {
                let raw = try s.command("x /r1xb 0x\(String(address,radix:16))")
                if let byte = match(raw,"(?i)^\\s*([0-9a-f]{2})\\s*$")?[1] { value = byte.lowercased() }
            }
            values.append(["name":name,"value":value.isEmpty ? output : value])
        }
        return ["registers":values,"location":lastLocation,"tool":debugTool,"state":s.running ? "running" : "paused","breakpoints":breakpoints,"stopwatch":stopwatchReading()]
    }
    func debugAction(_ action: String, names: [String]) throws -> [String:Any] {
        guard let s = debugger else { throw IDEError("Start a debug session first.") }
        if action == "stop" { s.stop(); debugger = nil; lastLocation = [:]; clearBreakpointBindings(); onEvent("debugState",["state":"disconnected"]); return ["state":"disconnected","breakpoints":breakpoints] }
        guard ["stepi","step","next","continue","halt","reset"].contains(action) else { throw IDEError("Unknown debug action.") }
        if action != "halt" && s.running { throw IDEError("Pause the target first.") }
        if action == "continue" { s.running = true }
        do { _ = try s.checked(action) } catch { s.running = false; throw error }
        if action == "halt" || action == "reset" { s.running = false }
        if action == "reset" { lastLocation = ["address":"0x0000"]; if debugTool == "SIM" { _ = try s.checked("stopwatch clear") } }
        if s.running { onEvent("debugState",["state":"running","tool":debugTool]); return ["state":"running"] }
        onEvent("debugState",["state":"paused","tool":debugTool]); return try inspect(names)
    }
    func stopwatchReading() -> [String:Any] {
        guard let s = debugger, debugTool == "SIM", !s.running else { return ["available":false] }
        do {
            let output = try s.checked("stopwatch")
            guard let digits = match(output,"(?i)cycle count\\s*=\\s*([0-9]+)")?[1], let cycles = UInt64(digits) else {
                throw IDEError("The simulator did not return a cycle count.")
            }
            guard let elapsed = match(output,"\\(([0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)\\s*(ns|us|µs|μs|ms|s)\\)"),
                  let value = Double(elapsed[1]),
                  let scale = ["ns":1e-9,"us":1e-6,"µs":1e-6,"μs":1e-6,"ms":1e-3,"s":1.0][elapsed[2]] else {
                throw IDEError("The simulator did not return an elapsed time.")
            }
            return ["available":true,"cycles":String(cycles),"seconds":value*scale,"elapsedText":elapsed[1]+" "+elapsed[2],"clockMHz":simulatorClockMHz,"accumulate":stopwatchAccumulates]
        } catch { return ["available":false,"error":error.localizedDescription] }
    }
    func resetStopwatch() throws -> [String:Any] {
        guard let s = debugger, debugTool == "SIM", !s.running else { throw IDEError("Pause the simulator before resetting the stopwatch.") }
        _ = try s.checked("stopwatch clear")
        return stopwatchReading()
    }
    private func clearBreakpointBindings() {
        for i in breakpoints.indices { breakpoints[i].removeValue(forKey:"id") }
    }
    private func installBreakpoint(_ s: MDBSession, path: String, line: Int) throws -> Int {
        let result = try s.checked("break \(quoteMDB(path+":"+String(line)))")
        guard let m = match(result,"(?i)Breakpoint\\s+(\\d+)\\s+at"), let id = Int(m[1]) else {
            throw IDEError("Cannot set a breakpoint at \(URL(fileURLWithPath:path).lastPathComponent):\(line). Choose an executable instruction, or click this breakpoint to remove it.\n"+result)
        }
        return id
    }
    func breakpoint(path: String, line: Int) throws -> [String:Any] {
        guard debugger?.running != true else { throw IDEError("Pause the target before changing breakpoints.") }
        let p = try requireProject(); _ = try p.allowed(path)
        guard line > 0 else { throw IDEError("Invalid line number.") }
        if let i = breakpoints.firstIndex(where:{$0["path"] as? String == path && $0["line"] as? Int == line}) {
            if let s = debugger, let id = breakpoints[i]["id"] as? Int { _ = try s.checked("delete \(id)") }
            breakpoints.remove(at:i)
        } else {
            var point: [String:Any] = ["path":path,"line":line]
            if let s = debugger { point["id"] = try installBreakpoint(s,path:path,line:line) }
            breakpoints.append(point)
        }
        return ["breakpoints":breakpoints]
    }
    func memory(type: String, address: String, count: Int, format: String = "xb") throws -> String {
        guard let s = debugger, !s.running else { throw IDEError("Start or pause a debug session to inspect memory.") }
        guard ["r","p","e","c","u","D"].contains(type), ["xb","i"].contains(format), address.range(of:"^(0[xX][0-9A-Fa-f]+|[0-9]+)$",options:.regularExpression) != nil, (1...512).contains(count) else { throw IDEError("Enter a valid memory address and a count between 1 and 512.") }
        return try s.checked("x /\(type)\(count)\(format) \(address)")
    }
    func writeRegister(name: String, value: String) throws -> String {
        guard let s = debugger, !s.running else { throw IDEError("Pause a debug session before editing a value.") }
        guard name.range(of:"^[A-Za-z_][A-Za-z0-9_.$]*$",options:.regularExpression) != nil, value.range(of:"^(0[xX][0-9a-fA-F]{1,2}|[0-9]{1,3})$",options:.regularExpression) != nil else { throw IDEError("Use a register name and a byte value (0–255 or 0x00–0xFF).") }
        let number = value.lowercased().hasPrefix("0x") ? Int(value.dropFirst(2),radix:16) : Int(value)
        guard let number, (0...255).contains(number) else { throw IDEError("The byte value must be between 0 and 255.") }
        let addr = try s.command("print /a \(name)")
        let address: String
        if let m = match(addr,"(?i)The Address of .+:\\s*(0x[0-9a-f]+)") { address = m[1] }
        else if let local = localDataSymbols[name] { address = "0x"+String(local,radix:16) }
        else { throw IDEError("Unable to resolve the address of \(name).") }
        return try s.checked("write /r \(address) 0x\(String(number,radix:16))")
    }
    func setPin(_ pin: String, high: Bool) throws -> String {
        guard let s = debugger, debugTool == "SIM", !s.running else { throw IDEError("Start and pause the simulator to change an input pin.") }
        guard pin.range(of:"^R[A-J][0-7]$",options:.regularExpression) != nil else { throw IDEError("Choose a PIC input pin, such as RB0.") }
        _ = try s.checked("write pin \(pin) \(high ? "high" : "low")")
        return try s.checked("print pin \(pin)")
    }
    func triggerInterrupt(_ source: String) throws -> String {
        guard let s = debugger, debugTool == "SIM", !s.running else { throw IDEError("Start and pause the simulator to raise an interrupt flag.") }
        let sources: [String:(String,Int)] = ["INT0":("INTCON",0x02),"INT1":("INTCON3",0x01),"INT2":("INTCON3",0x02),"TMR0":("INTCON",0x04),"TMR1":("PIR1",0x01),"TMR2":("PIR1",0x02),"ADC":("PIR1",0x40)]
        guard let (register,mask) = sources[source] else { throw IDEError("Unknown interrupt source.") }
        let output = try s.checked("print /x \(register)")
        guard let m = match(output,"=\\s*([0-9a-fA-F]+)"), let value = Int(m[1],radix:16) else { throw IDEError("Could not read the interrupt flag register.") }
        _ = try writeRegister(name:register,value:"0x"+String(value|mask,radix:16))
        return "Raised \(source) flag in \(register). Step or continue to service it. The source and global interrupt enables must already be set in your firmware."
    }
    func detectTools() throws -> String {
        if let debugger { return try debugger.command("hwtool") }
        let s = try newSession(); defer { s.stop() }; return try s.command("hwtool",timeout:30)
    }
    func program(index: Int = 0) throws -> [String:Any] {
        guard debugger == nil else { throw IDEError("Stop debugging before programming.") }
        guard index >= 0 else { throw IDEError("Invalid tool index.") }
        let p = try requireProject()
        if p.prebuilt == nil { let b = try build(); guard b["ok"] as? Bool == true else { throw IDEError("Fix the build errors before programming.") } }
        let hex = try p.artifact("hex",image:"production")
        let s = try newSession(); defer { s.stop() }
        _ = try s.checked("device PIC18F87K22")
        _ = try s.checked("set poweroptions.powerenable false")
        _ = try s.checked("hwtool PICkit3 -p \(index)",timeout:60)
        let result = try s.checked("program \(quoteMDB(hex.path))",timeout:120)
        guard result.lowercased().contains("program succeeded") else { throw IDEError("Programming was not confirmed.\n"+result) }
        return ["ok":true,"log":result,"image":hex.path]
    }
    func regenerate() throws -> String {
        guard debugger == nil else { throw IDEError("Stop debugging first.") }
        let p = try requireProject()
        let result = try runner.run(tc.java,["-Djava.awt.headless=true","-jar",tc.platform+"/lib/PrjMakefilesGenerator.jar",p.root.path],cwd:p.root,env:tc.environment,timeout:90,output:{self.onEvent("buildOutput",$0)})
        guard result.0 == 0 else { throw IDEError(result.1) }
        return result.1
    }
    func shutdown() { debugger?.stop(); debugger = nil; runner.cancel(); serial.disconnect() }
}
