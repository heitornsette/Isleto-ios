import SwiftUI

/// Colors of the Isleto mascot (assets/icon on the desktop) and of the desktop island.
extension Color {
    /// Sprout green of the mascot (#3AA76D): buttons and accents.
    static let isletoAccent = Color(hex: "#3AA76D")
    /// Body green of the mascot (#79D9A6).
    static let isletoMint = Color(hex: "#79D9A6")
    /// Focus phase color on the desktop (#FF6B5E).
    static let isletoFocus = Color(hex: "#FF6B5E")
    static let isletoWater = Color(hex: "#40A6FF")
    static let isletoHabit = Color(hex: "#3AA76D")

    /// "#RRGGBB" (or "RRGGBB"). Invalid text gives the accent green.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let value = digits.count == 6 ? UInt32(digits, radix: 16) : nil
        let rgb = value ?? 0x3AA76D
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

/// Choices of the habit form.
enum HabitPalette {
    /// 21 colors, 7 per row.
    static let colors: [String] = [
        "#F87171", "#FB923C", "#FBBF24", "#FACC15", "#A3E635", "#4ADE80", "#34D399",
        "#2DD4BF", "#22D3EE", "#38BDF8", "#60A5FA", "#818CF8", "#A78BFA", "#C084FC",
        "#E879F9", "#F472B6", "#FB7185", "#94A3B8", "#A1A1AA", "#A8A29E", "#3AA76D",
    ]

    /// SF Symbols that fit habits.
    static let icons: [String] = [
        "checkmark", "figure.run", "figure.walk", "dumbbell.fill", "bicycle", "figure.yoga",
        "drop.fill", "cup.and.saucer.fill", "fork.knife", "carrot.fill", "pills.fill", "heart.fill",
        "bed.double.fill", "moon.stars.fill", "sun.max.fill", "brain.head.profile", "book.fill", "pencil",
        "graduationcap.fill", "laptopcomputer", "music.note", "paintbrush.fill", "camera.fill", "leaf.fill",
        "tree.fill", "pawprint.fill", "house.fill", "cart.fill", "creditcard.fill", "banknote.fill",
        "phone.fill", "message.fill", "person.2.fill", "hands.sparkles.fill", "shower.fill", "bolt.fill",
        "smoke.fill", "wineglass.fill", "gamecontroller.fill", "iphone.slash",
    ]
}
