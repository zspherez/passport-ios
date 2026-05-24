import SwiftUI
import AVFoundation

/// Lightweight QR scanner. Hosted in a sheet from PassportView and from
/// RegisterView; both consume the scanned string the same way (parsed into
/// a `ScannedVenueQR` by `DeepLink.parseVenueQR`). The view fires `onScan`
/// at most once per session — the caller is expected to dismiss in response.
///
/// We use `AVCaptureMetadataOutput` rather than Vision/`VNDetectBarcodes`
/// because the entire payload is a tiny URL and the metadata pipeline has
/// the lower per-frame cost. Camera teardown happens synchronously the
/// moment a QR is read so the preview doesn't keep grinding behind the
/// dismissing sheet.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> ScannerHostController {
        ScannerHostController(coordinator: context.coordinator, onCancel: onCancel)
    }

    func updateUIViewController(_ controller: ScannerHostController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void
        private var fired = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !fired,
                  let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let payload = first.stringValue,
                  !payload.isEmpty else { return }
            fired = true
            DispatchQueue.main.async { [weak self] in
                self?.onScan(payload)
            }
        }
    }
}

/// UIViewController that owns the AVCaptureSession + preview layer. Lives
/// inside `QRScannerView` so SwiftUI doesn't have to know about UIKit
/// lifecycle directly.
final class ScannerHostController: UIViewController {
    private let coordinator: QRScannerView.Coordinator
    private let onCancel: () -> Void
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "qrscanner.session")

    init(coordinator: QRScannerView.Coordinator, onCancel: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
        addOverlay()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(coordinator, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        self.previewLayer = layer
    }

    /// Center-of-screen reticle + cancel button. Kept lightweight because
    /// adding a full SwiftUI overlay on top of the AVCapture layer just to
    /// draw two rectangles isn't worth the bridge complexity.
    private func addOverlay() {
        let reticle = UIView()
        reticle.translatesAutoresizingMaskIntoConstraints = false
        reticle.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        reticle.layer.borderWidth = 2
        reticle.layer.cornerRadius = 14
        view.addSubview(reticle)

        let hint = UILabel()
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.text = "Scan the venue's QR"
        hint.font = .preferredFont(forTextStyle: .headline)
        hint.textColor = .white
        hint.textAlignment = .center
        view.addSubview(hint)

        let cancel = UIButton(type: .system)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.setTitle("Cancel", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .preferredFont(forTextStyle: .body)
        cancel.addAction(UIAction { [weak self] _ in self?.onCancel() }, for: .touchUpInside)
        view.addSubview(cancel)

        NSLayoutConstraint.activate([
            reticle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            reticle.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            reticle.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.65),
            reticle.heightAnchor.constraint(equalTo: reticle.widthAnchor),

            hint.bottomAnchor.constraint(equalTo: reticle.topAnchor, constant: -20),
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            cancel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }
}
