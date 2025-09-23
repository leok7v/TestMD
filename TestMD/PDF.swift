// PDF.swift
import SwiftUI

func generatePDF_not_working<Content: View>(_ view: Content) throws -> URL {
    let url = URL.temporaryDirectory.appendingPathComponent("untitled.pdf")
    if FileManager.default.fileExists(atPath: url.path()) {
        try FileManager.default.removeItem(at: url)
    }
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0
    renderer.render(rasterizationScale: 1.0, renderer: { size, ctx in
        var box = CGRect(x: 0, y: 0, width: 500, height: 500)
//      var box = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else {
            return
        }
        pdf.beginPDFPage(nil)
        ctx(pdf)
        pdf.endPDFPage()
        pdf.closePDF()
        
    })
    return url
}

private func paper() -> CGSize {
    let A4 = CGSize(width: 595, height: 842) // in points
    let Letter = CGSize(width: 612, height: 792)
    let LetterRegions: Set<String> = ["US", "CA", "MX", "CL", "CO",
                                      "CR", "PA", "PE", "PH", "PR"]
    return LetterRegions.contains(Locale.current.region?.identifier ?? "") ?
           Letter : A4
}
