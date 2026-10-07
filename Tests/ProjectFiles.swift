import Foundation
import JavaScriptCore

@main struct ProjectFilesCheck {
    static func main() throws {
        let base = URL(fileURLWithPath:CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aster-files-" + UUID().uuidString).appendingPathExtension("X")
        let fm = FileManager.default
        try fm.copyItem(at:base.appendingPathComponent("Resources/Template.X"),to:root)
        defer { try? fm.removeItem(at:root) }
        let config = root.appendingPathComponent("nbproject/configurations.xml")
        let originalConfig = try Data(contentsOf:config)
        let project = try PICProject(root)
        func write(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try "; source\n".write(to:url,atomically:true,encoding:.utf8)
            return url
        }
        let extra = try write("extra.asm")
        _ = try write("helpers/EXTRA.ASM")
        _ = try write("helpers/macros.inc")
        for path in ["build/generated.asm", "dist/generated.asm", "nbproject/private/private.asm", ".hidden.asm", "Other.X/main.asm"] { _ = try write(path) }
        try fm.createSymbolicLink(at:root.appendingPathComponent("outside.asm"),withDestinationURL:URL(fileURLWithPath:"/etc/passwd"))
        _ = project.info()
        let sources = project.files.filter { ["asm","inc"].contains($0.pathExtension.lowercased()) }
        precondition(sources.count == 4, "Discover extra and nested sources, without duplicates or generated/private files")
        let read = try project.read(extra.path)
        _ = try project.save(extra.path,content:"; edited\n",expected:read["digest"] as! String,encoding:"utf8")
        let reopened = try PICProject(root).read(extra.path)
        precondition(reopened["content"] as? String == "; edited\n")
        try fm.removeItem(at:extra)
        _ = project.info()
        precondition(!project.files.contains(extra), "Refresh removes deleted discovered files")
        let finalConfig = try Data(contentsOf:config)
        precondition(originalConfig == finalConfig, "Discovery preserves build settings")
        let js = JSContext()!
        let source = try String(contentsOf:base.appendingPathComponent("Web/app.js"),encoding:.utf8)
        _ = js.objectForKeyedSubscript("Function")!.construct(withArguments:[source])
        precondition(js.exception == nil, "App JavaScript parses")
        print("PASS: discovery, refresh, nested/uppercase sources, exclusions, save/reopen, unchanged build settings, JavaScript syntax")
    }
}
