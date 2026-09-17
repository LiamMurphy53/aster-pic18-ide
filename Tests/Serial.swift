import Foundation
import Darwin
@main struct SerialTests {
    static func main() throws {
        setbuf(stdout,nil)
        var master:Int32=0,slave:Int32=0,name=[CChar](repeating:0,count:128)
        guard openpty(&master,&slave,&name,nil,nil)==0 else { throw IDEError("Could not open a test serial pair") }
        defer { Darwin.close(master); Darwin.close(slave) }
        let path=String(cString:name), serial=SerialConnection(portProvider:{[path]})
        let received=DispatchSemaphore(value:0); var message=""
        serial.onData={message += $0;if message.contains("PIC reply") {received.signal()} }
        defer { serial.disconnect() }
        try serial.connect(path,baud:19200)
        let input=Data("PIC reply\n".utf8)
        _=input.withUnsafeBytes{Darwin.write(master,$0.baseAddress,input.count)}
        guard received.wait(timeout:.now()+3) == .success,message=="PIC reply\n" else {throw IDEError("Serial receive did not match")}
        print("PASS Serial receives target data at 19200 baud")
        try serial.send("Host message\n")
        var buf=[UInt8](repeating:0,count:128)
        let n=Darwin.read(master,&buf,128)
        guard n>0,String(decoding:buf.prefix(n),as:UTF8.self)=="Host message\n" else {throw IDEError("Serial transmit did not match")}
        print("PASS Serial sends exact text with LF")
        serial.disconnect()
        guard serial.port==nil else {throw IDEError("Port still connected")}
        print("PASS Serial disconnect releases the device")
    }
}
