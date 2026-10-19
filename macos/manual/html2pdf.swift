// html2pdf <in.html> <out.pdf>: paginated A4 PDF through WebKit's print path
import AppKit
import WebKit

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

class Loader: NSObject, WKNavigationDelegate {
    var done = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done = true }
}
let loader = Loader()
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 794, height: 1123))
web.navigationDelegate = loader
web.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())
while !loader.done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
RunLoop.main.run(until: Date().addingTimeInterval(0.5))

let info = NSPrintInfo()
info.paperSize = NSSize(width: 595.28, height: 841.89)
info.topMargin = 40; info.bottomMargin = 46; info.leftMargin = 0; info.rightMargin = 0
info.horizontalPagination = .fit
info.verticalPagination = .automatic
info.jobDisposition = .save
info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
let op = web.printOperation(with: info)
op.showsPrintPanel = false
op.showsProgressPanel = false
op.view?.frame = web.bounds
let window = NSWindow(contentRect: web.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = web
op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
RunLoop.main.run(until: Date().addingTimeInterval(3))
print(FileManager.default.fileExists(atPath: output.path) ? "wrote \(output.path)" : "no pdf")
