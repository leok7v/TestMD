import SwiftUI
import WebKit

public func paperSize() -> CGSize { // A4 or Letter in points
    let A4 = CGSize(width: 595, height: 842) // ~8.3 x 11.7
    let Letter = CGSize(width: 8.5 * 72, height: 11 * 72)
    let LetterRegions: Set<String> = ["US", "CA", "MX", "CL", "CO",
                                      "CR", "PA", "PE", "PH", "PR"]
    return LetterRegions.contains(Locale.current.region?.identifier ?? "") ?
           Letter : A4
}

public func pageRect() -> CGRect {
    let size = paperSize()
    return CGRect(origin: .zero, size: size)
}

private func document(_ html: String,
                      _ css: String,
                      _ cs: ColorScheme,
                      _ accentColor: Color.Resolved) -> String {
    let rootColors: String
    if cs == .dark {
        rootColors = ":root { --text-color: #c9d1d9; " +
                             "--background-color: #0d1117; }"
    } else {
        rootColors = ":root { --text-color: #24292e; " +
                             "--background-color: #fff; }"
    }
    let size = paperSize()
    return """
    <!doctype html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(rootColors)
        \(css)
        :root { 
            color:      var(--text-color);
            background: var(--background-color);
        }
        @media print {
            @page { size: \(size.width)pt \(size.height)pt; margin: 36pt; }
        }
        html, body { margin: 0; padding: 0; }
        pre { overflow-x: auto; }
        code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
        hr { border: 0; border-top: 1px solid #888; margin: 1.2em 0; }
        th, td { border: 1px solid #888; padding: 6px 8px; }
        a { color: \(accentColor.toHtmlHexString()); text-decoration: none; }
        a:hover { text-decoration: underline; }
        table { border-collapse: collapse; }
        </style>
    </head>
    <body>
        \(html)
    </body>
    </html>
    """
}

#if os(iOS)
import UIKit
typealias ViewRepresentable = UIViewRepresentable
typealias Context = UIViewRepresentableContext<HtmlView>
#else
import AppKit
typealias ViewRepresentable = NSViewRepresentable
typealias Context = NSViewRepresentableContext<HtmlView>
#endif

struct HtmlView: ViewRepresentable {
    
    let html: String
    var onWebViewReady: ((WKWebView) -> Void)? = nil
    var forcedColorScheme: ColorScheme? = nil

    @Environment(\.self) private var environment // for accent color
    @Environment(\.colorScheme)  var colorScheme

    @State private var linkColor: Color.Resolved?
 
    class Coordinator: NSObject, WKNavigationDelegate {
    
        var parent: HtmlView
        var webView: WKWebView?
        
        init(_ parent: HtmlView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            parent.onWebViewReady?(webView)
        }
        
        func webView(_ webView: WKWebView,
             decidePolicyFor navigationAction: WKNavigationAction,
             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                #if os(iOS)
                UIApplication.shared.open(url, options: [:],
                                          completionHandler: nil)
                #else // os(macOS)
                NSWorkspace.shared.open(url)
                #endif
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
                
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    static let dark = Bundle.main.path(forResource: "prism-dark",    ofType: "css")!
    static let lite = Bundle.main.path(forResource: "prism-default", ofType: "css")!
    
    static let prism_dark = try! String(contentsOfFile: dark, encoding: .utf8)
    static let prism_lite = try! String(contentsOfFile: lite, encoding: .utf8)

    func makeView(_ context: Context) -> WKWebView {
        let inspectable = isDebuggerAttached() || isDebugBuild()
        let config = WKWebViewConfiguration()
        config.preferences.setValue(inspectable, forKey: "developerExtrasEnabled")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isInspectable = inspectable
        #if os(iOS)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.allowsBackForwardNavigationGestures = false
        wv.scrollView.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.delaysContentTouches = false
        #else
        wv.setValue(false, forKey: "drawsBackground")
        #endif
        return wv
    }
    
    func update(_ webView: WKWebView, _ context: Context) {
        webView.navigationDelegate = context.coordinator
        let cs = forcedColorScheme ?? colorScheme
        print("dark: \(cs == .dark)")
        let css = cs == .dark ? Self.prism_dark : Self.prism_lite
        let accentColor = Color.accentColor.resolve(in: environment)
        let page = document(html, css, colorScheme, accentColor)
        DispatchQueue.main.async {
            webView.loadHTMLString(page, baseURL: Bundle.main.bundleURL)
        }
    }

    func makeNSView(context: Context) -> WKWebView { return makeView(context) }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView, context)
    }

    func makeUIView(context: Context) -> WKWebView  { return makeView(context) }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        update(webView, context)
    }

}

@MainActor
func toPDF(_ webView: WKWebView) async -> Data? {
    do {
        #if os(iOS)
        let c = WKPDFConfiguration()
        c.rect = CGRect(x: 0, y: 0, width: 600, height: 800)
        return try await webView.pdf(configuration: c)
        #else
        let c = WKPDFConfiguration()
        c.rect = CGRect(x: 0, y: 0, width: 600, height: 800)
        return try await webView.pdf(configuration: c)
        #endif
    } catch {
        print("PDF generation error: \(error)")
        return nil
    }
}

func isDebugBuild() -> Bool {
    #if DEBUG
        return true
    #else
        return false
    #endif
}

func isDebuggerAttached() -> Bool {
    var i = kinfo_proc()
    var s = MemoryLayout<kinfo_proc>.stride
    var m: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    let r = sysctl(&m, UInt32(m.count), &i, &s, nil, 0)
    guard r == 0 else { return false }
    return (i.kp_proc.p_flag & P_TRACED) != 0
}

extension Color.Resolved {
    func toHtmlHexString() -> String {
        let r = Int(self.red * 255)
        let g = Int(self.green * 255)
        let b = Int(self.blue * 255)
        return String(format: "#%02lX%02lX%02lX", r, g, b)
    }
}

