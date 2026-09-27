import AVFoundation
import Combine
import Speech
import SwiftUI
import UIKit

struct SparkPromptInputDrawerSheet: View {
    @Binding var text: String
    @Binding var isPresented: Bool
    var onAutoFill: (() async throws -> String)?
    var onPolish: (() async throws -> String)?
    var onTranslate: (() async throws -> String)?
    var onOCRImage: ((UIImage) async throws -> String)?

    @FocusState private var textFocused: Bool
    @State private var isAutoFilling = false
    @State private var isPolishing = false
    @State private var isTranslating = false
    @State private var isOCRRecognizing = false
    @State private var originalText = ""
    @State private var processedText = ""
    @State private var actionError: String?
    @State private var showOCRSourceOptions = false
    @State private var showCameraPicker = false
    @State private var showPhotoLibraryPicker = false
    @State private var showCameraUnavailableAlert = false
    @State private var showLinkInputRow = false
    @State private var linkText = ""

    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 36

    private var tokenEstimate: Int {
        SparkPromptTokenEstimator.estimate(text)
    }

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $text)
                .focused($textFocused)
                .scrollContentBackgroundIfAvailable(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomToolbar
        }
        .padding(12)
        .background(Color(.systemGray6))
        .onAppear { textFocused = true }
        .sheet(isPresented: $showCameraPicker) {
            SystemImagePicker(
                source: .camera,
                onCancel: { showCameraPicker = false },
                onImagePicked: { image in
                    showCameraPicker = false
                    runOCR(image)
                }
            )
            .background(Color.black)
        }
        .sheet(isPresented: $showPhotoLibraryPicker) {
            SystemImagePicker(
                source: .photoLibrary,
                onCancel: { showPhotoLibraryPicker = false },
                onImagePicked: { image in
                    showPhotoLibraryPicker = false
                    runOCR(image)
                }
            )
            .ignoresSafeArea()
        }
        .alert(L10n.text("prompt_input.ocr.camera_unavailable"), isPresented: $showCameraUnavailableAlert) {
            Button(L10n.text("common.ok")) {}
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { actionError != nil },
            set: { if $0 == false { actionError = nil } }
        )) {
            Button(L10n.text("common.ok")) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var bottomToolbar: some View {
        VStack(spacing: 10) {
            if showLinkInputRow {
                linkInputRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(alignment: .center, spacing: 8) {
                if onAutoFill != nil {
                    processingButton(
                        systemImage: processedText == text && text.isEmpty == false ? "arrow.uturn.backward.circle" : "wand.and.sparkles",
                        isBusy: isAutoFilling,
                        action: runAutoFill
                    )
                    .accessibilityLabel(L10n.text("prompt_input.toolbar.autofill"))
                }

                if onPolish != nil {
                    processingButton(
                        systemImage: processedText == text && text.isEmpty == false ? "arrow.uturn.backward.circle" : "hammer.circle",
                        isBusy: isPolishing,
                        action: runPolish
                    )
                    .accessibilityLabel(L10n.text("knowledge.toolbar.polish"))
                }

                if onTranslate != nil {
                    processingButton(
                        systemImage: processedText == text && text.isEmpty == false ? "arrow.uturn.backward.circle" : "globe",
                        isBusy: isTranslating,
                        action: runTranslate
                    )
                    .accessibilityLabel(L10n.text("knowledge.toolbar.translate"))
                }

                if onOCRImage != nil {
                    processingButton(
                        systemImage: "viewfinder.circle",
                        isBusy: isOCRRecognizing,
                        action: toggleOCRSources
                    )
                    .accessibilityLabel(L10n.text("knowledge.toolbar.ocr"))
                }

                toolbarButton(systemImage: "link.circle", action: toggleLinkRow)
                    .accessibilityLabel(L10n.text("prompt_input.toolbar.add_link"))

                toolbarButton(systemImage: "trash.circle", action: clearText)
                    .accessibilityLabel(L10n.text("knowledge.toolbar.clear"))

                toolbarButton(systemImage: "chevron.down.circle") {
                    isPresented = false
                }
                .accessibilityLabel(L10n.text("common.close"))

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(L10n.format("knowledge.toolbar.chars", text.count))
                    Text(L10n.format("knowledge.toolbar.tokens_approx", tokenEstimate))
                }
                .font(.caption)
                .foregroundColor(.gray)
                .accessibilityElement(children: .combine)
            }
            

            if showOCRSourceOptions {
                ocrSourceSelector
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.accentColor.opacity(0.18), radius: 1)
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: showOCRSourceOptions)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: showLinkInputRow)
    }

    private var ocrSourceSelector: some View {
        HStack(spacing: 6) {
            sourceButton(
                systemImage: "camera.circle",
                title: L10n.text("prompt_input.ocr.camera"),
                action: presentCamera
            )

            sourceButton(
                systemImage: "photo.circle",
                title: L10n.text("prompt_input.ocr.photo_library"),
                action: { showPhotoLibraryPicker = true }
            )
        }
    }

    private var linkInputRow: some View {
        HStack(spacing: 8) {
            TextField(L10n.text("prompt_input.toolbar.link_placeholder"), text: $linkText)
                .textInputAutocapitalizationIfAvailable(.never)
                .autocorrectionDisabledIfAvailable()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)

            Button {
                appendLink()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(L10n.text("prompt_input.toolbar.add_link"))
        }
    }

    private func sourceButton(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func processingButton(systemImage: String, isBusy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isBusy {
                ProgressView()
                    .frame(width: buttonSize, height: buttonSize)
            } else {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: buttonSize, height: buttonSize)
                    .foregroundColor(Color(.systemGray))
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusyActionRunning)
    }

    private func toolbarButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .resizable()
                .scaledToFit()
                .frame(width: buttonSize, height: buttonSize)
                .foregroundColor(Color(.systemGray))
        }
        .buttonStyle(.plain)
        .disabled(isBusyActionRunning)
    }

    private var isBusyActionRunning: Bool {
        isAutoFilling || isPolishing || isTranslating || isOCRRecognizing
    }

    private enum ProcessingAction {
        case autoFill
        case polish
        case translate
    }

    private func runAutoFill() {
        guard let onAutoFill else { return }
        runTextAction(.autoFill, work: onAutoFill)
    }

    private func runPolish() {
        guard let onPolish else { return }
        runTextAction(.polish, work: onPolish)
    }

    private func runTranslate() {
        guard let onTranslate else { return }
        runTextAction(.translate, work: onTranslate)
    }

    private func runTextAction(_ action: ProcessingAction, work: @escaping () async throws -> String) {
        if processedText == text, originalText.isEmpty == false {
            text = originalText
            processedText = ""
            return
        }
        originalText = text
        setBusy(true, for: action)
        Task {
            do {
                let raw = try await work()
                let result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.isEmpty == false {
                    text = result
                    processedText = result
                }
            } catch {
                actionError = error.localizedDescription
            }
            setBusy(false, for: action)
        }
    }

    private func setBusy(_ busy: Bool, for action: ProcessingAction) {
        switch action {
        case .autoFill:
            isAutoFilling = busy
        case .polish:
            isPolishing = busy
        case .translate:
            isTranslating = busy
        }
    }

    private func toggleOCRSources() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            showOCRSourceOptions.toggle()
            if showOCRSourceOptions {
                showLinkInputRow = false
            }
        }
    }

    private func toggleLinkRow() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            showLinkInputRow.toggle()
            if showLinkInputRow {
                showOCRSourceOptions = false
            }
        }
    }

    private func presentCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCameraPicker = true
        } else {
            showCameraUnavailableAlert = true
        }
    }

    private func runOCR(_ image: UIImage) {
        guard let onOCRImage else { return }
        isOCRRecognizing = true
        showOCRSourceOptions = false
        Task {
            do {
                let raw = try await onOCRImage(image)
                let result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.isEmpty == false {
                    appendBlock(result)
                }
            } catch {
                actionError = error.localizedDescription
            }
            isOCRRecognizing = false
        }
    }

    private func appendLink() {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        appendBlock(trimmed)
        linkText = ""
        showLinkInputRow = false
    }

    private func appendBlock(_ value: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = value
        } else {
            text += "\n" + value
        }
        processedText = ""
    }

    private func clearText() {
        text = ""
        processedText = ""
        originalText = ""
    }
}

private enum SparkPromptTokenEstimator {
    static func estimate(_ text: String) -> Int {
        let wordCount = text.split { $0.isWhitespace || $0.isPunctuation }.count
        return max(1, Int(ceil(Double(wordCount) * 1.2)))
    }
}
