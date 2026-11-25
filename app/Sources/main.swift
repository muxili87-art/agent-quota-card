import AppKit
import Carbon.HIToolbox
import Foundation

if CommandLine.arguments.contains("--hotkey-check") {
    var reference: EventHotKeyRef?
    let identifier = EventHotKeyID(signature: OSType(0x4147_5155), id: 99) // "AGQU"
    let status = RegisterEventHotKey(
        UInt32(kVK_ANSI_Q),
        UInt32(controlKey | optionKey),
        identifier,
        GetApplicationEventTarget(),
        0,
        &reference
    )
    print("registerStatus=\(status) hasReference=\(reference != nil)")
    exit(status == noErr ? 0 : 1)
}

if CommandLine.arguments.contains("--selftest") {
    let codex = try? CodexQuotaReader.readCurrent()
    let agy = try? AntigravityQuotaReader.readCurrent()
    let payload = QuotaPayload.data(
        codex: codex ?? .empty,
        codexFetchedAt: codex != nil ? Date() : nil,
        antigravity: agy ?? .empty,
        antigravityFetchedAt: agy != nil ? Date() : nil,
        intervalSeconds: 60
    ).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    print(payload)
    exit((codex != nil || agy != nil) ? 0 : 1)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
