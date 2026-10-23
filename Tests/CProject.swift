import Foundation

@main struct CProjectCheck {
    static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        let template = base.appendingPathComponent("Resources/CTemplate.X")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aster-c-" + UUID().uuidString).appendingPathExtension("X")
        try FileManager.default.copyItem(at: template, to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try PICProject(root)
        precondition(project.configurations.first?["compiler"] == "XC8")
        precondition(project.files.contains { $0.lastPathComponent == "main.c" })
        precondition(!project.files.contains { $0.lastPathComponent == "main.asm" })
        let compiler = Toolchain().cCompiler
        precondition(FileManager.default.fileExists(atPath: compiler))
        print("PASS: XC8 project metadata, C source discovery, installed compiler")
    }
}
