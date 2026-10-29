import Foundation
import JavaScriptCore

// instruments panel logic: shared measurement/cursor helpers (Web/measurements.js) and AD2 request validation
@main struct InstrumentsCheck {
    static func main() throws {
        let base = URL(fileURLWithPath:CommandLine.arguments[1])
        let js = JSContext()!
        var failures: [String] = []
        js.exceptionHandler = { _, e in failures.append("exception: \(e?.toString() ?? "?")") }
        js.setObject(unsafeBitCast({ (ok: Bool, name: String) in if !ok { failures.append(name) } } as @convention(block) (Bool,String)->Void, to:AnyObject.self), forKeyedSubscript:"check" as NSString)
        js.evaluateScript(try String(contentsOf:base.appendingPathComponent("Web/measurements.js"),encoding:.utf8))
        js.evaluateScript("""
        const M=AsterMeasurements,near=(a,b)=>Math.abs(a-b)<1e-12;
        const legacy={mode:'logic',sampleRate:1e6,channel:3,values:[[0,0],[100,1],[1100,0],[20100,1],[21300,0],[40100,1]]};
        M.normalize(legacy);check(legacy.traces.length===1&&legacy.traces[0].channel===3,'legacy capture becomes one trace');
        const c={mode:'logic',sampleRate:1e6,span:.05,traces:[{channel:2,values:[[0,0],[100,1],[1100,0],[20100,1],[21300,0],[40100,1]]},{channel:4,values:[[0,1],[500,0],[30000,1]]}]};
        const t2=M.trace(c,2),a=M.analyze(t2);check(a.cycles===2&&near(a.period,.02)&&near(a.high,.0011)&&near(a.duty,5.5),'logic averages match the helper');
        check(M.trace(c,4).channel===4&&M.trace(c,9).channel===2,'measure trace falls back to the first');
        const s=M.summary(t2);check(s.count===2&&near(s.min,.001)&&near(s.max,.0012),'complete pulses only');
        const e=M.edges(c);check(e.length===7&&e[0]===100/1e6&&e.every((v,i)=>!i||v>e[i-1]),'edges sorted across traces');
        check(M.nearest(e,.0012)===.0011&&M.nearest(e,.024)===.0213&&M.nearest(e,.026)===.03&&M.nearest([],1)===null,'nearest edge');
        check(M.valueAt(c,c.traces[0],.0005)===1&&M.valueAt(c,c.traces[0],.002)===0&&M.valueAt(c,c.traces[1],.0001)===1&&M.valueAt(c,c.traces[1],.031)===1,'logic level at cursor');
        const sc={mode:'scope',dt:.001,sampleRate:1e4,traces:[{channel:0,values:[0,1,3]},{channel:1,values:[5,5,5]}]};
        check(Math.abs(M.valueAt(sc,sc.traces[0],.0015)-2)<1e-9&&M.valueAt(sc,sc.traces[0],.01)===null,'scope voltage interpolates');
        check(M.samplesCSV(sc).split('\\n')[0]==='time_s,scope1_v,scope2_v'&&M.samplesCSV(sc).includes('0.001,1,5'),'scope samples csv');
        const edges=M.transitionsCSV(c).trim().split('\\n');check(edges.length===10&&edges[1]==='0,0,0,1000000,2'&&edges[2]==='0,0,1,1000000,4'&&edges[3]==='100,0.0001,1,1000000,2','edge csv has every channel');
        check(M.transitionsCSV(legacy).includes('1100,0.0011,0,1000000,3'),'legacy edge csv');
        check(near(M.niceStep(.05,8),.01)&&near(M.niceStep(.0009,8),.0002)&&near(M.niceStep(2.2,8),.5),'nice time steps');
        check(M.tick(.005,.005,.05)==='5 ms'&&M.tick(.0005,.0001,.001)==='0.5 ms'&&M.tick(.0005,.0001,.0008)==='500 µs'&&M.tick(.0015,.0005,.002)==='1.5 ms'&&M.tick(1.5,.5,2.2)==='1.5 s','axis labels');
        check(M.time(.0010004)==='1.0004 ms'&&M.time(12.5e-6)==='12.500 µs'&&M.time(-.002)==='-2.0000 ms'&&M.time(1.25)==='1.25000 s'&&M.time(NaN)==='—','cursor times');
        check(M.frequency(1/.02)==='50.000 Hz'&&M.frequency(1/.001)==='1.0000 kHz'&&M.frequency(0)==='—'&&M.volts(3.3)==='3.300 V'&&M.volts(-.05)==='-50.0 mV','frequency and voltage readouts');
        """)
        func rejects(_ a: [String:Any]) -> Bool { (try? AD2Session.arguments(a)) == nil }
        let logic = try AD2Session.arguments(["mode":"logic","span":0.05,"channels":[2,0,5],"trigger":5,"edge":"fall","level":1.5,"position":25,"triggerMode":"normal","range":50])
        if logic != ["logic","0.05","channels=2,0,5","trigger=5","edge=fall","level=1.5","position=25.0","mode=normal","range=50"] { failures.append("logic arguments: \(logic)") }
        let scope = try AD2Session.arguments(["mode":"scope","span":2.2,"channels":[1],"trigger":-1,"range":5])
        if scope != ["scope","2.2","channels=1","trigger=none","edge=rise","level=1.5","position=10.0","mode=auto","range=5"] { failures.append("scope arguments: \(scope)") }
        if try AD2Session.arguments(["mode":"logic","span":0.02,"channel":7]) != ["logic","0.02","channels=7","trigger=7","edge=rise","level=1.5","position=10.0","mode=auto","range=50"] { failures.append("single channel request") }
        for bad: [String:Any] in [["mode":"scope","span":0.05,"channels":[2]],["mode":"logic","span":0.05,"channels":[1,1]],["mode":"logic","span":0.05,"channels":[]],["mode":"logic","span":5,"channels":[0]],["mode":"logic","span":0.05,"channels":[0],"trigger":16],["mode":"logic","span":0.05,"channels":[0],"edge":"both"],["mode":"scope","span":0.05,"channels":[0],"range":10],["mode":"scope","span":0.05,"channels":[0],"level":30],["mode":"logic","span":0.05,"channels":[0],"position":120],["mode":"dmm","span":0.05,"channels":[0]]] where !rejects(bad) { failures.append("accepted \(bad)") }
        if !failures.isEmpty { failures.forEach { print("FAIL: \($0)") }; exit(1) }
        print("PASS: 19 instrument checks (traces, measurements, edges, cursor values, csv, axis/readout formatting, AD2 request validation)")
    }
}
