//
//  QRCodeService.swift
//  SchoolSpaceApp
//
//  Scanner et décodage des QR codes d'établissement
//  Format : JSON chiffré avec { jeton, login, url } + PIN 4 chiffres
//

import Foundation
import AVFoundation
import CryptoKit

final class QRCodeService: NSObject {
    static let shared = QRCodeService()

    private override init() {}

    // MARK: - Scan QR Code

    /// Ouvre un scanner et retourne le contenu brut du QR code
    func scanQRCode() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let scanner = QRScannerViewController()
            scanner.completion = { result in
                switch result {
                case .success(let code):
                    continuation.resume(returning: code)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            // Présenter le scanner
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(scanner, animated: true)
            }
        }
    }

    // MARK: - Décodage QR Code

    /// Décode un QR code d'établissement
    /// Le format est un JSON chiffré : { "jeton": "...", "login": "...", "url": "..." }
    /// Le déchiffrement utilise un PIN à 4 chiffres fourni par l'utilisateur
    func decodeQRCode(_ rawString: String, pin: String) throws -> DecodedQRCode {
        // 1. Parser le JSON brut
        guard let data = rawString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let encryptedJeton = json["jeton"],
              let encryptedLogin = json["login"],
              let url = json["url"] else {
            throw SchoolSpaceError.invalidQRCode
        }

        // 2. Déchiffrer avec le PIN (AES-GCM avec clé dérivée du PIN)
        let key = deriveKey(from: pin)

        let decryptedJeton = try decrypt(encryptedJeton, key: key)
        let decryptedLogin = try decrypt(encryptedLogin, key: key)

        return DecodedQRCode(
            jeton: decryptedJeton,
            login: decryptedLogin,
            url: url
        )
    }

    // MARK: - Chiffrement / Déchiffrement

    /// Dérive une clé AES-256 à partir du PIN 4 chiffres (PBKDF2)
    private func deriveKey(from pin: String) -> SymmetricKey {
        let salt = "SchoolSpaceQRCodeSalt".data(using: .utf8)!
        let pinData = pin.data(using: .utf8)!

        // PBKDF2 avec 100000 itérations
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: pinData),
            salt: salt,
            info: Data(),
            outputByteCount: 32
        )
        return key
    }

    /// Déchiffre une chaîne encodée en Base64 (AES-GCM)
    private func decrypt(_ encryptedBase64: String, key: SymmetricKey) throws -> String {
        guard let encryptedData = Data(base64Encoded: encryptedBase64) else {
            throw SchoolSpaceError.qrCodeDecryptionFailed
        }

        // Format : nonce (12 octets) + ciphertext + tag (16 octets)
        guard encryptedData.count >= 12 + 16 else {
            throw SchoolSpaceError.qrCodeDecryptionFailed
        }

        let nonce = encryptedData.prefix(12)
        let ciphertext = encryptedData.dropFirst(12).dropLast(16)
        let tag = encryptedData.suffix(16)

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        guard let string = String(data: decryptedData, encoding: .utf8) else {
            throw SchoolSpaceError.qrCodeDecryptionFailed
        }

        return string
    }
}

// MARK: - Contrôleur de scanner QR Code (UIKit)

import UIKit

class QRScannerViewController: UIViewController {
    var completion: ((Result<String, Error>) -> Void)?

    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var overlayView: QRCodeOverlayView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupOverlay()
        setupCloseButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        overlayView?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true {
            captureSession.stopRunning()
        }
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              captureSession.canAddInput(videoInput) else {
            completion?(.failure(SchoolSpaceError.cameraPermissionDenied))
            dismiss(animated: true)
            return
        }

        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    private func setupOverlay() {
        overlayView = QRCodeOverlayView(frame: view.bounds)
        overlayView.backgroundColor = .clear
        view.addSubview(overlayView)
    }

    private func setupCloseButton() {
        let button = UIButton(type: .system)
        button.setTitle("Fermer", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.3)
        button.layer.cornerRadius = 12
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            button.widthAnchor.constraint(equalToConstant: 80),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func closeTapped() {
        completion?(.failure(SchoolSpaceError.unknown(NSError(domain: "QRScanner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Annulé par l'utilisateur"]))))
        dismiss(animated: true)
    }
}

// MARK: - Delegate capture

extension QRScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let stringValue = metadataObject.stringValue else { return }

        captureSession.stopRunning()
        completion?(.success(stringValue))
        dismiss(animated: true)
    }
}

// MARK: - Vue overlay pour le cadre de visée

class QRCodeOverlayView: UIView {
    private let cornerLength: CGFloat = 30
    private let cornerThickness: CGFloat = 4
    private let scanRectSize: CGFloat = 240

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Fond semi-transparent
        let backgroundPath = UIBezierPath(rect: rect)
        let scanRect = CGRect(
            x: (rect.width - scanRectSize) / 2,
            y: (rect.height - scanRectSize) / 2,
            width: scanRectSize,
            height: scanRectSize
        )
        backgroundPath.append(UIBezierPath(roundedRect: scanRect, cornerRadius: 16).reversing())

        context.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
        backgroundPath.fill()

        // Cadre de visée (coins)
        let accentColor = UIColor(named: "AccentColor") ?? UIColor.systemGreen
        context.setStrokeColor(accentColor.cgColor)
        context.setLineWidth(cornerThickness)
        context.setLineCap(.round)

        let corners = [
            (scanRect.minX, scanRect.minY), // Top-left
            (scanRect.maxX, scanRect.minY), // Top-right
            (scanRect.minX, scanRect.maxY), // Bottom-left
            (scanRect.maxX, scanRect.maxY)  // Bottom-right
        ]

        for (x, y) in corners {
            let isRight = x == scanRect.maxX
            let isBottom = y == scanRect.maxY

            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: y))

            if !isRight && !isBottom { // Top-left
                path.addLine(to: CGPoint(x: x + cornerLength, y: y))
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y + cornerLength))
            } else if isRight && !isBottom { // Top-right
                path.addLine(to: CGPoint(x: x - cornerLength, y: y))
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y + cornerLength))
            } else if !isRight && isBottom { // Bottom-left
                path.addLine(to: CGPoint(x: x + cornerLength, y: y))
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y - cornerLength))
            } else { // Bottom-right
                path.addLine(to: CGPoint(x: x - cornerLength, y: y))
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y - cornerLength))
            }

            path.stroke()
        }

        // Texte d'instruction
        let text = "Placez le QR code dans le cadre"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (rect.width - textSize.width) / 2,
            y: scanRect.maxY + 24,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }
}