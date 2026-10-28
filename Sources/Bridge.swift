import Foundation

// file-based request bridge so a local agent (claude) can drive the same operations as the ui
// protocol: write requests/<id>.json = {"op":..,"args":{..}}, read responses/<id>.json
// status.json is a heartbeat so a client can tell whether aster is listening
final class AsterBridge {
    typealias Reply = (Any?, String?, String) -> Void
    let folder: URL
    let version: String
    var handler: (String, [String:Any], @escaping Reply) -> Void = { _, _, reply in reply(nil, "The bridge has no handler.", "") }
    private let queue = DispatchQueue(label: "app.aster.bridge")
    private let fm = FileManager.default
    private var timer: DispatchSourceTimer?
    private var lastHeartbeat = Date.distantPast
    private var lastPrune = Date.distantPast
    private var inFlight = Set<String>()
    private var info: [String:Any] = [:]
    var requests: URL { folder.appendingPathComponent("requests") }
    var working: URL { folder.appendingPathComponent("working") }
    var responses: URL { folder.appendingPathComponent("responses") }
    var screenshots: URL { folder.appendingPathComponent("screenshots") }

    init(folder: URL, version: String) { self.folder = folder.standardizedFileURL; self.version = version }

    static func validID(_ id: String) -> Bool { id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil }

    func start() throws {
        for dir in [requests, working, responses] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        queue.sync {
            // a request claimed by a previous launch never finished, answer it so the client stops waiting
            for url in (try? fm.contentsOfDirectory(at: working, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json" {
                respond(id: url.deletingPathExtension().lastPathComponent, op: "", value: nil, error: "Aster restarted before this request finished.", output: "", started: Date())
                try? fm.removeItem(at: url)
            }
            writeStatus(enabled: true)
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(150))
        t.setEventHandler { [weak self] in self?.poll() }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel(); timer = nil
        queue.sync { writeStatus(enabled: false) }
    }

    // latest app state for the heartbeat file
    func update(_ state: [String:Any]) { queue.async { self.info = state; self.writeStatus(enabled: self.timer != nil) } }

    private func poll() {
        let now = Date()
        if now.timeIntervalSince(lastHeartbeat) >= 1 { writeStatus(enabled: true) }
        if now.timeIntervalSince(lastPrune) >= 60 { prune(); lastPrune = now }
        let names = ((try? fm.contentsOfDirectory(atPath: requests.path)) ?? []).filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.sorted()
        for name in names {
            let id = String(name.dropLast(5))
            let source = requests.appendingPathComponent(name)
            guard AsterBridge.validID(id) else { try? fm.removeItem(at: source); continue }
            guard !inFlight.contains(id) else { continue }
            let claimed = working.appendingPathComponent(name)
            try? fm.removeItem(at: claimed)
            guard (try? fm.moveItem(at: source, to: claimed)) != nil else { continue }
            let started = Date()
            guard let data = try? Data(contentsOf: claimed),
                  let body = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any],
                  let op = body["op"] as? String else {
                respond(id: id, op: "", value: nil, error: "Request must be a JSON object with an op.", output: "", started: started)
                try? fm.removeItem(at: claimed)
                continue
            }
            inFlight.insert(id)
            handler(op, body["args"] as? [String:Any] ?? [:]) { [weak self] value, error, output in
                guard let self else { return }
                self.queue.async {
                    self.respond(id: id, op: op, value: value, error: error, output: output, started: started)
                    try? self.fm.removeItem(at: claimed)
                    self.inFlight.remove(id)
                }
            }
        }
    }

    private func respond(id: String, op: String, value: Any?, error: String?, output: String, started: Date) {
        var body: [String:Any] = ["id": id, "op": op, "ok": error == nil, "ms": Int(Date().timeIntervalSince(started) * 1000)]
        if let error { body["error"] = error } else { body["value"] = value ?? NSNull() }
        if !output.isEmpty { body["output"] = String(output.suffix(200_000)) }
        if !JSONSerialization.isValidJSONObject(body) {
            body["value"] = NSNull()
            body["ok"] = false
            body["error"] = "The result could not be encoded as JSON."
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: responses.appendingPathComponent(id + ".json"), options: .atomic)
    }

    private func writeStatus(enabled: Bool) {
        lastHeartbeat = Date()
        var body = info
        body["app"] = "Aster"
        body["version"] = version
        body["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
        body["enabled"] = enabled
        body["updated"] = ISO8601DateFormatter().string(from: lastHeartbeat)
        body["unix"] = lastHeartbeat.timeIntervalSince1970
        body["busy"] = !inFlight.isEmpty
        guard JSONSerialization.isValidJSONObject(body), let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .prettyPrinted]) else { return }
        try? data.write(to: folder.appendingPathComponent("status.json"), options: .atomic)
    }

    // clients cannot always delete files, so aster cleans up old responses and screenshots
    private func prune() {
        let cutoff = Date().addingTimeInterval(-3600)
        for dir in [responses, screenshots] {
            for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < cutoff { try? fm.removeItem(at: url) }
            }
        }
    }
}
