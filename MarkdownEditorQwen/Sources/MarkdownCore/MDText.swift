import Foundation

/// Text normalization that keeps the parsed string identical to the displayed string.
///
/// cmark normalizes line endings and expands tabs internally, which would shift the
/// source positions it reports. By normalizing up front, parse-time offsets always
/// line up with what the editor displays.
public enum MDText {

    /// Normalize line endings to `\n` and expand tabs to 4 spaces.
    public static func normalize(_ source: String) -> String {
        var result = source
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        result = result.replacingOccurrences(of: "\t", with: "    ")
        return result
    }
}
