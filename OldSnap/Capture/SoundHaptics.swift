import AVFoundation
import UIKit

/// Era-correct shutter feedback: synthesized mechanically-flavored tones per
/// camera family plus haptics. Uses the `.ambient` audio session category so
/// everything respects the silent switch. (Real recorded foley can replace
/// the synth by dropping files into Resources and mapping them here.)
final class SoundHaptics {
    static let shared = SoundHaptics()

    private var players: [String: AVAudioPlayer] = [:]
    private let impact = UIImpactFeedbackGenerator(style: .rigid)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    /// Shutter moment for a camera: sound + haptic.
    func shutter(for camera: CameraID) {
        switch camera {
        case .dc2000:
            play(tone: .digicamBeep)
            softImpact.impactOccurred()
        case .sq70:
            play(tone: .instantWhir)
            impact.impactOccurred()
        default:
            play(tone: .filmThunk)
            impact.impactOccurred(intensity: 1.0)
        }
    }

    /// Film-advance wind-on after capture (35mm cameras).
    func windOn() {
        softImpact.impactOccurred(intensity: 0.7)
    }

    // MARK: - Synthesized tones

    private enum Tone: String {
        case filmThunk, instantWhir, digicamBeep
    }

    private func play(tone: Tone) {
        if let player = players[tone.rawValue] {
            player.currentTime = 0
            player.play()
            return
        }
        guard let data = Self.synthesize(tone: tone),
              let player = try? AVAudioPlayer(data: data) else { return }
        player.volume = 0.5
        players[tone.rawValue] = player
        player.play()
    }

    /// Builds a short WAV in memory. Deliberately simple envelopes tuned to
    /// read as "mechanism", not "notification".
    private static func synthesize(tone: Tone) -> Data? {
        let sampleRate = 22050.0
        let duration: Double
        var samples: [Float]

        func noise(_ i: Int) -> Float {
            // Deterministic pseudo-noise in [-1, 1], no RNG dependency.
            let v = (sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1.0)
            return Float(v)
        }

        switch tone {
        case .filmThunk:
            // Low knock + brief ratchet tail.
            duration = 0.16
            let count = Int(sampleRate * duration)
            samples = (0..<count).map { i in
                let t = Double(i) / sampleRate
                let knock = sin(2 * .pi * 110 * t) * exp(-t * 40)
                let ratchet = Double(noise(i)) * 0.3 * exp(-t * 18) * (t > 0.05 ? 1 : 0)
                return Float(knock * 0.8 + ratchet)
            }
        case .instantWhir:
            // Motor whir sweeping down, ~0.5 s.
            duration = 0.5
            let count = Int(sampleRate * duration)
            samples = (0..<count).map { i in
                let t = Double(i) / sampleRate
                let f = 190.0 - 60 * t
                let motor = sin(2 * .pi * f * t) * 0.4
                let buzz = sin(2 * .pi * f * 7 * t) * 0.12
                let env = min(t * 12, 1) * exp(-max(t - 0.38, 0) * 25)
                return Float((motor + buzz) * env)
            }
        case .digicamBeep:
            // Two-step electronic beep.
            duration = 0.22
            let count = Int(sampleRate * duration)
            samples = (0..<count).map { i in
                let t = Double(i) / sampleRate
                let f = t < 0.1 ? 1560.0 : 2080.0
                let gate = (t < 0.09 || (t > 0.11 && t < 0.2)) ? 1.0 : 0.0
                return Float(sin(2 * .pi * f * t) * 0.35 * gate)
            }
        }

        return wavData(samples: samples, sampleRate: Int(sampleRate))
    }

    private static func wavData(samples: [Float], sampleRate: Int) -> Data {
        var pcm = Data()
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * 32767)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(16); append16(1); append16(1)
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append16(2); append16(16)
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}
