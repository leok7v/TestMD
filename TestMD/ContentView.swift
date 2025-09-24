import SwiftUI
import SwiftData
import WebKit
import PDFKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        ItemView(item: item)
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

struct MarkdownlView: View {
    let md: String
    static let markdown = Markdown()
    var body: some View {
        let html = Self.markdown.parse(md)
        HtmlView(html: html)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: .topLeading)
    }
}

let path = Bundle.main.path(forResource: "test", ofType: "md")!
let md = try! String(contentsOfFile: path, encoding: .utf8)
let markdown = Markdown()
let html = markdown.parse(md)

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
            return 1000 // fallback
        }
    } catch {
        print("Error getting content height: \(error)")
        return 0 // fallback
    }
}

@MainActor
private func layout(_ wv: WKWebView) async -> CGSize {
    let size = paperSize()
    wv.frame.size.width = size.width
    wv.frame.size.height = 0
    #if os(iOS)
    wv.layoutIfNeeded()
    #else
    wv.layoutSubtreeIfNeeded()
    #endif
    let height = await contentHeight(wv)
    return CGSize(width: size.width, height: height)
}


// PDF Header at the moment of implementation looks like this:
// 0000  25 50 44 46 2d 31 2e 33  0a 25 c4 e5 f2 e5 eb a7  |%PDF-1.3.%......|
// 0010  f3 a0 d0 c4 c6 0a 33 20  30 20 6f 62 6a 0a 3c 3c  |......3 0 obj.<<|
// 0020  20 2f 46 69 6c 74 65 72  20 2f 46 6c 61 74 65 44  | /Filter /FlateD|
// 0030  65 63 6f 64 65 20 2f 4c  65 6e 67 74 68 20 38 34  |ecode /Length 84|
// 0040  20 3e 3e 0a 73 74 72 65  61 6d 0a 78 01 25 ca c1  | >>.stream.x.%..|

extension Data {
    func pdfStreamLength() -> Int {
        let bytes = self.withUnsafeBytes { $0.bindMemory(to: UInt8.self) }
        let searchLen = Swift.min(self.count, 500)
        var start = -1 // Find "<<"
        for i in 0..<(searchLen-1) {
            if bytes[i] == 0x3c && bytes[i+1] == 0x3c {  // "<<"
                start = i + 2
                break
            }
        }
        if start <= 0 { return -1 }
        var end = -1 // Find ">>"
        for i in start..<(searchLen-1) {
            if bytes[i] == 0x3e && bytes[i+1] == 0x3e {  // ">>"
                end = i
                break
            }
        }
        if end <= start { return -1 }
        let dictData = Data(bytes[start..<end]) // Extract between << and >>
        guard let dictStr = String(data: dictData, encoding: .ascii) else {
            return -1
        }
        if let lengthPos = dictStr.range(of: "/Length ") {
            let afterLength = dictStr[lengthPos.upperBound...]
            let numStr = String(afterLength.prefix { $0.isNumber })
            return Int(numStr) ?? -1
        }
        return -1
    }
}

extension Data {
    func hexdump(maxBytes: Int = 3722) {
        let bytes = self.prefix(maxBytes)
        var result = ""
        for offset in stride(from: 0, to: bytes.count, by: 16) {
            let chunk = bytes[offset..<Swift.min(offset + 16, bytes.count)]
            result += String(format: "%08x  ", offset)
            for i in 0..<16 {
                if i == 8 { result += " " }
                if i < chunk.count {
                    let byte = chunk[chunk.startIndex + i]
                    result += String(format: "%02x ", byte)
                } else {
                    result += "   "
                }
            }
            result += " |"
            for i in 0..<chunk.count {
                let byte = chunk[chunk.startIndex + i]
                let char = (byte >= 32 && byte <= 126) ? Character(UnicodeScalar(byte)) : "."
                result += String(char)
            }
            result += "|\n"
        }
        if self.count > maxBytes {
            result += "... (\(self.count - maxBytes) more bytes)\n"
        }
        print(result)
    }
}

enum FileError: Error { case writeFailed }

func createPDF_A(_ wv: WKWebView,
    completionHandler: @escaping @MainActor @Sendable (Result<URL, any Error>)
                                                        -> Void) {
    Task {
        let size = paperSize()
        let content = await layout(wv)
        let pageCount = max(1, Int(ceil(content.height / size.height)))
        print("\(content.width) x \(content.height)")
        let doc = PDFDocument()
        doc.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "My Document Title",
            PDFDocumentAttribute.authorAttribute: "John Doe",
            PDFDocumentAttribute.subjectAttribute: "Document Subject Description",
            PDFDocumentAttribute.creatorAttribute: "My App Name",
            PDFDocumentAttribute.producerAttribute: "My Custom PDF Generator",
            PDFDocumentAttribute.creationDateAttribute: Date(),
            PDFDocumentAttribute.modificationDateAttribute: Date(),
            PDFDocumentAttribute.keywordsAttribute: ["keyword1", "keyword2", "important"]
        ]
        let c = WKPDFConfiguration()
        var y = CGFloat(pageCount) * size.height
        c.rect = CGRect(x: 0, y: y, width: size.width, height: size.height)
        let emptyPage = try await wv.pdf(configuration: c)
        let empty = emptyPage.pdfStreamLength()
//      emptyPage.hexdump()
        var count = 0
        print("emptyPage: \(emptyPage.count) bytes pdfStreamLength: \(emptyPage.pdfStreamLength())")
        for i in 0..<pageCount {
            do {
                y = CGFloat(i) * size.height
                c.rect = CGRect(x: 0, y: y, width: size.width, height: size.height)
                let data = try await wv.pdf(configuration: c)
                print("Page[\(i)]: \(data.count) bytes pdfStreamLength: \(data.pdfStreamLength())")
                let length = data.pdfStreamLength()
                // iOS implementation of WebKit sucks in .pdf() and
                // generates 2 empty pages at the end of 7 pages document
                if (empty > 0 && length > 0 && length <= empty + 16) {
                    // skip empty pages
                    // emptyPage.hexdump()
                } else {
                    let pd = PDFDocument(data: data)
                    let page = pd!.page(at: 0)?.copy() as! PDFPage
                    doc.insert(page, at: count)
                    count += 1
                }
            } catch {
                print("PDF generation error: \(error)")
                completionHandler(.failure(error))
                return
            }
        }
        print("pageCount: \(pageCount) doc.pageCount: \(doc.pageCount)")
        let file = URL.documentsDirectory.appendingPathComponent("untitled.pdf")
        try? FileManager.default.removeItem(at: file)
        if doc.write(to: file) {
            completionHandler(.success(file))
        } else {
            completionHandler(.failure(FileError.writeFailed))
        }
    }
}

func createPDF_B(_ wv: WKWebView,
               _ completionHandler: @escaping @MainActor @Sendable (Result<URL, any Error>) -> Void) {
    Task {
        let content = await layout(wv)
        let cfg = WKPDFConfiguration()
        cfg.rect = .init(origin: .zero, size: content)
        cfg.allowTransparentBackground = false
        wv.createPDF(configuration: cfg) { result in
            switch result {
                case .success(let data):
                    print("PDF creation successful: \(data.count) bytes")
                    let file = URL.documentsDirectory.appendingPathComponent("untitled.pdf")
                    try? FileManager.default.removeItem(at: file)
                    do {
                        try data.write(to: file)
                        completionHandler(.success(file))
                    } catch {
                        completionHandler(.failure(error))
                    }
                case .failure(let error):
                    print("PDF creation failed with error: \(error.localizedDescription)")
                    completionHandler(.failure(error))
            }
        }
    }
}

#if os(iOS)
func createPDF_C(_ wv: WKWebView, completion: @escaping (Result<URL, Error>) -> Void) { // Paginated
    Task {
        let content = await layout(wv)
        let formatter = wv.viewPrintFormatter()
        let render = UIPrintPageRenderer()
        render.addPrintFormatter(formatter, startingAtPageAt: 0)
        let paperRect = pageRect() // Letter or A4 in points
        let margin = 36.0 // 1/2 inch in points
        let printableRect = paperRect.insetBy(dx: margin, dy: margin)
        render.setValue(NSValue(cgRect: paperRect), forKey: "paperRect")
        render.setValue(NSValue(cgRect: printableRect), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paperRect, nil)
        var numPages = render.numberOfPages
        let n = Int(ceil(content.height / printableRect.height))
        if (numPages < n) {
            numPages = n
        }
        for i in 0..<numPages {
            UIGraphicsBeginPDFPage()
            render.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        // temporaryDirectory does not work for iOS charing
        let file = URL.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        do {
            try data.write(to: file)
            completion(.success(file))
        } catch {
            completion(.failure(error))
        }
    }
}

#elseif os(macOS)
import AppKit

func createPDF_C(_ wv: WKWebView, completion: @escaping (Result<URL, Error>) -> Void) {
    Task {
        let size = paperSize()
        let _ = await layout(wv)
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        let margin = 36.0 // 1/2 inch in in points
        info.paperSize      = size
        info.topMargin      = margin
        info.bottomMargin   = margin
        info.leftMargin     = margin
        info.rightMargin    = margin
        info.jobDisposition = .save
        let file = URL.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        let dictionary = info.dictionary()
        let save = NSPrintInfo.JobDisposition.save.rawValue
        dictionary[NSPrintInfo.AttributeKey.jobDisposition] = save
        dictionary[NSPrintInfo.AttributeKey.jobSavingURL]   = file
        let op = wv.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        let rect = NSRect(x: 0, y: 0, width: 100, height: 100)
        let hidden = NSWindow(contentRect: rect,  styleMask: .borderless,
                                  backing: .buffered, defer: false)
        op.runModal(for: hidden, delegate: nil, didRun: nil, contextInfo: nil)
        completion(.success(file))
    }
}

@MainActor
func save(_ data: Data) throws -> URL?  {
    var url : URL? = nil
    let savePanel = NSSavePanel()
    savePanel.nameFieldStringValue = "document.pdf"
    savePanel.begin { response in
        if response == .OK, let u = savePanel.url {
            do {
                try data.write(to: u)
                url = u
            } catch {
                print("Failed to write to: \(url!.lastPathComponent) " +
                      "because of \"\(error.localizedDescription)\"")
            }
        }
    }
    return url
}

@MainActor
func saveAs(_ url: URL) throws -> URL?  {
    let data = try? Data(contentsOf: url)
    try? FileManager.default.removeItem(at: url)
    return save(data)
}

#endif

let ABC = 2

struct ItemView: View {
    let item: Item
    @State var file: URL?
    @State var err: Error?
    @State private var webView: WKWebView?
    var body: some View {
        let view = HtmlView(html: html) { webView in
            self.webView = webView
        }
        VStack(alignment: .leading, spacing: 12) {
            Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
            view.frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .topLeading)
            Button(action: {
                if let wv = webView {
                    if (ABC == 0) {
                        createPDF_A(wv) { result in
                            print("Result: \(result)")
                            switch result {
                            case .success(let url):
                                print("PDF creation successful.")
                                file = url
                            case .failure(let error):
                                err = error
                                print("PDF creation failed with error: \(error.localizedDescription)")
                            }
                        }
                    } else if (ABC == 1) {
                        createPDF_B(wv) { result in
                            switch result {
                                case .success(let url):
                                    print("PDF creation successful: \(url)")
                                    file = url
                                case .failure(let error):
                                    print("PDF creation failed with error: \(error.localizedDescription)")
                                    err = error
                            }
                        }
                    } else if (ABC == 2) {
                        createPDF_C(wv) { result in
                            switch result {
                                case .success(let url):
                                    print("PDF creation successful: \(url)")
                                    file = url
                                case .failure(let error):
                                    print("PDF creation failed with error: \(error.localizedDescription)")
                                    err = error
                            }
                        }
                    }
                }
            }, label: {
                Text("PDF")
            })
            .font(.title2)
            if let file {
                HStack {
                    Text("PDF Generated!")
                    // if message: != nil and Save To Files choosen on iOS
                    // message is getting saved as plain text file instead
                    // of being shown to user
                    ShareLink(item: file, subject: Text("Subject: abc"))
                }
            }
        }
    }
}


#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
