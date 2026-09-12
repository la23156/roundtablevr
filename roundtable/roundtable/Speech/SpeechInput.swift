//
//  SpeechInput.swift
//  roundtable
//
//  Always-listening user speech via Deepgram live streaming STT.
//  Primary: Flux (wss://api.deepgram.com/v2/listen?model=flux-general-en,
//  TurnInfo events); fallback: nova-3 (wss://api.deepgram.com/v1/listen).
//  NOTE: Flux v2 only accepts CloseStream/ForceEndTurn/Configure text frames —
//  sending v1 KeepAlive makes the server error out and close the socket.
//  Echo-cancelled AVAudioEngine input is
//  converted to 16 kHz PCM16 and streamed over a websocket. Emits:
//    - onSpeechStart: Deepgram `SpeechStarted` VAD event (instant duck)
//    - onFinal: transcript once `speech_final` endpointing fires (~300 ms of
//      trailing silence — much faster than a local timer, and it works in the
//      simulator since nothing is on-device)
//

import AVFoundation
import Foundation

@MainActor
final class SpeechInput {
    var onSpeechStart: (() -> Void)?
    var onFinal: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?

    /// Accumulates `is_final` segments until `speech_final`/UtteranceEnd.
    private var utteranceParts: [String] = []
    private var speaking = false

    /// Cheap protocol debugging: print the first occurrence of each distinct
    /// server message type.
    private var seenMessageTypes: Set<String> = []
    /// Bytes of mic audio streamed to the socket (watchdog input).
    private var audioBytesSent = 0
    private var firstAudioSentAt: Date?

    func start() async {
        // Without record permission the engine input tap yields pure silence
        // (or the engine fails to start) — ask up front so failure is loud.
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            print("SpeechInput: microphone permission DENIED — voice interjection disabled. Enable in Settings > Privacy & Security > Microphone.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.mixWithOthers, .allowBluetoothHFP])
            try session.setActive(true)

            connectSocket(flux: true)

            // Deepgram v1 closes idle sockets; ping keeps it alive during long
            // stretches where the user just listens. IMPORTANT: nova-3 only —
            // Flux (v2) rejects KeepAlive ("unknown variant") and CLOSES the
            // socket. Flux only accepts CloseStream/ForceEndTurn/Configure,
            // and the continuous mic audio stream keeps it alive anyway.
            keepAliveTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(8))
                    guard let self, !self.usingFlux else { continue }
                    try? await self.socket?.send(.string(#"{"type":"KeepAlive"}"#))
                }
            }

            // Watchdog: if we have been streaming mic audio for >8 s and the
            // server has sent zero transcript-bearing messages, the protocol
            // is silently wrong — drop to nova-3.
            watchdogTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self else { return }
                    guard self.usingFlux, !self.receivedAnyResult,
                          let since = self.firstAudioSentAt,
                          Date().timeIntervalSince(since) > 8 else { continue }
                    print("SpeechInput: watchdog — \(self.audioBytesSent) audio bytes streamed with no transcript messages in 8 s; reconnecting with nova-3")
                    self.socket?.cancel(with: .goingAway, reason: nil)
                    self.connectSocket(flux: false)
                    return
                }
            }

            // Echo cancellation must be enabled before the engine starts.
            try engine.inputNode.setVoiceProcessingEnabled(true)
            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                                   channels: 1, interleaved: true),
                  let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                print("SpeechInput: audio format setup failed")
                return
            }

            engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
                let ratio = 16_000.0 / inputFormat.sampleRate
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
                guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
                var error: NSError?
                var fed = false
                converter.convert(to: converted, error: &error) { _, outStatus in
                    if fed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    fed = true
                    outStatus.pointee = .haveData
                    return buffer
                }
                guard error == nil, converted.frameLength > 0,
                      let channel = converted.int16ChannelData else { return }
                let data = Data(bytes: channel[0], count: Int(converted.frameLength) * 2)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.firstAudioSentAt == nil { self.firstAudioSentAt = Date() }
                    self.audioBytesSent += data.count
                    try? await self.socket?.send(.data(data))
                }
            }

            try engine.start()
            print("SpeechInput: Deepgram live STT connected (echo-cancelled)")
        } catch {
            print("SpeechInput unavailable: \(error). Interjection disabled this run.")
        }
    }

    private var usingFlux = false
    /// True once a transcript-bearing message (TurnInfo/Results) has arrived.
    /// Deliberately NOT set by the `Connected` handshake message — a socket
    /// that connects but never transcribes must still trigger the fallback.
    private var receivedAnyResult = false

    /// Flux is Deepgram's conversational model with built-in end-of-turn
    /// detection (~260 ms); nova-3 with endpointing is the fallback if the
    /// account/model isn't available.
    private func connectSocket(flux: Bool) {
        usingFlux = flux
        receivedAnyResult = false
        var components: URLComponents
        if flux {
            components = URLComponents(string: "wss://api.deepgram.com/v2/listen")!
            components.queryItems = [
                URLQueryItem(name: "model", value: "flux-general-en"),
                URLQueryItem(name: "encoding", value: "linear16"),
                URLQueryItem(name: "sample_rate", value: "16000"),
            ]
        } else {
            components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
            components.queryItems = [
                URLQueryItem(name: "model", value: "nova-3"),
                URLQueryItem(name: "language", value: "en"),
                URLQueryItem(name: "encoding", value: "linear16"),
                URLQueryItem(name: "sample_rate", value: "16000"),
                URLQueryItem(name: "channels", value: "1"),
                URLQueryItem(name: "interim_results", value: "true"),
                URLQueryItem(name: "vad_events", value: "true"),
                URLQueryItem(name: "endpointing", value: "300"),
                URLQueryItem(name: "utterance_end_ms", value: "1000"),
                URLQueryItem(name: "punctuate", value: "true"),
            ]
        }
        var request = URLRequest(url: components.url!)
        request.setValue("Token \(Secrets.deepgramKey)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        listen()
        print("SpeechInput: connected (\(flux ? "flux" : "nova-3"))")
    }

    private func listen() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while let socket = self?.socket, !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    if case .string(let text) = message {
                        await MainActor.run { self?.handle(json: text) }
                    }
                } catch {
                    guard !Task.isCancelled else { break }
                    print("SpeechInput socket ended: \(error)")
                    // Flux unavailable (e.g. 4xx on upgrade) -> nova-3 fallback.
                    await MainActor.run {
                        guard let self else { return }
                        if self.usingFlux, !self.receivedAnyResult {
                            self.connectSocket(flux: false)
                        }
                    }
                    break
                }
            }
        }
    }

    private func handle(json: String) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return }

        if seenMessageTypes.insert(type).inserted {
            print("SpeechInput: first \(type) message: \(json.prefix(200))")
        }

        switch type {
        case "Connected":
            break // handshake only — does not count as a transcript message

        case "Error":
            print("SpeechInput: server Error: \(json.prefix(300))")
            if usingFlux, !receivedAnyResult {
                socket?.cancel(with: .goingAway, reason: nil)
                connectSocket(flux: false)
            }

        case "TurnInfo":
            // Flux: model-integrated turn events.
            receivedAnyResult = true
            let event = object["event"] as? String ?? ""
            let transcript = (object["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch event {
            case "StartOfTurn":
                if !speaking {
                    speaking = true
                    onSpeechStart?()
                }
            case "EndOfTurn":
                utteranceParts = transcript.isEmpty ? utteranceParts : [transcript]
                finishUtterance()
            case "Update", "EagerEndOfTurn", "TurnResumed":
                if !transcript.isEmpty, !speaking {
                    speaking = true
                    onSpeechStart?()
                }
            default:
                break
            }

        case "SpeechStarted":
            if !speaking {
                speaking = true
                onSpeechStart?()
            }

        case "Results":
            receivedAnyResult = true
            guard let channel = object["channel"] as? [String: Any],
                  let alternatives = channel["alternatives"] as? [[String: Any]],
                  let transcript = alternatives.first?["transcript"] as? String else { return }
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            // Belt-and-suspenders speech onset (some accounts don't emit VAD events).
            if !trimmed.isEmpty, !speaking {
                speaking = true
                onSpeechStart?()
            }
            if object["is_final"] as? Bool == true, !trimmed.isEmpty {
                utteranceParts.append(trimmed)
            }
            if object["speech_final"] as? Bool == true {
                finishUtterance()
            }

        case "UtteranceEnd":
            finishUtterance()

        default:
            break
        }
    }

    private func finishUtterance() {
        let text = utteranceParts.joined(separator: " ")
        utteranceParts.removeAll()
        speaking = false
        if !text.isEmpty {
            onFinal?(text)
        }
    }

    func stop() {
        receiveTask?.cancel()
        keepAliveTask?.cancel()
        watchdogTask?.cancel()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }
}
