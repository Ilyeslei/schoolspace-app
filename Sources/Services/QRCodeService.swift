//
//  QRCodeService.swift
//  SchoolSpaceApp
//
//  Scanner et décodage des QR codes d'établissement
//

import Foundation
import AVFoundation
import CryptoKit
import SwiftUI

@MainActor
final class QRCodeService: Sendable {
    nonisolated(unsafe) static let shared = QRCodeService()

    private init() {}

    // MARK: - Scan QR Code (utilise UIViewControllerRepresentable côté View)

    func decodeQRCode(_ rawString: String, pin: String) throws -> DecodedQRCode {
        guard let data = rawString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let encryptedJeton = json["jeton"],
              let encryptedLogin = json["login"],
              let url = json["url"] else {
            throw SchoolSpaceError.invalidQRCode
        }

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

    private func deriveKey(from pin: String) -> SymmetricKey {
        let salt = "SchoolSpaceQRCodeSalt".data(using: .utf8)!
        let pinData = pin.data(using: .utf8)!

        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: pinData),
            salt: salt,
            info: Data(),
            outputByteCount: 32
        )
        return key
    }

    private func decrypt(_ encryptedBase64: String, key: SymmetricKey) throws -> String {
        guard let encryptedData = Data(base64Encoded: encryptedBase64) else {
            throw SchoolSpaceError.qrCodeDecryptionFailed
        }

        guard encryptedData.count >= 12 + 16 else {
            throw SchoolSpaceError.qrCodeDecryptionFailed
        }

        let nonce = try AES.GCM.Nonce(data: encryptedData.prefix(12))
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

// MARK: - Vue scanner SwiftUI (remplace le contrôleur UIKit)

struct QRScannerView: UIViewControllerRepresentable {
    let completion: (Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let scanner = QRScannerViewController()
        scanner.completion = completion
        return scanner
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

@MainActor
final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
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
            Task { @MainActor in
                self.captureSession?.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Task { @MainActor in
            if self.captureSession?.isRunning == true {
                self.captureSession.stopRunning()
            }
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

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

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

final class QRCodeOverlayView: UIView {
    private let cornerLength: CGFloat = 30
    private let cornerThickness: CGFloat = 4
    private let scanRectSize: CGFloat = 240

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

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

        let accentColor = UIColor(named: "AccentColor") ?? UIColor.systemGreen
        context.setStrokeColor(accentColor.cgColor)
        context.setLineWidth(cornerThickness)
        context.setLineCap(.round)

        let corners = [
            (scanRect.minX, scanRect.minY),
            (scanRect.maxX, scanRect.minY),
            (scanRect.minX, scanRect.maxY),
            (scanRect.maxX, scanRect.maxY)
        ]

        for (x, y) in corners {
            let isRight = x == scanRect.maxX
            let isBottom = y == scanRect.maxY

            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: y))

            if !isRight && !isBottom {
                path.addLine(to: CGPoint(x: x + cornerLength, y: y))
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y + cornerLength))
            } else if isRight && !isBottom {
                path.addLine(to: CGPoint(x: x - cornerLength, y: y))
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y + cornerLength))
            } else if !isRight && isBottom {
                path.addLine(to: CGPoint(x: x + cornerLength, y: y))
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y - cornerLength))
            } else {
                path.addLine(to: CGPoint(x: x - cornerLength, y: y))
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y - cornerLength))
            }

            path.stroke()
        }

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
