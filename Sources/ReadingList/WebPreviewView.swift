import SwiftUI
import WebKit

/// Keeps one warm `WKWebView` per host so saved links from the same site share
/// live session state: dismiss a login or cookie banner on one entry and every
/// other entry on that host opens already signed in, with scroll/playback
/// position preserved. Cookies persist across launches via the default
/// `WKWebsiteDataStore` regardless of the pool.
@MainActor
final class WebPreviewPool {
    static let shared = WebPreviewPool()

    private var webViews: [String: TrackingWebView] = [:]
    private let uiDelegateHandler = WebViewUIDelegate()

    func webView(for host: String) -> TrackingWebView {
        if let existing = webViews[host] {
            return existing
        }

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.preferredContentMode = .recommended
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let view = TrackingWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.uiDelegate = uiDelegateHandler
        webViews[host] = view
        return view
    }

    static func key(for url: URL) -> String {
        (url.host() ?? url.absoluteString).lowercased()
    }
}

struct WebPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        let host = WebPreviewPool.key(for: url)
        let webView = WebPreviewPool.shared.webView(for: host)

        if webView.superview !== nsView {
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = false
            nsView.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
                webView.topAnchor.constraint(equalTo: nsView.topAnchor),
                webView.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
            ])
        }

        guard webView.lastRequestedURL != url else {
            return
        }

        webView.lastRequestedURL = url
        webView.load(URLRequest(url: url))
    }
}

/// Loads links that ask for a new window (target="_blank") in the same
/// preview instead of silently dropping them.
@MainActor
final class WebViewUIDelegate: NSObject, WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

final class TrackingWebView: WKWebView {
    var lastRequestedURL: URL?
}
