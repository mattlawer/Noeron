//
//  QuickLookPreview.swift
//  Noeron
//
//  Cross-platform QuickLook viewer for evidence files. Uses QLPreviewController on
//  iOS/iPadOS and QLPreviewView on macOS.
//

import SwiftUI
import QuickLook

#if os(macOS)
import Quartz

struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    // Returns a plain container and hosts a QLPreviewView inside it, so we never
    // have to return QLPreviewView's failable initializer result directly.
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        if let preview = QLPreviewView(frame: .zero, style: .normal) {
            preview.autostarts = true
            preview.previewItem = url as NSURL
            preview.autoresizingMask = [.width, .height]
            preview.frame = container.bounds
            container.addSubview(preview)
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let preview = nsView.subviews.first as? QLPreviewView else { return }
        if (preview.previewItem as? NSURL) as URL? != url {
            preview.previewItem = url as NSURL
        }
    }
}
#else
// On iOS/iPadOS, QLPreviewController and its data-source protocols come from the
// `QuickLook` framework imported above. `QuickLookUI` is macOS-only.

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif
