import Foundation
import PDFKit

enum NativePdfImport {
  static func extract(_ source: URL, output: URL, name: String) throws {
    guard let document = PDFDocument(url: source), !document.isEncrypted else {
      throw BookDocumentFailure(code: "pdf_unavailable", message: "PDF 无法读取或受到加密保护")
    }
    guard document.pageCount > 0, document.pageCount <= 10_000 else {
      throw BookDocumentFailure(code: "pdf_limit", message: "PDF 页数超出导入范围")
    }
    let file = output.appendingPathComponent("content.txt")
    guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
      throw BookDocumentFailure(code: "pdf_output", message: "无法创建 PDF 文字暂存文件")
    }
    let sink = try FileHandle(forWritingTo: file)
    defer { try? sink.close() }
    var bytes = 0
    for index in 0..<document.pageCount {
      let text = autoreleasepool { document.page(at: index)?.string ?? "" }
      if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
      let data = Data((text + "\n\n").utf8)
      bytes += data.count
      guard bytes <= 64 * 1024 * 1024 else {
        throw BookDocumentFailure(code: "pdf_limit", message: "PDF 文字超过导入大小限制")
      }
      if #available(iOS 13.4, *) {
        try sink.write(contentsOf: data)
      } else {
        sink.write(data)
      }
    }
    guard bytes > 0 else {
      throw BookDocumentFailure(code: "pdf_no_text", message: "PDF 不含可提取文字；扫描版需先进行文字识别")
    }
  }
}
