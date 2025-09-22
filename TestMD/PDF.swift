// PDF.swift
import SwiftUI
import PDFKit
#if os(macOS)
import AppKit
#endif

private extension Data {
    func writeTempPDF(named name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(name)
        try write(to: url, options: .atomic)
        return url
    }
}

private struct _PageSpec {
    let size: CGSize
    let margin: CGFloat
    var rect: CGRect { CGRect(origin: .zero, size: size) }
    var contentWidth: CGFloat { size.width - margin * 2 }
    var contentHeight: CGFloat { size.height - margin * 2 }
}

#if os(macOS)
private func render<V: View>(_ v: V,
                             _ spec: _PageSpec,
                             _ fill: Bool) -> Data {
    let ctrl = NSHostingController(rootView: v)
    ctrl.view.wantsLayer = true
    ctrl.view.layer?.backgroundColor = NSColor.clear.cgColor
    var fit = ctrl.sizeThatFits(in: CGSize(width: spec.contentWidth,
                                           height: .greatestFiniteMagnitude))
    var totalHeight = fit.height
    if !totalHeight.isFinite || totalHeight > 200000 {
        ctrl.view.frame = CGRect(x: 0, y: 0,
                                 width: spec.contentWidth, height: 10)
        ctrl.view.layoutSubtreeIfNeeded()
        fit = ctrl.view.fittingSize
        totalHeight = fit.height
    }
    if !totalHeight.isFinite || totalHeight < 1 {
        totalHeight = spec.contentHeight
    }
    totalHeight = ceil(max(1, totalHeight))
    ctrl.view.frame = CGRect(x: 0, y: 0,
                             width: spec.contentWidth, height: totalHeight)
    ctrl.view.layoutSubtreeIfNeeded()
    let pages = Int(ceil(totalHeight / spec.contentHeight))
    let data = NSMutableData()
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    var mediaBox = spec.rect
    let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
    for p in 0..<pages {
        ctx.beginPDFPage([kCGPDFContextMediaBox: mediaBox] as CFDictionary)
        if fill {
            ctx.saveGState()
            ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
            ctx.fill(spec.rect)
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: spec.size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: spec.margin,
                        y: spec.margin - CGFloat(p) * spec.contentHeight)
        ctrl.view.layer?.render(in: ctx)
        ctx.restoreGState()
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return data as Data
}
#endif

#if os(iOS)
private func render<V: View>(_ v: V,
                             _ spec: _PageSpec,
                             _ fill: Bool) -> Data {
    let host = UIHostingController(rootView: v)
    host.view.backgroundColor = .clear
    let fit = host.sizeThatFits(in: CGSize(width: spec.contentWidth,
                                           height: .greatestFiniteMagnitude))
    let totalHeight = max(1, ceil(fit.height))
    host.view.bounds = CGRect(x: 0, y: 0,
                              width: spec.contentWidth, height: totalHeight)
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    let pages = Int(ceil(totalHeight / spec.contentHeight))
    let renderer = UIGraphicsPDFRenderer(bounds: spec.rect)
    let pdfData = renderer.pdfData { ctx in
        for p in 0..<pages {
            ctx.beginPage()
            let g = ctx.cgContext
            if fill {
                g.saveGState()
                g.setFillColor(UIColor.systemBackground.cgColor)
                g.fill(spec.rect)
                g.restoreGState()
            }
            g.saveGState()
            g.translateBy(x: 0, y: spec.size.height)
            g.scaleBy(x: 1, y: -1)
            g.translateBy(x: spec.margin,
                          y: spec.margin - CGFloat(p) * spec.contentHeight)
            host.view.layer.render(in: g)
            g.restoreGState()
        }
    }
    return pdfData
}
#endif

@MainActor
func renderPDFData<V: View>(_ view: V,
                            named name: String = "document.pdf",
                            pageWidth: CGFloat = 8.5 * 72.0,
                            pageHeight: CGFloat = 11.0 * 72.0,
                            margin: CGFloat = 10.0,
                            fillBackground: Bool = true) throws -> URL {
    let spec = _PageSpec(size: CGSize(width: pageWidth, height: pageHeight),
                         margin: margin)
    let pdfData = render(view, spec, fillBackground)
    if let doc = PDFDocument(data: pdfData),
       let d = doc.dataRepresentation() {
        return try d.writeTempPDF(named: name)
    } else {
        return try pdfData.writeTempPDF(named: name)
    }
}
