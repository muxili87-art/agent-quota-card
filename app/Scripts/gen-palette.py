#!/usr/bin/env python3
"""把 palette.json 展开成网页和 Swift 的代码。"""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent.parent
data = json.loads((root / "palette.json").read_text())
surface = data["surface"]
engines = data["engines"]
warn = data["thresholds"]["warn"]
crit = data["thresholds"]["crit"]
tiers = data["tiers"]

css = [
    "/* 由 app/Scripts/gen-palette.py 从 palette.json 生成，勿手改。 */",
    ":root {",
    f"  --ink: {surface['ink']};",
    f"  --label: {surface['label']};",
    f"  --quiet: {surface['quiet']};",
    f"  --surface-top: {surface['top']};",
    f"  --surface-mid: {surface['mid']};",
    f"  --surface-bottom: {surface['bottom']};",
    f"  --surface-glow: {surface['glow']};",
    f"  --surface-border: {surface['border']};",
    "}",
    "",
]
(root / "palette.css").write_text("\n".join(css))

js = [
    "// 由 app/Scripts/gen-palette.py 从 palette.json 生成，勿手改。",
    "window.AGENT_PALETTE = {",
    f"  thresholds: {{ warn: {warn}, crit: {crit} }},",
    "  engines: {",
]
for name, tone in engines.items():
    js.append(
        f'    {name}: {{ accent: "{tone["accent"]}", '
        f'fillFrom: "{tone["fillFrom"]}", fillTo: "{tone["fillTo"]}" }},'
    )
js.append("  },")
js.append("  tiers: {")
for name, tone in tiers.items():
    js.append(
        f'    {name}: {{ accent: "{tone["accent"]}", '
        f'fillFrom: "{tone["fillFrom"]}", fillTo: "{tone["fillTo"]}" }},'
    )
js += ["  }", "};", ""]
(root / "palette.js").write_text("\n".join(js))


def ns(hex_color):
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"NSColor(srgbRed: {r:.4f}, green: {g:.4f}, blue: {b:.4f}, alpha: 1)"


swift = [
    "import AppKit",
    "",
    "/// 由 app/Scripts/gen-palette.py 从 palette.json 生成，勿手改。",
    "enum Palette {",
    "    enum Tier: String {",
    "        case ok, warn, crit",
    "    }",
    "",
    "    enum Engine: String {",
    "        case codex, antigravity",
    "    }",
    "",
    f"    static let warnThreshold: Double = {warn}",
    f"    static let critThreshold: Double = {crit}",
    f"    static let ink = {ns(surface['ink'])}",
    f"    static let label = {ns(surface['label'])}",
    "",
    "    struct Tone {",
    "        let accent: NSColor",
    "        let fillFrom: NSColor",
    "        let fillTo: NSColor",
    "    }",
    "",
    "    static func tier(forRemaining remain: Double) -> Tier {",
    "        if remain < critThreshold { return .crit }",
    "        if remain < warnThreshold { return .warn }",
    "        return .ok",
    "    }",
    "",
    "    static func engineTone(_ engine: Engine, tier: Tier) -> Tone {",
    "        if tier == .ok {",
    "            switch engine {",
]
for name, tone in engines.items():
    swift.append(
        f"            case .{name}: return Tone(accent: {ns(tone['accent'])}, "
        f"fillFrom: {ns(tone['fillFrom'])}, fillTo: {ns(tone['fillTo'])})"
    )
swift += [
    "            }",
    "        }",
    "        return tone(for: tier)",
    "    }",
    "",
    "    static func tone(for tier: Tier) -> Tone {",
    "        switch tier {",
]
for name, tone in tiers.items():
    swift.append(
        f"        case .{name}: return Tone(accent: {ns(tone['accent'])}, "
        f"fillFrom: {ns(tone['fillFrom'])}, fillTo: {ns(tone['fillTo'])})"
    )
swift += ["        }", "    }", "}", ""]
(root / "app" / "Sources" / "Palette.swift").write_text("\n".join(swift))
