// SPDX-License-Identifier: GPL-3.0-or-later
@preconcurrency import AVFoundation
import AppKit

/// A small floating, mirrored camera preview ("check how you look before a
/// call"). The camera runs only while the window is open; closing it stops
/// the session and the green light goes off. Nothing is recorded.
@MainActor
final class CameraMirror {
    private var panel: NSPanel?
    private var session: AVCaptureSession?
    var onError: ((String) -> Void)?

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { if isOpen { close() } else { Task { await open() } } }

    func open() async {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            onError?("Allow Stitchy in Privacy & Security › Camera.")
            return
        }
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else {
            onError?("No camera found.")
            return
        }
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else { onError?("The camera is busy."); return }
        session.addInput(input)
        self.session = session

        let size: CGFloat = 220
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        let view = MirrorView(frame: NSRect(x: 0, y: 0, width: size, height: size), session: session) { [weak self] in self?.close() }
        p.contentView = view
        if !p.setFrameUsingName("StitchyCameraMirror"), let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - size - 24, y: screen.visibleFrame.maxY - size - 24))
        }
        p.setFrameAutosaveName("StitchyCameraMirror")
        panel = p
        p.orderFrontRegardless()
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    func close() {
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s?.stopRunning() }
        session = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Round, mirrored preview with a close button on hover.
private final class MirrorView: NSView {
    private let close = NSButton()
    private let onClose: () -> Void

    init(frame: NSRect, session: AVCaptureSession, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = frame.width / 2
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = bounds
        preview.videoGravity = .resizeAspectFill
        preview.connection?.automaticallyAdjustsVideoMirroring = false
        preview.connection?.isVideoMirrored = true
        layer?.addSublayer(preview)

        close.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close camera mirror")
        close.isBordered = false
        close.contentTintColor = .white
        close.frame = NSRect(x: frame.width / 2 - 12, y: 12, width: 24, height: 24)
        close.target = self
        close.action = #selector(closeTapped)
        close.isHidden = true
        addSubview(close)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func closeTapped() { onClose() }
    override func mouseEntered(with event: NSEvent) { close.isHidden = false }
    override func mouseExited(with event: NSEvent) { close.isHidden = true }
}
