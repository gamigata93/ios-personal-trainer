import Foundation

/// Removes personal names from device source names.
public enum SourceLabel {
    private static let devices = ["Apple Watch", "iPhone", "iPad"]
    private static let possessives = ["'s ", "’s "]

    /// "<Name>'s Apple Watch" becomes "Apple Watch" (also iPhone and iPad, with a
    /// straight or curly apostrophe). Any other name, such as a third-party app,
    /// is returned unchanged.
    public static func normalize(_ name: String) -> String {
        for device in devices {
            for possessive in possessives {
                let suffix = possessive + device
                if name.hasSuffix(suffix), name.count > suffix.count {
                    return device
                }
            }
        }
        return name
    }
}
