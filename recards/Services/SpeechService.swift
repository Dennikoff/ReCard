import Foundation
import AVFoundation

/// Произношение слов системным синтезатором.
///
/// Работает оффлайн и не требует хранения аудиофайлов. Воспроизведение происходит
/// только по нажатию кнопки: автопроизношения в приложении нет.
@MainActor
final class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    /// Произносит текст голосом, соответствующим языку колоды.
    ///
    /// Читать английское слово немецким голосом недопустимо, поэтому язык передаётся явно.
    func speak(_ text: String, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Повторное нажатие прерывает предыдущее произношение, а не встаёт в очередь.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        configureAudioSession()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = LanguageCatalog.preferredVoice(for: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Категория `playback` позволяет звучать в бесшумном режиме: пользователь нажал
    /// кнопку звука осознанно и ожидает услышать слово.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
    }
}
