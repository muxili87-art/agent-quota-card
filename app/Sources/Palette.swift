import AppKit

/// 由 app/Scripts/gen-palette.py 从 palette.json 生成，勿手改。
enum Palette {
    enum Tier: String {
        case ok, warn, crit
    }

    enum Engine: String {
        case codex, antigravity
    }

    static let warnThreshold: Double = 30
    static let critThreshold: Double = 15
    static let ink = NSColor(srgbRed: 0.9451, green: 0.9608, blue: 0.9765, alpha: 1)
    static let label = NSColor(srgbRed: 0.5804, green: 0.6392, blue: 0.7216, alpha: 1)

    struct Tone {
        let accent: NSColor
        let fillFrom: NSColor
        let fillTo: NSColor
    }

    static func tier(forRemaining remain: Double) -> Tier {
        if remain < critThreshold { return .crit }
        if remain < warnThreshold { return .warn }
        return .ok
    }

    static func engineTone(_ engine: Engine, tier: Tier) -> Tone {
        if tier == .ok {
            switch engine {
            case .codex: return Tone(accent: NSColor(srgbRed: 0.8863, green: 0.9098, blue: 0.9412, alpha: 1), fillFrom: NSColor(srgbRed: 0.5804, green: 0.6392, blue: 0.7216, alpha: 1), fillTo: NSColor(srgbRed: 0.8863, green: 0.9098, blue: 0.9412, alpha: 1))
            case .antigravity: return Tone(accent: NSColor(srgbRed: 0.7490, green: 0.8588, blue: 0.9961, alpha: 1), fillFrom: NSColor(srgbRed: 0.3765, green: 0.6471, blue: 0.9804, alpha: 1), fillTo: NSColor(srgbRed: 0.7490, green: 0.8588, blue: 0.9961, alpha: 1))
            }
        }
        return tone(for: tier)
    }

    static func tone(for tier: Tier) -> Tone {
        switch tier {
        case .ok: return Tone(accent: NSColor(srgbRed: 0.8863, green: 0.9098, blue: 0.9412, alpha: 1), fillFrom: NSColor(srgbRed: 0.5804, green: 0.6392, blue: 0.7216, alpha: 1), fillTo: NSColor(srgbRed: 0.8863, green: 0.9098, blue: 0.9412, alpha: 1))
        case .warn: return Tone(accent: NSColor(srgbRed: 0.9608, green: 0.6196, blue: 0.0431, alpha: 1), fillFrom: NSColor(srgbRed: 0.8510, green: 0.4667, blue: 0.0235, alpha: 1), fillTo: NSColor(srgbRed: 0.9843, green: 0.7490, blue: 0.1412, alpha: 1))
        case .crit: return Tone(accent: NSColor(srgbRed: 0.9373, green: 0.2667, blue: 0.2667, alpha: 1), fillFrom: NSColor(srgbRed: 0.8627, green: 0.1490, blue: 0.1490, alpha: 1), fillTo: NSColor(srgbRed: 0.9725, green: 0.4431, blue: 0.4431, alpha: 1))
        }
    }
}
