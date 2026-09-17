import AppKit
import WebKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let core = IDECore()
    var window: NSWindow!
    var web: WKWebView!
    let worker = DispatchQueue(label:"app.aster.operations")
    var closing = false
    var busy = false
    var testMode = false
    let resources = Bundle.main.resourceURL!
    func applicationDidFinishLaunching(_ notification: Notification) {
        testMode = CommandLine.arguments.contains("--ui-test")
        let content = WKUserContentController(); content.add(self,name:"aster")
        let config = WKWebViewConfiguration(); config.userContentController = content
        web = WKWebView(frame:.zero,configuration:config)
        web.navigationDelegate = self; web.uiDelegate = self
        web.setValue(false,forKey:"drawsBackground")
        if #available(macOS 13.3, *) { web.isInspectable = true }
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1440,height:930),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = "Aster — PIC18 workspace"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed:0.043,green:0.055,blue:0.075,alpha:1)
        window.minSize = NSSize(width:1000,height:700); window.contentView = web; window.delegate = self
        window.setFrameAutosaveName("AsterMainWindow"); window.center()
        window.appearance = NSAppearance(named:.darkAqua)
        menu()
        core.onEvent = { [weak self] name,value in self?.event(name,value) }
        core.serial.onData = { [weak self] text in self?.event("serialData",text) }
        web.loadFileURL(resources.appendingPathComponent("Web/index.html"),allowingReadAccessTo:resources)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
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
        let wi = NSMenuItem(); bar.addItem(wi); let wm = NSMenu(title:"Window"); wi.submenu = wm; NSApp.windowsMenu = wm
        wm.addItem(withTitle:"Minimize",action:#selector(NSWindow.miniaturize(_:)),keyEquivalent:"m")
        wm.addItem(withTitle:"Zoom",action:#selector(NSWindow.zoom(_:)),keyEquivalent:"")
    }
    @objc func menuAction(_ sender: NSMenuItem) { if let action = sender.representedObject as? String { event("menu",action) } }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Aster",.applicationVersion:"0.1.0",.version:"PIC18F87K22 · MPLAB X 6.20",.credits:NSAttributedString(string:"A focused workspace for PIC development.\nBuilt for your EasyPIC PRO v7 labs.")]) }
    func event(_ name: String, _ value: Any) { DispatchQueue.main.async { [weak self] in self?.web.evaluateJavaScript("window.asterEvent?.(\(jsonString(name)),\(jsonString(value)))",completionHandler:nil) } }
    func respond(_ id: String, value: Any? = nil, error: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.web.evaluateJavaScript("window.asterResponse(\(jsonString(id)),\(jsonString(value ?? NSNull())),\(jsonString(error ?? "")))",completionHandler:nil)
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
        if op == "chooseNew" {
            let panel = NSSavePanel(); panel.title = "Create PIC18 Assembly Project"; panel.nameFieldStringValue = "MyProject.X"; panel.message = "Creates an MPLAB-compatible assembly project with reset and interrupt vectors."; panel.canCreateDirectories = true
            panel.beginSheetModal(for:window) { response in self.respond(id,value:response == .OK ? panel.url?.path ?? "" : "") }; return
        }
        if op == "confirm" {
            let alert = NSAlert(); alert.messageText = args["title"] as? String ?? "Continue?"; alert.informativeText = args["message"] as? String ?? ""; alert.addButton(withTitle:args["accept"] as? String ?? "Continue"); alert.addButton(withTitle:"Cancel")
            alert.beginSheetModal(for:window) { self.respond(id,value:$0 == .alertFirstButtonReturn) }; return
        }
        if op == "closeApproved" { closing = true; respond(id,value:true); NSApp.terminate(nil); return }
        if op == "reveal" {
            let path = args["path"] as? String ?? core.project?.root.path ?? resources.path
            let url = URL(fileURLWithPath:path)
            NSWorkspace.shared.activateFileViewerSelecting([url]); respond(id,value:true); return
        }
        if op == "openDoc" {
            let allowed = ["datasheet":"PIC18F87K22.pdf","board":"easypic-pro-v7-manual-v101.pdf","lab1":"Lab1_Intro_Micro_DevBoard.pdf","lab2":"Lab2_Learning_the_PIC_Development_Environment.pdf","lab3":"Lab3_Basic_Input_and_Output.pdf","assembler":"MPLAB_XC8_PIC_Assembler_User_Guide.pdf"]
            guard let key = args["key"] as? String, let filename = allowed[key] else { respond(id,error:"Unknown reference."); return }
            let path = key == "assembler" ? core.tc.xc8+"/docs/"+filename : NSHomeDirectory()+"/Downloads/"+filename
            if FileManager.default.fileExists(atPath:path) { NSWorkspace.shared.open(URL(fileURLWithPath:path)); respond(id,value:true) } else { respond(id,error:"Reference not found in Downloads: "+filename) }; return
        }
        if op == "uiTestDone", testMode {
            let dir = resources.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests")
            try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            try? JSONSerialization.data(withJSONObject:args,options:.prettyPrinted).write(to:dir.appendingPathComponent("ui-result.json"))
            web.takeSnapshot(with:nil) { image,error in
                if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data:tiff), let data = rep.representation(using:.png,properties:[:]) { try? data.write(to:dir.appendingPathComponent("ui-screenshot.png")) }
                self.closing = true; NSApp.terminate(nil)
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
        case "bootstrap":
            let defaults = UserDefaults.standard
            if let path = defaults.string(forKey:"mplab") { core.tc.mplab = path }
            if let path = defaults.string(forKey:"xc8") { core.tc.xc8 = path }
            let root = NSHomeDirectory()+"/MPLABXProjects"
            let found = ((try? FileManager.default.contentsOfDirectory(atPath:root)) ?? []).filter{$0.hasSuffix(".X")}.map{root+"/"+$0}
            return ["tools":core.tc.status(),"recent":Array(Set((defaults.stringArray(forKey:"recent") ?? [])+found)).sorted(),"device":try deviceData(),"ports":core.serial.ports(),"initialProject":CommandLine.arguments.firstIndex(of:"--open-project").flatMap { CommandLine.arguments.indices.contains($0+1) ? CommandLine.arguments[$0+1] : nil } ?? "","testMode":testMode,"testProject":testMode ? resources.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/UIProject.X").path : ""]
        case "open":
            let result = try core.open(str("path")); let defaults = UserDefaults.standard
            var recent = defaults.stringArray(forKey:"recent") ?? []; recent.removeAll{$0 == str("path")}; recent.insert(str("path"),at:0); if !testMode { defaults.set(Array(recent.prefix(12)),forKey:"recent") }
            DispatchQueue.main.async { self.window.title = "\(self.core.project?.name ?? "Aster") — Aster" }; return result
        case "new":
            var url = URL(fileURLWithPath:str("path")); if url.pathExtension != "X" { url.appendPathExtension("X") }
            guard url.deletingPathExtension().lastPathComponent.range(of:"^[A-Za-z][A-Za-z0-9_-]*$",options:.regularExpression) != nil else { throw IDEError("Use letters, numbers, underscores, or hyphens for the project name.") }
            guard !FileManager.default.fileExists(atPath:url.path) else { throw IDEError("A folder already exists there. Choose a new project name.") }
            let template = resources.appendingPathComponent(str("template") == "interrupt" ? "InterruptTemplate.X" : "Template.X")
            try FileManager.default.copyItem(at:template,to:url)
            if let e = FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.isRegularFileKey]) { for case let file as URL in e {
                if (try? file.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true, let source = try? String(contentsOf:file,encoding:.utf8) {
                    try source.replacingOccurrences(of:"Template.X",with:url.lastPathComponent).replacingOccurrences(of:"<name>Template</name>",with:"<name>\(url.deletingPathExtension().lastPathComponent)</name>").write(to:file,atomically:true,encoding:.utf8)
                }
            } }
            return try core.open(url.path)
        case "project": return try core.requireProject().info()
        case "configuration": try core.requireProject().select(str("name")); return try core.requireProject().info()
        case "read": return try core.requireProject().read(str("path"))
        case "save": return try core.requireProject().save(str("path"),content:str("content"),expected:str("digest"),encoding:str("encoding","utf8"))
        case "build": return try core.build(debug:args["debug"] as? Bool ?? false)
        case "clean":
            _ = try core.build(clean:true); return try core.build(clean:true,debug:true)
        case "regenerate": return try core.regenerate()
        case "debugStart": return try core.startDebug(tool:str("tool","SIM"),index:int("index"))
        case "debugAction": return try core.debugAction(str("action"),names:args["names"] as? [String] ?? ["WREG","STATUS","BSR"])
        case "inspect": return try core.inspect(args["names"] as? [String] ?? [])
        case "breakpoint": return try core.breakpoint(path:str("path"),line:int("line",1))
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
    func windowShouldClose(_ sender: NSWindow) -> Bool { if closing { return true }; event("requestClose",true); return false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { if closing { return .terminateNow }; event("requestClose",true); return .terminateCancel }
    func applicationWillTerminate(_ notification: Notification) { core.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct AsterMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
}
