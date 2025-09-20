import Foundation
import JavaScriptCore

public class Markdown {

    private let context: JSContext

    private let integration = """
(function () {
  function normLang(lang) {
    if (!lang) { return 'markup'; }
    lang = ('' + lang).toLowerCase();
    const map = { js:'javascript', ts:'typescript', 'c++':'cpp', 'c#':'csharp',
                  sh:'bash', objc:'objectivec', m:'objectivec' };
    return map[lang] || lang;
  }
  marked.use(markedHighlight.markedHighlight({
    langPrefix: 'language-',
    emptyLangClass: '',
    highlight(code, lang /* = infoString head */) {
      const L = normLang(lang);
      const g = Prism.languages[L];
      return g ? Prism.highlight(code, g, L) : code; /* plain text fallback */
    }
  }));
  Markdown = { parse: marked.parse };
})();
"""
    func load_js(_ name: String) {
        let path = Bundle.main.path(forResource: name, ofType: "js")!
        let script = try! String(contentsOfFile: path, encoding: .utf8)
        context.evaluateScript(script)
    }

    init() {
        context = JSContext()!
        load_js("prism.min")
        load_js("marked.min")
        load_js("marked-highlight.min")
        context.evaluateScript(integration)
        if let exception = context.exception {
            let message = exception.toString() ?? "Unknown error"
            fatalError("JavaScript setup failed: \(message)")
        }
    }
    
    func parse(_ md: String) -> String { // ~= 2 millisecond for test.md
        let parser = context.objectForKeyedSubscript("marked")!
        return parser.invokeMethod("parse", withArguments: [md]).toString()!
    }
    
    static func benchmark(_ md: String, _ n: Int = 100) {
        let parser = Markdown()
        _ = parser.parse(md) // warm-up
        let t0 = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<n { _ = parser.parse(md) }
        let dt = Double(DispatchTime.now().uptimeNanoseconds - t0)
        let ms = dt / 1e6
        let per = ms / Double(n)
        let qps = 1000.0 / per
        print(String(format: "n=%d  total=%.2f ms  per=%.3f ms  qps=%.1f",
                     n, ms, per, qps))
    }
    
}
