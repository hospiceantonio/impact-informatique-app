import UIKit
import WebKit
import CoreLocation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = BizzooController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

final class BizzooController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply, CLLocationManagerDelegate {
    private var web: WKWebView!
    private let locationManager = CLLocationManager()
    private var positionReply: ((Any?, String?) -> Void)?
    private let variant = Bundle.main.bundleIdentifier?.hasSuffix(".admin") == true ? "admin" : "client"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "bizzoo")
        if let path = Bundle.main.url(forResource: "bridge", withExtension: "js"), let script = try? String(contentsOf: path) {
            configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        web = WKWebView(frame: .zero, configuration: configuration)
        web.translatesAutoresizingMaskIntoConstraints = false
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            web.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        locationManager.delegate = self
        if let root = Bundle.main.resourceURL?.appendingPathComponent(variant), FileManager.default.fileExists(atPath: root.appendingPathComponent("index.html").path) {
            web.loadFileURL(root.appendingPathComponent("index.html"), allowingReadAccessTo: root)
        }
    }

    // Le pont natif reste réservé au contenu embarqué de l'application.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
              let data = message.body as? [String: Any], let action = data["action"] as? String else {
            replyHandler(nil, "Origine refusée"); return
        }
        switch action {
        case "position":
            guard positionReply == nil else { replyHandler(nil, "Une demande de position est déjà en cours"); return }
            positionReply = replyHandler
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            } else { requestPosition() }
        case "share":
            guard let encoded = data["base64"] as? String, encoded.count <= 84_000_000,
                  let bytes = Data(base64Encoded: encoded), let name = data["name"] as? String else {
                replyHandler(nil, "Fichier invalide"); return
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent)
                try bytes.write(to: url)
                let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                sheet.popoverPresentationController?.sourceView = view
                sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                sheet.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: folder) }
                present(sheet, animated: true)
                replyHandler(true, nil)
            } catch { replyHandler(nil, "Impossible de préparer le fichier") }
        default: replyHandler(nil, "Action inconnue")
        }
    }

    private func requestPosition() {
        if [.authorizedWhenInUse, .authorizedAlways].contains(locationManager.authorizationStatus) {
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager.requestLocation()
        } else {
            positionReply?(nil, "Localisation refusée. Vous pouvez saisir votre adresse.")
            positionReply = nil
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if positionReply != nil && manager.authorizationStatus != .notDetermined { requestPosition() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        positionReply?(["coords": ["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude, "accuracy": location.horizontalAccuracy], "timestamp": location.timestamp.timeIntervalSince1970 * 1000], nil)
        positionReply = nil
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        positionReply?(nil, "Position indisponible. Vous pouvez saisir votre adresse.")
        positionReply = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL {
            guard let root = Bundle.main.resourceURL?.appendingPathComponent(variant).standardizedFileURL.path,
                  url.standardizedFileURL.path.hasPrefix(root + "/") else { decisionHandler(.cancel); return }
            decisionHandler(.allow); return
        }
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if ["https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
            UIApplication.shared.open(url)
        }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "https" { UIApplication.shared.open(url) }
        return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: "BIZZOO", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "BIZZOO", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Confirmer", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
}
