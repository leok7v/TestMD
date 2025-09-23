import SwiftUI
import SwiftData
import WebKit

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

func generatePDF(_ view: WKWebView) -> Data? {
    return nil
}

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
                    Task {
                        do {
                            let c = WKPDFConfiguration()
                            let data = try await wv.pdf(configuration: c)
                            print("PDF generated successfully: \(data.count) bytes")
                            file = URL.documentsDirectory.appendingPathComponent("untitled.pdf")
                            try? FileManager.default.removeItem(at: file!)
                            try? data.write(to: file!)
                        } catch {
                            print("PDF generation error: \(error)")
                            file = nil
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
                    ShareLink(item: file, subject: Text("Subject"),
                           message: Text("message"))
                }
            }

        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
