import AppKit
import WebKit

private final class CardSizeBridge: NSObject, WKScriptMessageHandler {
    var onSize: ((CGSize) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == "openDashboard" {
            if let raw = message.body as? String, let url = URL(string: raw) {
                NSWorkspace.shared.open(url)
            }
            return
        }
        guard message.name == "cardSize",
              let body = message.body as? [String: Any],
              let width = body["width"] as? Double,
              let height = body["height"] as? Double
        else { return }
        onSize?(CGSize(width: width, height: height))
    }
}

/// Keeps the card on its bundled page: any http(s) link opens in the browser.
private final class ExternalLinkPolicy: NSObject, WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

final class WebCardController {
    let webView: WKWebView
    let webDirectory: URL
    var onCardSize: ((CGSize) -> Void)?

    private let bridge = CardSizeBridge()
    private let linkPolicy = ExternalLinkPolicy()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        webDirectory = support
            .appendingPathComponent("AgentQuotaCard", isDirectory: true)
            .appendingPathComponent("web", isDirectory: true)

        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        configuration.userContentController.add(bridge, name: "cardSize")

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = linkPolicy
        webView.underPageBackgroundColor = .clear

        bridge.onSize = { [weak self] size in self?.onCardSize?(size) }
    }

    var dataURL: URL {
        webDirectory.appendingPathComponent("data.js")
    }

    private var indexURL: URL {
        webDirectory.appendingPathComponent("index.html")
    }

    func installAssets() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: webDirectory, withIntermediateDirectories: true)

        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("web", isDirectory: true) else {
            return
        }

        for name in ["index.html", "styles.css", "palette.css", "palette.js", "app.js"] {
            let source = bundled.appendingPathComponent(name)
            let target = webDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try? fileManager.removeItem(at: target)
            try? fileManager.copyItem(at: source, to: target)
        }

        let bundledData = bundled.appendingPathComponent("data.js")
        if !fileManager.fileExists(atPath: dataURL.path),
           fileManager.fileExists(atPath: bundledData.path) {
            try? fileManager.copyItem(at: bundledData, to: dataURL)
        }
    }

    func load() {
        var components = URLComponents(url: indexURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "embed", value: "1")]
        guard let url = components?.url else { return }
        webView.loadFileURL(url, allowingReadAccessTo: webDirectory)
    }

    func updateQuota(json: String) {
        guard webView.url != nil else {
            load()
            return
        }
        let script = "window.updateAgentQuota && window.updateAgentQuota(\(json));"
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if error != nil {
                self?.load()
            }
        }
    }
}
