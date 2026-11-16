import SwiftUI

/// A "Clear" button that empties a text field, used beside the Search,
/// Filter favorites and Rename fields on the Mac, and the Search field on
/// the iPhone.
///
/// Why a visible button rather than only the usual ways to empty a field
/// (Command-A then Delete, or the small round "x" some fields show)? Those
/// aren't obvious to everyone, the "x" is a tiny target, and a VoiceOver or
/// Voice Control user can find a button named "Clear" in one step
/// ("Click Clear" in Voice Control).
///
/// The button stays on screen and is dimmed while the field is empty,
/// instead of appearing and disappearing, so VoiceOver users always find it
/// in the same place.
struct ClearButton: View {
    /// The field's label, such as "Search for". VoiceOver's hint names it,
    /// so it's clear which field a Clear button empties.
    let fieldName: String
    /// The text to empty. `@Binding` means this view changes the caller's
    /// value directly, not a copy of it.
    @Binding var text: String
    /// Runs after clearing. The callers use it to put the cursor back in
    /// the field, ready to type something new.
    var afterClearing: () -> Void = {}

    var body: some View {
        Button("Clear") {
            text = ""
            afterClearing()
        }
        .disabled(text.isEmpty)
        // The name stays "Clear", matching what's shown, so Voice Control's
        // "Click Clear" works; the hint says which field it empties.
        .accessibilityHint("Empties the \(fieldName) field")
        #if os(iOS)
        // In an iPhone List row, a plain button would make the whole row
        // (field included) one big Clear button. Borderless keeps the tap
        // on the word "Clear" alone.
        .buttonStyle(.borderless)
        #endif
    }
}
