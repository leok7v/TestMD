import SwiftUI
import SwiftData

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

struct ItemView: View {
    let item: Item
    static let markdown = Markdown()
    static let path = Bundle.main.path(forResource: "test", ofType: "md")!
    static let md = try! String(contentsOfFile: path, encoding: .utf8)
    @State private var pdfURL: URL?
    var body: some View {
        let url = try! renderPDFData(MarkdownlView(md: Self.md), named: "readme.pdf")
        let _ = print(url)
        VStack(alignment: .leading, spacing: 12) {
            Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
            MarkdownlView(md: Self.md)
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .topLeading)
            HStack {
                Button("Make PDF") { // text.rectangle.page.fill
                    do {
                        pdfURL = try renderPDFData(MarkdownlView(md: Self.md),
                                                   named: "readme.pdf")
                        if let u = pdfURL { print(u) }
                    } catch {
                        print("PDF error: \(error)")
                    }
                }
                #if os(iOS)
                if let u = pdfURL { ShareLink("Share", item: u) }
                #endif
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
