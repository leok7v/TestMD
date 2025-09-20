import Foundation
import JavaScriptCore

public class Markdown {

    private let context: JSContext

    private let setupScript = """
const renderer = new marked.Renderer();

renderer.code = function(code, lang) {
  const languageClass = lang ? `language-${lang}` : '';
  const highlightedCode = lang && Prism.languages[lang] 
    ? Prism.highlight(code, Prism.languages[lang], lang) 
    : code;
  return `<pre class="${languageClass}"><code class="${languageClass}">${highlightedCode}</code></pre>`;
};

marked.setOptions({
  renderer: renderer,
  highlight: (code, lang) => {
    return code; 
  }
});

MarkdownParser = { parse: marked.parse };
"""

    func load_js(_ name: String) {
        var path = Bundle.main.path(forResource: name, ofType: "js")!
        let script = try! String(contentsOfFile: path, encoding: .utf8)
        context.evaluateScript(script)
    }

    init() {
        context = JSContext()!
        load_js("prism.min")
        load_js("marked.min")
        load_js("marked-highlight.min")
        context.evaluateScript(setupScript)
        if let exception = context.exception {
            let message = exception.toString() ?? "Unknown error"
            fatalError("JavaScript setup failed: \(message)")
        }
    }
    
    func parse(_ md: String) -> String {
        let parser = context.objectForKeyedSubscript("MarkdownParser")!
        return parser.invokeMethod("parse", withArguments: [md]).toString()!
    }
}
