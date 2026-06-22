import Foundation

extension String {
    var containsEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation ||
            (scalar.properties.isEmoji && scalar.value > 0x238C)
        }
    }

    var isSingleEmoji: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1 else { return false }
        return trimmed.containsEmoji
    }

    func withoutEmoji() -> String {
        String(
            unicodeScalars.filter { scalar in
                !(scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C))
            }
        )
    }
}
