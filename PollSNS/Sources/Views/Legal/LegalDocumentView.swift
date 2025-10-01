import SwiftUI
import WebKit

struct LegalDocumentView: View {
    let title: String
    let htmlFileName: String // 例: "terms-ja", "privacy-ja"

    var body: some View {
        WebView(htmlFileName: htmlFileName)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(UIColor.systemBackground))
    }
}

private struct WebView: UIViewRepresentable {
    let htmlFileName: String

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.contentInsetAdjustmentBehavior = .automatic
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 1) Legal サブディレクトリを探す（青フォルダの場合）
        let urlInLegal = Bundle.main.url(forResource: htmlFileName, withExtension: "html", subdirectory: "Legal")
        // 2) ルート直下も探す（黄色フォルダの場合）
        let urlInRoot = Bundle.main.url(forResource: htmlFileName, withExtension: "html")

        if let url = urlInLegal ?? urlInRoot {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            webView.scrollView.setContentOffset(.zero, animated: false)
        } else {
            let html = """
            <html><meta charset='utf-8'><body style='font: -apple-system-body; padding: 16px'>
            <h2>ドキュメントが見つかりません</h2><p>\(htmlFileName).html</p></body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}
