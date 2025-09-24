import SwiftUI
import WebKit
#if os(iOS)
import UIKit
typealias HostingController = UIHostingController
typealias Window            = UIWindow
#else
import AppKit
typealias HostingController = NSHostingController
typealias Window            = NSWindow
#endif

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

public enum HtmlPdfError: Error { case failed }

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
//  let size = paperSize()
//      @media print {
//          @page { size: \(size.width)pt \(size.height)pt; margin: 36pt; }
//      }
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

    /* Use UIPrintPageRenderer to paginate and print the web view
    https://www.swiftdevcenter.com/create-pdf-from-uiview-wkwebview-and-uitableview/#:~:text=We%20are%20going%20to%20create,below%20Extensions%20in%20your%20file)
    */

    /* On macOS, use NSPrintOperation to save a paginated PDF
       https://stackoverflow.com/questions/72036111/creating-a-pdf-from-wkwebview-in-macos-11#:~:text=1%20Answer%201)
    */

    @MainActor
    public func generatePDF(_ done: @escaping @MainActor @Sendable
                            (Result<URL, any Error>) -> Void) {
        Task {
            var window: Window? = nil
            let size = paperSize()
            let rect = pageRect()
            let margin = 36.0 // 1/2 inch
            // Make a mutable copy of the incoming view, force light appearance,
            // and provide a callback to capture the WKWebView when it is ready.
            var view = self
            view.forcedColorScheme = .light
            view.onWebViewReady = { webView in
                afterLayout(webView) { height in
                    print("height: \(height)")
        //          let tmpURL = URL.temporaryDirectory
        //              .appendingPathComponent(UUID().uuidString + ".pdf")
                    let file = URL.documentsDirectory
                        .appendingPathComponent("untitled.pdf")
                    #if os(iOS)
                    let formatter = webView.viewPrintFormatter()
                    let renderer  = UIPrintPageRenderer()
                    print("renderer.headerHeight: \(renderer.headerHeight)")
                    print("renderer.footerHeight: \(renderer.footerHeight)")
                    renderer.headerHeight = margin
                    renderer.footerHeight = margin
                    renderer.currentRenderingQuality(forRequested: .best)
                    renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
                    let paperRect      = rect
                    let printableRect  = paperRect.insetBy(dx: margin, dy: 0)
                    webView.frame      = printableRect
                    print("isLoading: \(webView.isLoading)")
                    print("estimatedProgress: \(webView.estimatedProgress)")
                    print("contentSize: \(webView.scrollView.contentSize)")
                    renderer.setValue(paperRect,     forKey: "paperRect")
                    renderer.setValue(printableRect, forKey: "printableRect")
                    print("printableRect: \(renderer.paperRect)")
                    print("printableRect: \(renderer.printableRect)")
                    let data = NSMutableData()
                    UIGraphicsBeginPDFContextToData(data, rect, nil)
                    let n = renderer.numberOfPages
                    renderer.prepare(forDrawingPages: NSMakeRange(0, n))
                    let bounds = UIGraphicsGetPDFContextBounds()
                    print("bounds: \(bounds)")
                    for i in 0 ..< n {
                        UIGraphicsBeginPDFPage()
                        renderer.drawPage(at: i, in: bounds)
                    }
                    UIGraphicsEndPDFContext()
                    if data.write(to: file, atomically: true) {
                        done(.success(file))
                    } else {
                        done(.failure(HtmlPdfError.failed))
                    }
                    window?.isHidden = false
                    window = nil
                #else
                    let printInfo = NSPrintInfo()
                    printInfo.paperSize     = size
                    printInfo.topMargin     = margin
                    printInfo.bottomMargin  = margin
                    printInfo.leftMargin    = margin
                    printInfo.rightMargin   = margin
                    printInfo.jobDisposition = .save
                    printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = file
                    let op = webView.printOperation(with: printInfo)
                    op.showsPrintPanel    = false
                    op.showsProgressPanel = false
                    op.runModal(for: window!, delegate: nil, didRun: nil, contextInfo: nil)
                    done(.success(file))
                    window?.orderOut(nil)
                    window = nil
                #endif
                }
            }
            let host = HostingController(rootView: view)
            host.view.frame = rect
            #if os(iOS)
            window = Window(frame: host.view.frame)
            window?.rootViewController = host
            window?.isHidden = false
            #else
            window = Window(contentRect: rect,
                            styleMask: .borderless,
                            backing: .buffered,
                            defer: false)
            window?.contentViewController = host
            window?.makeKeyAndOrderFront(nil)
            #endif
        }
    }
}

@MainActor
private func contentHeight(_ webView: WKWebView) async -> CGFloat {
    do {
        // JavaScript to get the actual document height
        let heightScript = """
            Math.max(
                document.body.scrollHeight,
                document.body.offsetHeight,
                document.documentElement.clientHeight,
                document.documentElement.scrollHeight,
                document.documentElement.offsetHeight
            );
        """
        
        let result = try await webView.evaluateJavaScript(heightScript)
        if let height = result as? CGFloat {
            return height
        } else if let height = result as? Double {
            return CGFloat(height)
        } else if let height = result as? Int {
            return CGFloat(height)
        } else {
            print("Unexpected height result type: \(type(of: result))")
            return -1
        }
    } catch {
        print("Error getting content height: \(error)")
        return -1
    }
}

private func layout(_ wv: WKWebView) {
    #if os(iOS)
    wv.layoutIfNeeded()
    #else
    wv.layoutSubtreeIfNeeded()
    #endif
}

private func afterLayout(_ wv: WKWebView, _ done: @escaping (CGFloat) -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        let size = paperSize()
        wv.frame.size.width = size.width
        wv.frame.size.height = 0
        layout(wv)
        Task {
            let height = await contentHeight(wv)
            if (height > 0) {
                wv.frame.size = CGSize(width: size.width, height: height)
                layout(wv)
            }
            DispatchQueue.main.async { done(height) }
        }
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

