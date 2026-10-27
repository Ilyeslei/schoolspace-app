//
//  SessionManager.swift
//  SchoolSpaceApp
//
//  Gestion de la session utilisateur : connexion, reconnexion automatique, déconnexion
//

import Foundation
import SwiftUI
import WebKit
import OSLog

@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var currentSession: UserSession?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false

    private let keychain = KeychainService.shared
    private let logger = Logger(subsystem: "com.example.schoolspace", category: "SessionManager")

    private init() {
        Task {
            await restoreSession()
        }
    }

    // MARK: - Restauration session (lancement app)

    func restoreSession() async {
        guard let session = keychain.load() else {
            logger.info("Aucune session sauvegardée")
            return
        }

        if session.isValid {
            logger.info("Session valide restaurée pour \(session.displayName)")
            currentSession = se
        } else if session.isExpired {
            logger.info("Session expirée, tentative de renouvellement")
            await tryRefreshSession(session)
        } else {
            logger.info("Session invalide, suppression")
            logout()
        }
    }

    // MARK: - Connexion via WKWebView

    func login(at url: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let loginURL: URL
        if url.contains("mobile.") || url.contains("eleve.html") || url.contains("parent.html") {
            loginURL = URL(string: url)!
        } else {
            let baseURL = url.hasSuffix("/") ? url : url + "/"
            loginURL = URL(string: baseURL + "mobile.eleve.html")!
        }

        logger.info("Ouverture page de connexion : \(loginURL.absoluteString)")

        let success = try await WebLoginCoordinator.shared.startLogin(at: loginURL)

        if success {
            logger.info("Connexion réussie détectée")
        } else {
            throw SchoolSpaceError.loginFailed
        }
    }

    // MARK: - Renouvellement de session

    private func tryRefreshSess
        logger.warning("Renouvellement de session non implémenté, reconnexion requise")
        logout()
        showErrorMessage("Votre session a expiré. Veuillez vous reconnecter.")
    }

    // MARK: - Création session après login réussi

    func createSession(userId: String, displayName: String, establishmentId: String, establishmentUrl: String, sessionToken: String) {
        let expiresAt = Date().addingTimeInterval(30 * 24 * 60 * 60)

        let session = UserSession(
            userId: userId,
            displayName: displayName,
            establishmentId: establishmentId,
            establishmentUrl: establishmentUrl,
            sessionToken: sessionToken,
            expiresAt: expiresAt
        )

        do {
            try keychain.save(session)
            currentSession = session
            logger.info("Session créée et sauvegardée pour \(displayName)")
        } catch {
            logger.error("Erreur sauvegarde session : \(error.localizedDescription)")
            showErrorMessage("Impossible de sauvegarder la session")
        }
    }

    // MARK: - Déconnexion

    func logout() {
        keychain.delete()
        currentSession = nil
        logger.info("Déconnexion effectuée")
    }

    // MARK: - Gestion erreurs

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    func dismissError() {
        showError = false
        errorMessage = nil
    }
}

// MARK: - Coordinateur WKWebView pour la connexion

@MainActor
final class WebLoginCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = WebLoginCoordinator()

    private var continuation: CheckedContinuation<Bool, Error>?
    private var webView: WKWebView?
    private var hostViewController: UIViewController?
    private let sessionManager = SessionManager.shared
    private let logger = Logger(subsystem: "com.example.schoolspace", category: "WebLogin")

    private override init() {
        super.init()
    }

    func startLogin(at url: URL) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            presentWebView(with: url)
        }
    }

    private func presentWebView(with url: URL) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let script = WKUserScript(
            source: loginDetectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)
        config.userContentController.add(self, name: "loginObserver")

        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
        webView?.allowsBackForwardNavigationGestures = true

        webView?.load(URLRequest(url: url))

        let navController = UINavigationController()
        navController.modalPresentationStyle = .fullScreen
        navController.view.backgroundColor = .systemBackground

        let vc = WebLoginViewController(webView: webView!)
        navController.setViewControllers([vc], animated: false)

        hostViewController = navController

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(navController, animated: true)
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.logger.debug("Page chargée : \(webView.url?.absoluteString ?? "inconnu")")
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.logger.error("Erreur chargement : \(error.localizedDescription)")
            self.finishLogin(success: false, error: SchoolSpaceError.networkError(e
        }
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            guard message.name == "loginObserver",
                  let body = message.body as? [String: Any],
                  let event = body["event"] as? String else { return }

            switch event {
            case "loginSuccess":
                if let userId = body["userId"] as? String,
                   let displayName = body["displayName"] as? String,
                   let establishmentId = body["establishmentId"] as? String,
                   let sessionToken = body["sessionToken"] as? String {

                    let establishmentUrl = self.webView?.url.flatMap { $0.absoluteString } ?? ""
                    self.sessionManager.createSession(
                        userId: userId,
                        displayName: displayName,
                        establishmentId: establishmentId,
                        establishmentUrl: establishmentUrl,
                        sessionToken: sessionToken
                    )
                    self.finishLogin(success: true)
                }

            case "loginError":
                if let errorMsg = body["message"] as? String {
                    self.logger.warning("Erreur login détectée : \(errorMsg)")
                }

            default:
                break
            }
        }
    }

    private func finishLogin(success: Bool, error: Error? = nil) {
        hostViewController?.dismiss(animated: true) { [weak self] in
            self?.webView = nil
            self?.hostViewController = nil

            if success {
                self?.continuation?.resume(returning: true)
            } else {
                self?.continuation?.resume(throwing: error ?? SchoolSpaceError.loginFailed)
            }
            self?.continuation = nil
        }
    }

    // MARK: - Script d'injection pour détecter la connexion

    private let loginDetectionScript = """
    (function() {
        'use strict';

        function sendEvent(event, data) {
            window.webkit.messageHandlers.loginObserver.postMessage({
                event: event,
                ...data
            });
        }

        function checkLoginState() {
            const userNameEl = document.querySelector('.user-name, .header .name, [data-user-name], .welcome-message');
            if (userNameEl && userNameEl.textContent.trim()) {
                const estabEl = document.querySelector('[data-establishment-id], .establishment-name');
                const establishmentId = estabEl?.dataset?.establishmentId || estabEl?.textContent?.trim() || 'unknown';

                const cookies = document.cookie;
                const sessionMatch = cookies.match(/sessionid=([^;]+)/i) || cookies.match(/PHPSESSID=([^;]+)/i) || cookies.match(/JSESSIONID=([^;]+)/i);
                const sessionToken = sessionMatch ? sessionMatch[1] : cookies;

                sendEvent('loginSuccess', {
                    userId: 'current_user',
                    displayName: userNameEl.textContent.trim(),
                    establishmentId: establishmentId,
                    sessionToken: sessionToken
                });
                return true;
            }

            const postLoginElements = document.querySelectorAll('.main-content, .dashboard, .notes-container, .emploi-temps, .cahier-textes');
            if (postLoginElements.length > 0) {
                const sessionToken = document.cookie;
                sendEvent('loginSuccess', {
                    userId: 'current_user',
                    displayName: 'Utilisateur',
                    establishmentId: 'unknown',
                    sessionToken: sessionToken
                });
                return true;
            }

            return false;
        }

        if (checkLoginState()) return;

        const observer = new MutationObserver((mutations) => {
            if (checkLoginState()) {
                observer.disconnect();
            }
        });

        observer.observe(document.body, {
            childList: true,
            subtree: true,
            characterData: true
        });

        const interval = setInterval(() => {
            if (checkLoginState()) {
                clearInterval(interval);
                observer.disconnect();
            }
        }, 2000);

        window.addEventListener('beforeunload', () => {
            clearInterval(interval);
            observer.disconnect();
        });
    })();
    """
}

// MARK: - Vue contrôleur pour WKWebView

@MainActor
final class WebLoginViewController: UIViewController {
    let webView: WKWebView
    private var progressView: UIProgressView!
    private var observation: NSKeyValueObservation?

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Annuler",
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )

        progressView = UIProgressView(progressViewStyle: .bar)
        progressView.progressTintColor = UIColor(named: "AccentColor") ?? .systemGreen
        progressView.trackTintColor = .clear
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        observation = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.progressView.progress = Float(webView.estimatedProgress)
                self.progressView.isHidden = webView.estimatedProgress >= 1.0
            }
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    deinit {
        observation?.invalidate()
    }
}
