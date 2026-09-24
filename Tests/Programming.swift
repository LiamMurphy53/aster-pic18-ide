import Foundation

@main struct ProgrammingTests {
    static let warning = "CAUTION: Check that the device selected in MPLAB IDE (PIC18F87K22) is the same one that is physically attached to the tool. Selecting a 5V device when a 3.3V device is connected can result in damage to the device. Do you wish to continue?"
    static func emit(_ value: String) { FileHandle.standardOutput.write(Data(value.utf8)) }
    static func fakeMDB(_ mode: String) {
        emit("MDB test transport\n>")
        while let command = readLine() {
            if command.hasPrefix("hwtool") {
                for character in warning + "\n\n>" { emit(String(character)) }
                guard readLine() == "yes" else { exit(3) }
                if mode == "repeat" {
                    emit("Second confirmation [yes/no/cancel]\n>")
                    guard readLine() == "yes" else { exit(4) }
                }
                emit("Target voltage detected\nTarget device PIC18F87K22 found.\nDevice Revision ID = 6\n>")
            } else if command.hasPrefix("program") {
                emit("Programming target...\nProgress 2 > 1\n")
                if mode == "timeout" { Thread.sleep(forTimeInterval:2); continue }
                Thread.sleep(forTimeInterval:0.05)
                emit(mode == "failure" ? "Program failed.\n>" : "Program succeeded.\n>")
            } else { emit("Ready\n>") }
        }
    }
    static func main() throws {
        if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--fake-mdb" { fakeMDB(CommandLine.arguments[2]); return }
        setbuf(stdout,nil)
        var checks = 0
        func check(_ name: String, _ value: Bool) throws {
            guard value else { throw IDEError("FAIL " + name) }
            checks += 1; print("PASS " + name)
        }
        let transcript = warning + "\r\n\r\n>Target voltage detected\n>"
        var everySplitCorrect = true
        for offset in 0...transcript.count {
            var reader = MDBPromptReader()
            let split = transcript.index(transcript.startIndex,offsetBy:offset)
            let prompts = reader.receive(String(transcript[..<split])) + reader.receive(String(transcript[split...]))
            if prompts.count != 2 { everySplitCorrect = false; continue }
            if case .confirmation(let text) = prompts[0] { everySplitCorrect = everySplitCorrect && text == warning }
            else { everySplitCorrect = false }
            if case .ready = prompts[1] {} else { everySplitCorrect = false }
        }
        try check("Device warning recognized at every possible pipe split",everySplitCorrect)
        var reader = MDBPromptReader()
        try check("Greater-than signs in output are not command prompts",reader.receive("Value 4 > 2\n").isEmpty)
        let executable = URL(fileURLWithPath:CommandLine.arguments[0])
        func session(_ mode: String) throws -> MDBSession {
            let result = MDBSession(Toolchain())
            try result.start(executable:executable,arguments:["--fake-mdb",mode])
            return result
        }
        for mode in ["success","repeat"] {
            let s = try session(mode); defer { s.stop() }
            var questions: [String] = []
            s.onConfirmation = { questions.append($0); Thread.sleep(forTimeInterval:0.15); return true }
            let connected = try s.checked("hwtool PICkit3 -p 0",timeout:0.1)
            try check("\(mode): waits for acceptance and chip detection",connected.contains("Device Revision ID = 6") && questions.first == warning)
            try check("\(mode): presents each confirmation once",questions.count == (mode == "repeat" ? 2 : 1))
            let programmed = try s.checked("program test.hex")
            try check("\(mode): programming command reaches MDB and waits for completion",programmed.contains("Program succeeded."))
            try check("\(mode): following command stays synchronized",try s.checked("reset") == "Ready")
        }
        for accepted in [false, true] {
            let s = try session("failure"); defer { s.stop() }
            s.onConfirmation = {_ in accepted}
            var rejected = false
            do {
                _ = try s.checked("hwtool PICkit3 -p 0")
                _ = try s.checked("program test.hex")
            } catch { rejected = error.localizedDescription.contains(accepted ? "Program failed" : "cancelled") }
            try check(accepted ? "Programming failure remains an error" : "Cancelling closes the session before programming",rejected)
            if !accepted {
                var closed = false
                do { _ = try s.command("program test.hex") } catch { closed = true }
                try check("Cancelled session cannot send another command",closed)
            }
        }
        let s = try session("timeout"); defer { s.stop() }
        s.onConfirmation = {_ in true}
        _ = try s.checked("hwtool PICkit3 -p 0")
        var timedOut = false
        do { _ = try s.checked("program test.hex",timeout:0.1) }
        catch { timedOut = error.localizedDescription.contains("timed out") }
        try check("Missing completion times out instead of reporting success",timedOut)
        print("ALL \(checks) PROGRAMMING PROTOCOL CHECKS PASSED")
    }
}
