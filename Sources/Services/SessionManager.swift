//
//  SessionManager.swift
//  SchoolSpaceApp
//
//  Gestion de la session utilisateur : connexion, reconnexion automatique, déconnexion
//  Utilise WKWebView pour la page de connexion, détection automatique de succès
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
        // Tentative de restauration de session au lancement
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
            currentSession = session
        } else if session.isExpired {
            logger.info("Session expirée, tentative de renouvellement")
            await tryRefreshSession(session)
        } else {
            logger.info("Session invalide, suppression")
            logout()
        }
    }

    // MARK: - Connexion via WKWebView

    /// Ouvre la page de connexion dans un navigateur intégré
    /// Retourne l'URL de la page de connexion mobile
    func login(at url: String) async throws -> URL {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Construire l'URL de connexion mobile si ce n'est pas déjà fait
        let loginURL: URL
        if url.contains("mobile.") || url.contains("eleve.html") || url.contains("parent.html") {
            loginURL = URL(string: url)!
        } else {
            let baseURL = url.hasSuffix("/") ? url : url + "/"
            loginURL = URL(string: baseURL + "mobile.eleve.html")!
        }

        logger.info("Ouverture page de connexion : \(loginURL.absoluteString)")

        // Le WebLoginViewController gère la WKWebView et la détection de connexion
        let success = try await WebLoginCoordinator.shared.startLogin(at: loginURL)

        if success {
            logger.info("Connexion réussie détectée")
            // La session a été créée dans le coordinator
            if let session = currentSession {
                return loginURL
            }
        }

        throw SchoolSpaceError.loginFailed
    }

    // MARK: - Renouvellement de session

    private func tryRefreshSession(_ session: UserSession) async {
        // TODO: Implémenter le renouvellement via refresh token si supporté
        // Pour l'instant, on demande à l'utilisateur de se reconnecter
        logger.warning("Renouvellement de session non implémenté, reconnexion requise")
        logout()
        showErrorMessage("Votre session a expiré. Veuillez vous reconnecter.")
    }

    // MARK: - Création session après login réussi

    /// Appelé par WebLoginCoordinator quand la connexion est détectée
    func createSession(userId: String, displayName: String, establishmentId: String, establishmentUrl: String, sessionToken: String) {
        // Durée de session : 30 jours (à ajuster selon la durée réelle du cookie)
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

    /// Lance le flux de connexion dans une WKWebView modale
    func startLogin(at url: URL) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            presentWebView(with: url)
        }
    }

    private func presentWebView(with url: URL) {
        // Configuration WKWebView
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        // Injection de script pour détecter la connexion
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

        // Charger l'URL
        webView?.load(URLRequest(url: url))

        // Présenter en plein écran
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.debug("Page chargée : \(webView.url?.absoluteString ?? "inconnu")")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.error("Erreur chargement : \(error.localizedDescription)")
        finishLogin(success: false, error: SchoolSpaceError.networkError(error))
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "loginObserver",
              let body = message.body as? [String: Any],
              let event = body["event"] as? String else { return }

        switch event {
        case "loginSuccess":
            if let userId = body["userId"] as? String,
               let displayName = body["displayName"] as? String,
               let establishmentId = body["establishmentId"] as? String,
               let sessionToken = body["sessionToken"] as? String {

                let establishmentUrl = webView.url?.absoluteString ?? ""
                sessionManager.createSession(
                    userId: userId,
                    displayName: displayName,
                    establishmentId: establishmentId,
                    establishmentUrl: establishmentUrl,
                    sessionToken: sessionToken
                )
                finishLogin(success: true)
            }

        case "loginError":
            if let errorMsg = body["message"] as? String {
                logger.warning("Erreur login détectée : \(errorMsg)")
            }

        default:
            break
        }
    }

    private func finishLogin(success: Bool, error: Error? = nil) {
        hostViewController?.dismiss(animated: true) {
            self.webView = nil
            self.hostViewController = nil

            if success {
                self.continuation?.resume(returning: true)
            } else {
                self.continuation?.resume(throwing: error ?? SchoolSpaceError.loginFailed)
            }
            self.continuation = nil
        }
    }

    // MARK: - Script d'injection pour détecter la connexion

    /// Ce script surveille la page pour détecter quand l'utilisateur est connecté
    /// Il faut l'adapter selon la structure exacte de la page mobile.eleve.html
    private let loginDetectionScript = """
    (function() {
        'use strict';

        function sendEvent(event, data) {
            window.webkit.messageHandlers.loginObserver.postMessage({
                event: event,
                ...data
            });
        }

        // Détection de connexion réussie
        function checkLoginState() {
            // Recherche d'indices de connexion dans la page
            // Ces sélecteurs sont à adapter selon le DOM réel de mobile.eleve.html

            // 1. Chercher le nom de l'utilisateur dans l'en-tête
            const userNameEl = document.querySelector('.user-name, .header .name, [data-user-name], .welcome-message');
            if (userNameEl && userNameEl.textContent.trim()) {
                // Chercher aussi l'ID établissement
                const estabEl = document.querySelector('[data-establishment-id], .establishment-name');
                const establishmentId = estabEl?.dataset?.establishmentId || estabEl?.textContent?.trim() || 'unknown';

                // Récupérer le cookie de session
                const cookies = document.cookie;
                const sessionMatch = cookies.match(/sessionid=([^;]+)/i) || cookies.match(/PHPSESSID=([^;]+)/i) || cookies.match(/JSESSIONID=([^;]+)/i);
                const sessionToken = sessionMatch ? sessionMatch[1] : cookies;

                sendEvent('loginSuccess', {
                    userId: 'current_user', // À extraire si possible
                    displayName: userNameEl.textContent.trim(),
                    establishmentId: establishmentId,
                    sessionToken: sessionToken
                });
                return true;
            }

            // 2. Vérifier la présence d'éléments post-connexion
            const postLoginElements = document.querySelectorAll('.main-content, .dashboard, .notes-container, .emploi-temps, .cahier-textes');
            if (postLoginElements.length > 0) {
                // Utilisateur probablement connecté
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

        // Vérification initiale
        if (checkLoginState()) return;

        // Observer les mutations du DOM (connexion dynamique)
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

        // Aussi vérifier périodiquement (fallback)
        const interval = setInterval(() => {
            if (checkLoginState()) {
                clearInterval(interval);
                observer.disconnect();
            }
        }, 2000);

        // Nettoyage au déchargement
        window.addEventListener('beforeunload', () => {
            clearInterval(interval);
            observer.disconnect();
        });
    })();
    """
}

// MARK: - Vue contrôleur pour WKWebView

class WebLoginViewController: UIViewController {
    let webView: WKWebView
    private var progressView: UIProgressView!

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // Barre de navigation minimaliste
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Annuler",
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )

        // Barre de progression
        progressView = UIProgressView(progressViewStyle: .bar)
        progressView.progressTintColor = UIColor(named: "AccentColor") ?? .systemGreen
        progressView.trackTintColor = .clear
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)

        // WebView
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

        // Observer la progression
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            progressView.progress = Float(webView.estimatedProgress)
            progressView.isHidden = webView.estimatedProgress >= 1.0
        }
    }

    @objc private func cancelTapped() {
        // Le coordinator gère l'annulation
        dismiss(animated: true)
    }

    deinit {
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
    }
}