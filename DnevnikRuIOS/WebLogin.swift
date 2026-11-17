import SwiftUI
import WebKit

@MainActor
final class WebLoginController: ObservableObject {
    @Published var currentHost = "dnevnik.ru"
    @Published var navigationError: String?
    weak var webView: WKWebView?
    func finish(using store: SchoolStore) {
        guard let webView else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let trusted = cookies.compactMap(SessionCookie.init)
            Task { @MainActor in
                await store.acceptCookies(trusted, userAgent: webView.customUserAgent ?? "")
            }
        }
    }
}
struct WebsiteLoginScreen: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = WebLoginController()
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                    Text(browser.currentHost)
                        .font(.footnote.monospaced())
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.thinMaterial)
                if let error = browser.navigationError {
                    Text(error).font(.caption).foregroundStyle(.red).padding(8)
                }
                WebsiteWebView(browser: browser)
                HStack(spacing: 12) {
                    Text("Введите пароль и код только на странице провайдера.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Готово") { browser.finish(using: store) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(12)
            }
            .navigationTitle("Вход в Дневник.ру")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { store.loginPresented = false; dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(store.isLoading)
    }
}
struct WebsiteWebView: UIViewRepresentable {
    @ObservedObject var browser: WebLoginController
    func makeCoordinator() -> Coordinator { Coordinator(browser: browser) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Isolate the login session. Authentication cookies are copied only after the user finishes.
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        browser.webView = view
        view.load(URLRequest(url: URL(string: "https://dnevnik.ru/marks")!))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var browser: WebLoginController?
        init(browser: WebLoginController) { self.browser = browser }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            browser?.currentHost = webView.url?.host ?? "dnevnik.ru"
            browser?.navigationError = nil
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            browser?.currentHost = webView.url?.host ?? "dnevnik.ru"
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            browser?.navigationError = "Не удалось открыть страницу: \(error.localizedDescription)"
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url,
               url.scheme != "https" && url.scheme != "about" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
