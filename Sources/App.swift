import AppKit
import WebKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let core = IDECore()
    let ad2 = AD2Session()
    var window: NSWindow!
    var web: WKWebView!
    var content: WKUserContentController!
    var instrumentsWindow: NSWindow?
    var instrumentsWeb: WKWebView?
    let worker = DispatchQueue(label:"app.aster.operations")
    var closing = false
    var busy = false
    var testMode = false
    let resources = Bundle.main.resourceURL!
    var bridge: AsterBridge?
    var bridgeMenuItem: NSMenuItem?
    let captureLock = NSLock()
    var capture: String?
    func applicationDidFinishLaunching(_ notification: Notification) {
        testMode = CommandLine.arguments.contains("--ui-test")
        content = WKUserContentController(); content.add(self,name:"aster")
        let config = WKWebViewConfiguration(); config.userContentController = content
        web = WKWebView(frame:.zero,configuration:config)
        web.navigationDelegate = self; web.uiDelegate = self
        web.setValue(false,forKey:"drawsBackground")
        if #available(macOS 13.3, *) { web.isInspectable = true }
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1440,height:930),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = "Aster — PIC18 workspace"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed:0.098,green:0.133,blue:0.180,alpha:1)
        window.minSize = NSSize(width:1000,height:700); window.contentView = web; window.delegate = self
        window.setFrameAutosaveName("AsterMainWindow"); window.center()
        window.appearance = NSAppearance(named:.darkAqua)
        menu()
        core.onEvent = { [weak self] name,value in self?.captureOutput(name,value); self?.event(name,value) }
        core.onConfirmation = { [weak self] message in
            // MDB runs on the operation queue; keep the window responsive while
            // its command waits for the user's answer on the main queue.
            let answer = DispatchSemaphore(value:0)
            var accepted = false
            DispatchQueue.main.async {
                guard let self else { answer.signal(); return }
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Confirm the connected device"
                alert.informativeText = message
                alert.addButton(withTitle:"Continue")
                alert.addButton(withTitle:"Cancel")
                alert.beginSheetModal(for:self.window) { response in
                    accepted = response == .alertFirstButtonReturn
                    answer.signal()
                }
            }
            answer.wait()
            return accepted
        }
        core.serial.onData = { [weak self] text in self?.event("serialData",text) }
        web.loadFileURL(resources.appendingPathComponent("Web/index.html"),allowingReadAccessTo:resources)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        if !testMode { restoreBridge() }
    }
    func menu() {
        let bar = NSMenu(); NSApp.mainMenu = bar
        let appItem = NSMenuItem(); bar.addItem(appItem); let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle:"About Aster",action:#selector(about),keyEquivalent:"").target = self
        appMenu.addItem(.separator()); appMenu.addItem(withTitle:"Quit Aster",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        for (name,entries) in [("File",[("Open Project…","open","o"),("New Project…","new","n"),("Save","save","s"),("Save All","saveAll","S")]),("Edit",[("Undo","undo:","z"),("Redo","redo:","Z"),("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a"),("Find","find","f")]),("Project",[("Build","build","b"),("Clean","clean",""),("Regenerate Makefiles","regenerate",""),("Reveal in Finder","reveal",""),("Toolchain Settings","settings",",")]),("Debug",[("Start Session","debug","d"),("Continue / Pause","toggleRun",""),("Step Instruction","stepi",""),("Step Over","next",""),("Reset","reset",""),("Stop Session","stop","")])] {
            let item = NSMenuItem(); bar.addItem(item); let submenu = NSMenu(title:name); item.submenu = submenu
            for (title,action,key) in entries { let m = NSMenuItem(title:title,action:action.hasSuffix(":") ? NSSelectorFromString(action) : #selector(menuAction(_:)),keyEquivalent:key); if !action.hasSuffix(":") { m.target = self; m.representedObject = action }; submenu.addItem(m) }
        }
        if let project = bar.items.first(where:{ $0.submenu?.title == "Project" })?.submenu {
            project.addItem(.separator())
            let toggle = NSMenuItem(title:"Claude Bridge",action:#selector(toggleBridge),keyEquivalent:""); toggle.target = self; project.addItem(toggle); bridgeMenuItem = toggle
            project.addItem(withTitle:"Choose Bridge Folder…",action:#selector(chooseBridgeFolder),keyEquivalent:"").target = self
            project.addItem(withTitle:"Reveal Bridge Folder",action:#selector(revealBridgeFolder),keyEquivalent:"").target = self
        }
        let wi = NSMenuItem(); bar.addItem(wi); let wm = NSMenu(title:"Window"); wi.submenu = wm; NSApp.windowsMenu = wm
        wm.addItem(withTitle:"Minimize",action:#selector(NSWindow.miniaturize(_:)),keyEquivalent:"m")
        wm.addItem(withTitle:"Zoom",action:#selector(NSWindow.zoom(_:)),keyEquivalent:"")
        wm.addItem(.separator()); wm.addItem(withTitle:"Instruments",action:#selector(openInstruments),keyEquivalent:"I").target = self
    }
    // analog discovery scope/logic analyzer in its own window, loading the same page in instruments mode
    @objc func openInstruments() {
        if let w = instrumentsWindow { w.makeKeyAndOrderFront(nil); return }
        let config = WKWebViewConfiguration(); config.userContentController = content
        let view = WKWebView(frame:.zero,configuration:config); view.navigationDelegate = self; view.uiDelegate = self; view.setValue(false,forKey:"drawsBackground")
        if #available(macOS 13.3, *) { view.isInspectable = true }
        let w = NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        w.title = "Aster Instruments — Analog Discovery 2"; w.isReleasedWhenClosed = false; w.minSize = NSSize(width:760,height:520); w.contentView = view; w.delegate = self
        w.backgroundColor = window.backgroundColor; w.appearance = NSAppearance(named:.darkAqua)
        if !w.setFrameUsingName("AsterInstrumentsWindow") { w.center() }; w.setFrameAutosaveName("AsterInstrumentsWindow")
        instrumentsWindow = w; instrumentsWeb = view
        view.loadFileURL(URL(string:resources.appendingPathComponent("Web/index.html").absoluteString+"#instruments")!,allowingReadAccessTo:resources)
        w.makeKeyAndOrderFront(nil); event("instrumentsWindow",true)
    }
    @objc func menuAction(_ sender: NSMenuItem) { if let action = sender.representedObject as? String { event("menu",action) } }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Aster",.applicationVersion:"0.1.0",.version:"PIC18F87K22 · MPLAB X 6.20",.credits:NSAttributedString(string:"A focused workspace for PIC development.\nBuilt for your EasyPIC PRO v7 labs.")]) }
    // events reach the main window and the instruments window; each page ignores what it does not show
    func event(_ name: String, _ value: Any) { DispatchQueue.main.async { [weak self] in for view in [self?.web,self?.instrumentsWeb].compactMap({$0}) { view.evaluateJavaScript("window.asterEvent?.(\(jsonString(name)),\(jsonString(value)))",completionHandler:nil) } } }
    // the instruments page prefixes its request ids with "i"
    func page(_ id: String) -> WKWebView { id.hasPrefix("i") ? instrumentsWeb ?? web : web }
    func host(_ id: String) -> NSWindow { id.hasPrefix("i") ? instrumentsWindow ?? window : window }
    func respond(_ id: String, value: Any? = nil, error: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.page(id).evaluateJavaScript("window.asterResponse(\(jsonString(id)),\(jsonString(value ?? NSNull())),\(jsonString(error ?? "")))",completionHandler:nil)
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String:Any], let id = body["id"] as? String, let op = body["op"] as? String else { return }
        let args = body["args"] as? [String:Any] ?? [:]
        if op == "cancel" { core.runner.cancel(); respond(id,value:true); return }
        if op == "chooseProject" {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.treatsFilePackagesAsDirectories = true; panel.prompt = "Open Project"
            panel.message = "Select an MPLAB .X folder, or a prebuilt HEX / ELF image."
            panel.directoryURL = URL(fileURLWithPath:NSHomeDirectory()+"/MPLABXProjects")
            panel.beginSheetModal(for:window) { response in self.respond(id,value:response == .OK ? panel.url?.path ?? "" : "") }; return
        }
        if op == "chooseSource" {
            let panel = NSOpenPanel();panel.allowsMultipleSelection = false;panel.canChooseDirectories = false
            panel.message = "Choose the starter to copy into the current editor tab. The original file stays unchanged."
            panel.beginSheetModal(for:window) { response in
                guard response == .OK,let url = panel.url else { self.respond(id,value:NSNull());return }
                do {
                    guard ["c","h","asm","s","inc"].contains(url.pathExtension.lowercased()) else { throw IDEError("Choose a C, header, or assembly source file.") }
                    let data = try Data(contentsOf:url);guard data.count <= 2_000_000 else { throw IDEError("Source file is too large.") }
                    let content = String(data:data,encoding:.utf8) ?? String(data:data,encoding:.isoLatin1) ?? ""
                    self.respond(id,value:["name":url.lastPathComponent,"content":content])
                } catch {self.respond(id,error:error.localizedDescription)}
            };return
        }
        if op == "exportText" {
            guard let content=args["content"] as? String,content.utf8.count <= 4_000_000,let name=args["name"] as? String else {respond(id,error:"Invalid export.");return}
            let panel=NSSavePanel();panel.nameFieldStringValue=URL(fileURLWithPath:name).lastPathComponent;panel.canCreateDirectories=true
            panel.beginSheetModal(for:host(id)) { response in
                guard response == .OK,let url=panel.url else {self.respond(id,value:false);return}
                do {try content.write(to:url,atomically:true,encoding:.utf8);self.respond(id,value:true)}catch {self.respond(id,error:error.localizedDescription)}
            };return
        }
        if op == "chooseNew" {
            let panel = NSSavePanel(); panel.title = "Create PIC18 Project"; panel.nameFieldStringValue = "MyProject.X"; panel.message = "Creates an MPLAB-compatible assembly or XC8 C project."; panel.canCreateDirectories = true
            panel.beginSheetModal(for:window) { response in self.respond(id,value:response == .OK ? panel.url?.path ?? "" : "") }; return
        }
        if op == "confirm" {
            let alert = NSAlert(); alert.messageText = args["title"] as? String ?? "Continue?"; alert.informativeText = args["message"] as? String ?? ""; alert.addButton(withTitle:args["accept"] as? String ?? "Continue"); alert.addButton(withTitle:"Cancel")
            alert.beginSheetModal(for:host(id)) { self.respond(id,value:$0 == .alertFirstButtonReturn) }; return
        }
        if op == "openInstruments" { openInstruments(); respond(id,value:true); return }
        if op == "instrumentsEval", testMode {
            guard let view = instrumentsWeb, let js = args["js"] as? String else { respond(id,error:"The instruments window is not open."); return }
            view.callAsyncJavaScript(js,arguments:[:],in:nil,in:.page) { result in
                switch result { case .success(let value): self.respond(id,value:value); case .failure(let error): self.respond(id,error:error.localizedDescription) }
            }; return
        }
        if op == "testEvent", testMode { event(args["name"] as? String ?? "",args["value"] ?? NSNull()); respond(id,value:true); return }
        if op == "closeApproved" { closing = true; respond(id,value:true); NSApp.terminate(nil); return }
        if op == "reveal" {
            let path = args["path"] as? String ?? core.project?.root.path ?? resources.path
            let url = URL(fileURLWithPath:path)
            NSWorkspace.shared.activateFileViewerSelecting([url]); respond(id,value:true); return
        }
        if op == "openDoc" {
            guard let data = try? Data(contentsOf:resources.appendingPathComponent("references.json")),
                  let names = try? JSONDecoder().decode([String:String].self,from:data),
                  let key = args["key"] as? String, let filename = names[key] else { respond(id,error:"Unknown reference."); return }
            var folders = [URL]()
            if let saved = UserDefaults.standard.string(forKey:"referenceFolder") { folders.append(URL(fileURLWithPath:saved)) }
            if let root = core.project?.root { folders += [root,root.deletingLastPathComponent(),root.deletingLastPathComponent().deletingLastPathComponent()] }
            folders += [URL(fileURLWithPath:NSHomeDirectory()+"/Downloads"),resources.appendingPathComponent("References")]
            if key == "assembler" { folders.insert(URL(fileURLWithPath:core.tc.xc8+"/docs"),at:0) }
            let candidates = folders.flatMap { folder in ([""] + (1...5).map{"lab\($0)"}).map { folder.appendingPathComponent($0).appendingPathComponent(filename) } }
            if let url = candidates.first(where:{FileManager.default.fileExists(atPath:$0.path)}) {
                respond(id,value:NSWorkspace.shared.open(url)); return
            }
            // Let the user locate their local reference once, without copying course files into the app.
            let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.pdf]; panel.message = "Locate " + filename
            panel.beginSheetModal(for:window) { response in
                guard response == .OK, let url = panel.url else { self.respond(id,value:false); return }
                UserDefaults.standard.set(url.deletingLastPathComponent().path,forKey:"referenceFolder")
                self.respond(id,value:NSWorkspace.shared.open(url))
            }; return
        }

        if op == "uiTestDone", testMode {
            let dir = resources.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests")
            try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            if JSONSerialization.isValidJSONObject(args) { do { try JSONSerialization.data(withJSONObject:args,options:.prettyPrinted).write(to:dir.appendingPathComponent("ui-result.json")) } catch { FileHandle.standardError.write(Data("ui-result.json: \(error)\n".utf8)) } } else { FileHandle.standardError.write(Data("ui-result.json: not valid JSON \(args)\n".utf8)) }
            func save(_ image: NSImage?, _ name: String) { if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data:tiff), let data = rep.representation(using:.png,properties:[:]) { try? data.write(to:dir.appendingPathComponent(name)) } }
            web.takeSnapshot(with:nil) { image,_ in
                save(image,"ui-screenshot.png")
                guard let view = self.instrumentsWeb else { self.closing = true; NSApp.terminate(nil); return }
                view.takeSnapshot(with:nil) { image,_ in save(image,"ui-instruments-screenshot.png"); self.closing = true; NSApp.terminate(nil) }
            }; return
        }
        worker.async {
            do { self.respond(id,value:try self.perform(op,args)) } catch { self.respond(id,error:error.localizedDescription) }
        }
    }
    func perform(_ op: String, _ args: [String:Any]) throws -> Any {
        func str(_ key: String,_ fallback: String = "") -> String { args[key] as? String ?? fallback }
        func int(_ key: String,_ fallback: Int = 0) -> Int { args[key] as? Int ?? fallback }
        switch op {
        case "ad2Status", "ad2Capture", "ad2Run":
            let helper = resources.appendingPathComponent("aster-ad2")
            guard FileManager.default.isExecutableFile(atPath:helper.path) else { throw IDEError("Analog Discovery capture helper is missing from this app build.") }
            if op == "ad2Run" {
                let id = try ad2.start(helper.path,try AD2Session.arguments(args),frame:{ id,frame in self.event("ad2Frame",["run":id,"frame":frame]) },ended:{ id,error in self.event("ad2Stopped",["run":id,"error":error]) })
                return ["run":id]
            }
            var parameters = ["status"]
            if op == "ad2Capture" { parameters = ["capture"]+(try AD2Session.arguments(args)); ad2.stop(wait:true) }
            let (code,output) = try CommandRunner().run(helper.path,parameters,timeout:16)
            guard code == 0, let data = output.data(using:.utf8), let object = try? JSONSerialization.jsonObject(with:data) else { throw IDEError(output.trimmingCharacters(in:.whitespacesAndNewlines)) }
            return object
        case "ad2Stop":
            ad2.stop(wait:true); return true
        case "bootstrap":
            let defaults = UserDefaults.standard
            if let path = defaults.string(forKey:"mplab") { core.tc.mplab = path }
            if let path = defaults.string(forKey:"xc8") { core.tc.xc8 = path }
            let root = NSHomeDirectory()+"/MPLABXProjects"
            let found = ((try? FileManager.default.contentsOfDirectory(atPath:root)) ?? []).filter{$0.hasSuffix(".X")}.map{root+"/"+$0}
            return ["bridge":bridgeState(),"tools":core.tc.status(),"recent":Array(Set((defaults.stringArray(forKey:"recent") ?? [])+found)).sorted(),"device":try deviceData(),"ports":core.serial.ports(),"initialProject":CommandLine.arguments.firstIndex(of:"--open-project").flatMap { CommandLine.arguments.indices.contains($0+1) ? CommandLine.arguments[$0+1] : nil } ?? "","testMode":testMode,"testProject":testMode ? resources.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/UIProject.X").path : ""]
        case "open":
            let result = try core.open(str("path")); let defaults = UserDefaults.standard
            var recent = defaults.stringArray(forKey:"recent") ?? []; recent.removeAll{$0 == str("path")}; recent.insert(str("path"),at:0); if !testMode { defaults.set(Array(recent.prefix(12)),forKey:"recent") }
            DispatchQueue.main.async { self.window.title = "\(self.core.project?.name ?? "Aster") — Aster" }; return result
        case "new":
            var url = URL(fileURLWithPath:str("path")); if url.pathExtension != "X" { url.appendPathExtension("X") }
            guard url.deletingPathExtension().lastPathComponent.range(of:"^[A-Za-z][A-Za-z0-9_-]*$",options:.regularExpression) != nil else { throw IDEError("Use letters, numbers, underscores, or hyphens for the project name.") }
            guard !FileManager.default.fileExists(atPath:url.path) else { throw IDEError("A folder already exists there. Choose a new project name.") }
            let kind = str("template", "blank")
            guard ["blank", "basic", "interrupt", "c"].contains(kind) else { throw IDEError("Choose a blank project or an available template.") }
            let template = resources.appendingPathComponent(kind == "interrupt" ? "InterruptTemplate.X" : kind == "c" ? "CTemplate.X" : "Template.X")
            try FileManager.default.copyItem(at:template,to:url)
            if let e = FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.isRegularFileKey]) { for case let file as URL in e {
                if (try? file.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true, let source = try? String(contentsOf:file,encoding:.utf8) {
                    try source.replacingOccurrences(of:"Template.X",with:url.lastPathComponent).replacingOccurrences(of:"<name>Template</name>",with:"<name>\(url.deletingPathExtension().lastPathComponent)</name>").write(to:file,atomically:true,encoding:.utf8)
                }
            } }
            if kind == "blank" {
                // Keep the MPLAB build configuration, but start with no example code.
                try "".write(to:url.appendingPathComponent("main.asm"),atomically:true,encoding:.utf8)
            }
            let result = try core.open(url.path)
            if kind == "c" {
                do { _ = try core.regenerate() }
                catch { self.core.onEvent("buildOutput", "Project created. Regenerate Makefiles after setting up the Microchip tools.\n" + error.localizedDescription + "\n") }
            }
            return result
        case "addSource":
            guard core.debugger == nil else {throw IDEError("Stop debugging before adding files.")}
            let project=try core.requireProject(),file=try project.addSource(str("name"))
            var warning=""
            do {_ = try core.regenerate()}catch {warning="File added. Use Regenerate Makefiles before building: " + error.localizedDescription}
            return ["project":project.info(),"path":file.path,"warning":warning]
        case "setWatches":
            let project = try core.requireProject()
            guard str("projectPath") == project.root.path, let names = args["watches"] as? [String] else { throw IDEError("The project changed before its watches could be saved.") }
            try project.saveWatches(names); return true
        case "project": return try core.requireProject().info()
        case "configuration": try core.requireProject().select(str("name")); return try core.requireProject().info()
        case "read": return try core.requireProject().read(str("path"))
        case "save": return try core.requireProject().save(str("path"),content:str("content"),expected:str("digest"),encoding:str("encoding","utf8"))
        case "build": return try core.build(debug:args["debug"] as? Bool ?? false)
        case "clean":
            _ = try core.build(clean:true); return try core.build(clean:true,debug:true)
        case "regenerate": return try core.regenerate()
        case "debugStart": return try core.startDebug(tool:str("tool","SIM"),index:int("index"),clockMHz:args["clockMHz"] as? Double,accumulateStopwatch:args["accumulateStopwatch"] as? Bool ?? false)
        case "debugAction": return try core.debugAction(str("action"),names:args["names"] as? [String] ?? ["WREG","STATUS","BSR"])
        case "resetStopwatch": return try core.resetStopwatch()
        case "inspect": return try core.inspect(args["names"] as? [String] ?? [])
        case "breakpoint": return try core.breakpoint(path:str("path"),line:int("line",1))
        case "resolveAddress": return try core.resolveAddress(str("address"))
        case "pointerAddress": return try core.pointerAddress(str("pointer"))
        case "fullDisassembly": return try core.fullDisassembly()
        case "memory": return try core.memory(type:str("type","r"),address:str("address","0x0"),count:int("count",64),format:str("format","xb"))
        case "writeRegister": return try core.writeRegister(name:str("name"),value:str("value"))
        case "debugCommand": guard let s = core.debugger else { throw IDEError("Start debugging first.") }; return try s.command(str("command"))
        case "stack": guard let s = core.debugger, !s.running else { throw IDEError("Pause a debug session first.") }; return try s.command("backtrace")
        case "setPin": return try core.setPin(str("pin"),high:args["high"] as? Bool ?? false)
        case "triggerInterrupt": return try core.triggerInterrupt(str("source"))
        case "detectTools": return try core.detectTools()
        case "program": return try core.program(index:int("index"))
        case "serialPorts": return core.serial.ports()
        case "serialConnect": try core.serial.connect(str("path"),baud:int("baud",19200)); return true
        case "serialDisconnect": core.serial.disconnect(); return true
        case "serialSend": try core.serial.send(str("text")); return true
        case "settings":
            guard core.debugger == nil else { throw IDEError("Stop debugging before changing tools.") }
            let candidate = Toolchain(mplab:str("mplab"),xc8:str("xc8"))
            guard candidate.status().allSatisfy({$0["available"] as? Bool == true}) else { throw IDEError("Some tool files are missing from these paths.") }
            core.tc = candidate; UserDefaults.standard.set(candidate.mplab,forKey:"mplab"); UserDefaults.standard.set(candidate.xc8,forKey:"xc8"); return candidate.status()
        default: throw IDEError("Unknown operation: "+op)
        }
    }
    // MARK: claude bridge

    func bridgeState() -> [String:Any] { ["enabled":bridge != nil,"folder":bridge?.folder.path ?? UserDefaults.standard.string(forKey:"bridgeFolder") ?? ""] }
    func restoreBridge() {
        let args = CommandLine.arguments, defaults = UserDefaults.standard
        if let i = args.firstIndex(of:"--bridge"), args.indices.contains(i+1) { startBridge(URL(fileURLWithPath:(args[i+1] as NSString).expandingTildeInPath)); return }
        if defaults.bool(forKey:"bridgeEnabled"), let path = defaults.string(forKey:"bridgeFolder") { startBridge(URL(fileURLWithPath:path)) }
    }
    func startBridge(_ folder: URL) {
        bridge?.stop(); bridge = nil
        let b = AsterBridge(folder:folder,version:"0.1.0")
        b.handler = { [weak self] op,args,reply in
            guard let self else { reply(nil,"Aster is closing.",""); return }
            self.handleBridge(op,args,reply)
        }
        do { try b.start() } catch {
            let alert = NSAlert(); alert.messageText = "Claude Bridge could not start"; alert.informativeText = error.localizedDescription; alert.runModal(); return
        }
        bridge = b
        UserDefaults.standard.set(folder.path,forKey:"bridgeFolder"); UserDefaults.standard.set(true,forKey:"bridgeEnabled")
        bridgeChanged()
    }
    func stopBridge() {
        bridge?.stop(); bridge = nil
        UserDefaults.standard.set(false,forKey:"bridgeEnabled")
        bridgeChanged()
    }
    func bridgeChanged() {
        bridgeMenuItem?.state = bridge == nil ? .off : .on
        event("bridgeState",bridgeState())
        updateBridgeStatus()
    }
    func updateBridgeStatus() {
        guard let bridge else { return }
        let p = core.project
        bridge.update(["project":p?.root.path ?? "","projectName":p?.name ?? "","debugging":core.debugger != nil,"running":core.debugger?.running ?? false,"tool":core.debugTool])
    }
    @objc func toggleBridge() {
        if bridge != nil { stopBridge(); return }
        if let path = UserDefaults.standard.string(forKey:"bridgeFolder") { startBridge(URL(fileURLWithPath:path)) } else { chooseBridgeFolder() }
    }
    @objc func chooseBridgeFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"; panel.message = "Choose a folder Claude can reach. Aster reads requests from it and writes results back."
        if let path = UserDefaults.standard.string(forKey:"bridgeFolder") { panel.directoryURL = URL(fileURLWithPath:path) }
        panel.beginSheetModal(for:window) { response in if response == .OK, let url = panel.url { self.startBridge(url) } }
    }
    @objc func revealBridgeFolder() {
        guard let path = bridge?.folder.path ?? UserDefaults.standard.string(forKey:"bridgeFolder") else { NSSound.beep(); return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:path)])
    }
    func captureOutput(_ name: String,_ value: Any) {
        guard name == "buildOutput" || name == "debugOutput", let text = value as? String else { return }
        captureLock.lock(); if capture != nil { capture! += text; if capture!.count > 400_000 { capture = String(capture!.suffix(200_000)) } }; captureLock.unlock()
    }
    // ask the main thread a yes/no question from the operation queue
    func confirmFromWorker(_ title: String,_ message: String) -> Bool {
        let answer = DispatchSemaphore(value:0); var accepted = false
        DispatchQueue.main.async {
            NSApp.requestUserAttention(.criticalRequest)
            let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = title; alert.informativeText = message
            alert.addButton(withTitle:"Allow"); alert.addButton(withTitle:"Cancel")
            alert.beginSheetModal(for:self.window) { response in accepted = response == .alertFirstButtonReturn; answer.signal() }
        }
        answer.wait(); return accepted
    }
    func uiHasUnsavedEdits() -> Bool {
        let answer = DispatchSemaphore(value:0); var dirty = false
        DispatchQueue.main.async {
            self.web.evaluateJavaScript("window.asterHasUnsaved?.() === true") { value,_ in dirty = value as? Bool ?? false; answer.signal() }
        }
        _ = answer.wait(timeout:.now()+3); return dirty
    }
    func waitStop(_ args: [String:Any]) throws -> Any {
        let timeout = min(max(args["timeout"] as? Double ?? 10,0.05),150)
        let deadline = Date().addingTimeInterval(timeout)
        while let s = core.debugger, s.running, Date() < deadline { Thread.sleep(forTimeInterval:0.05) }
        guard let s = core.debugger else { throw IDEError("Start a debug session first.") }
        if s.running { return ["state":"running","timedOut":true] }
        core.onEvent("debugState",["state":"paused","tool":core.debugTool])
        return try core.inspect(args["names"] as? [String] ?? ["WREG","STATUS","BSR"])
    }
    func bridgeScreenshot(_ reply: @escaping AsterBridge.Reply) {
        DispatchQueue.main.async {
            self.web.takeSnapshot(with:nil) { image,error in
                guard let folder = self.bridge?.screenshots, let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data:tiff), let png = rep.representation(using:.png,properties:[:]) else {
                    reply(nil,error?.localizedDescription ?? "Could not capture the Aster window.",""); return
                }
                do {
                    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    let url = folder.appendingPathComponent("aster-\(Int(Date().timeIntervalSince1970*1000)).png")
                    try png.write(to:url); reply(["path":url.path,"width":rep.pixelsWide,"height":rep.pixelsHigh],nil,"")
                } catch { reply(nil,error.localizedDescription,"") }
            }
        }
    }
    // ops whose results the web ui uses to stay in sync with what claude did
    static let bridgeSyncOps: Set<String> = ["open","new","debugStart","debugAction","inspect","waitStop","resetStopwatch","breakpoint","addSource","configuration","project","ad2Capture","ad2Run"]
    static let bridgeUIActions: Set<String> = ["build","clean","debug","stop","stepi","next","reset","toggleRun","saveAll","regenerate"]
    func handleBridge(_ op: String,_ args: [String:Any],_ reply: @escaping AsterBridge.Reply) {
        event("bridge",["phase":"start","op":op])
        let finish: AsterBridge.Reply = { [weak self] value,error,output in
            guard let self else { reply(value,error,output); return }
            let synced: Any = error == nil && AppDelegate.bridgeSyncOps.contains(op) ? (value ?? NSNull()) : NSNull()
            self.event("bridge",["phase":"end","op":op,"args":args,"ok":error == nil,"error":error ?? "","value":synced])
            self.updateBridgeStatus()
            reply(value,error,output)
        }
        switch op {
        case "ping":
            finish(["bridge":bridgeState(),"tools":core.tc.status(),"project":core.project.map { $0.info() as Any } ?? NSNull(),"debugging":core.debugger != nil,"running":core.debugger?.running ?? false],nil,"")
        case "screenshot":
            bridgeScreenshot(finish)
        case "openInstruments":
            DispatchQueue.main.async { self.openInstruments(); finish(true,nil,"") }
        case "uiAction":
            let name = args["action"] as? String ?? ""
            guard AppDelegate.bridgeUIActions.contains(name) else { finish(nil,"Unsupported UI action. Use one of: "+AppDelegate.bridgeUIActions.sorted().joined(separator:", "),""); return }
            event("menu",name); finish(true,nil,"")
        case "settings","bootstrap","save":
            finish(nil,"\(op) is not available through the bridge. Edit files on disk instead of using save.","")
        default:
            worker.async {
                do {
                    if op == "open" || op == "new", self.uiHasUnsavedEdits() { throw IDEError("Aster has unsaved edits. Save them before switching projects.") }
                    if op == "program" {
                        guard self.confirmFromWorker("Claude wants to program the board","Build and program the production image with PICkit 3 (tool index \(args["index"] as? Int ?? 0)). The EasyPIC board must be on its own power supply.") else { throw IDEError("Programming was declined in Aster.") }
                    }
                    if op == "debugStart", (args["tool"] as? String ?? "SIM") != "SIM" {
                        guard self.confirmFromWorker("Claude wants to debug on hardware","Start a PICkit 3 debug session on the connected board. The EasyPIC board must be on its own power supply.") else { throw IDEError("Hardware debugging was declined in Aster.") }
                    }
                    self.captureLock.lock(); self.capture = ""; self.captureLock.unlock()
                    defer { self.captureLock.lock(); self.capture = nil; self.captureLock.unlock() }
                    let value = try op == "waitStop" ? self.waitStop(args) : self.perform(op,args)
                    self.captureLock.lock(); let output = op == "build" || op == "clean" ? "" : (self.capture ?? ""); self.captureLock.unlock()
                    finish(value,nil,output)
                } catch { finish(nil,error.localizedDescription,"") }
            }
        }
    }

    func deviceData() throws -> Any {
        let url = resources.appendingPathComponent("device.json")
        return try JSONSerialization.jsonObject(with:Data(contentsOf:url))
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
        if let url = navigationAction.request.url, url.isFileURL, url.standardizedFileURL.path.hasPrefix(resources.path+"/") { decisionHandler(.allow) } else { decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ()->Void) {
        let a = NSAlert(); a.messageText = message; a.beginSheetModal(for:window) { _ in completionHandler() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if sender === instrumentsWindow || closing { return true }; event("requestClose",true); return false }
    // closing the instruments window stops a running acquisition, like waveforms
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === instrumentsWindow else { return }
        ad2.stop(); instrumentsWeb?.navigationDelegate = nil; instrumentsWindow = nil; instrumentsWeb = nil; event("instrumentsWindow",false)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { if closing { return .terminateNow }; event("requestClose",true); return .terminateCancel }
    func applicationWillTerminate(_ notification: Notification) { bridge?.stop(); ad2.stop(wait:true); core.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct AsterMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
}
