//
//  SparkVoiceInput.swift
//  SparkClient
//
//  Created by 話 on 2026/4/25.
//

import AVFoundation
import Combine
import Speech
import SwiftUI
import UIKit

struct SparkVoiceInputSheet: View {
    @Binding var text: String
    @Binding var isPresented: Bool
    var onPolish: (() async throws -> String)?

    @StateObject private var speechRecognizer = SparkSpeechRecognizer()
    @State private var isPolishing = false
    @State private var originalText = ""
    @State private var polishedText = ""
    @State private var actionError: String?

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $text)
                    .scrollContentBackgroundIfAvailable(.hidden)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)

                ScrollView(.horizontal) {
                    Text(speechRecognizer.recognizedText)
                        .lineLimit(1)
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .defaultScrollAnchorIfAvailable(.trailing)
            }
            .padding(.horizontal, 12)

            HStack(spacing: 16) {
                Button {
                    toggleRecording()
                } label: {
                    Image(systemName: speechRecognizer.isRecording ? "arrowtriangle.up.circle" : "microphone.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .foregroundColor(speechRecognizer.isRecording ? .red : .accentColor)
                        .padding(12)
                }
                .buttonStyle(.plain)
                .disabled(isPolishing)
                .accessibilityLabel(L10n.text("prompt_input.voice.record"))

                if speechRecognizer.isRecording {
                    SparkWaveformBarsView(level: speechRecognizer.audioLevel)
                        .frame(maxWidth: .infinity, minHeight: 42)
                } else {
                    Spacer()
                }

                if let onPolish, speechRecognizer.isRecording == false {
                    Button {
                        runPolish(onPolish)
                    } label: {
                        if isPolishing {
                            ProgressView()
                                .frame(width: 42, height: 42)
                                .padding(.vertical, 12)
                        } else {
                            Image(systemName: polishedText == text && text.isEmpty == false ? "arrow.uturn.backward.circle" : "hammer.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 42, height: 42)
                                .foregroundColor(.accentColor)
                                .padding(.vertical, 12)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isPolishing)
                    .accessibilityLabel(L10n.text("knowledge.toolbar.polish"))
                }

                Button {
                    appendRecognizedText()
                    isPresented = false
                } label: {
                    Image(systemName: "checkmark.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .foregroundColor(speechRecognizer.isRecording ? .gray : .accentColor)
                        .padding(12)
                }
                .buttonStyle(.plain)
                .disabled(isPolishing || speechRecognizer.isRecording)
                .accessibilityLabel(L10n.text("common.done"))
            }
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.accentColor.opacity(0.18), radius: 1)
            )
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .onAppear {
            speechRecognizer.requestAuthorization()
            speechRecognizer.startRecording()
        }
        .onDisappear {
            speechRecognizer.stopRecording()
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { actionError != nil || speechRecognizer.errorMessage != nil },
            set: {
                if $0 == false {
                    actionError = nil
                    speechRecognizer.errorMessage = nil
                }
            }
        )) {
            Button(L10n.text("common.ok")) {}
        } message: {
            Text(actionError ?? speechRecognizer.errorMessage ?? "")
        }
    }

    private func toggleRecording() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
            appendRecognizedText()
        } else {
            speechRecognizer.startRecording()
        }
    }

    private func appendRecognizedText() {
        let recognized = speechRecognizer.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard recognized.isEmpty == false else { return }
        text += text.isEmpty ? recognized : "\n" + recognized
        speechRecognizer.recognizedText = ""
    }

    private func runPolish(_ work: @escaping () async throws -> String) {
        if polishedText == text, originalText.isEmpty == false {
            text = originalText
            polishedText = ""
            return
        }
        originalText = text
        isPolishing = true
        Task {
            do {
                let result = try await work().trimmingCharacters(in: .whitespacesAndNewlines)
                if result.isEmpty == false {
                    text = result
                    polishedText = result
                }
            } catch {
                actionError = error.localizedDescription
            }
            isPolishing = false
        }
    }
}

@MainActor
private final class SparkSpeechRecognizer: NSObject, ObservableObject {
    @Published var recognizedText = ""
    @Published var isRecording = false
    @Published var audioLevel: Float = 0
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                if status != .authorized {
                    self.errorMessage = L10n.text("prompt_input.voice.permission_denied")
                }
            }
        }
    }

    func startRecording() {
        guard isRecording == false else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = L10n.text("prompt_input.voice.unavailable")
            return
        }

        stopRecording()
        recognizedText = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.averagePowerLevel(buffer: buffer)
                Task { @MainActor in
                    self?.audioLevel = level
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.recognizedText = result.bestTranscription.formattedString
                    }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        self.stopRecording()
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            stopRecording()
        }
    }

    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func averagePowerLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.1 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.1 }
        var sum: Float = 0
        for index in 0..<frameLength {
            sum += abs(channelData[index])
        }
        return min(1, max(0.08, sum / Float(frameLength) * 18))
    }
}




struct SparkWaveformBarsView: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<24, id: \.self) { index in
                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let wave = sin(Double(index) * 0.7 + Date().timeIntervalSinceReferenceDate * 7)
        let normalized = max(0.08, CGFloat(level) + CGFloat(wave) * 0.12)
        return min(42, max(8, normalized * 48))
    }
}
