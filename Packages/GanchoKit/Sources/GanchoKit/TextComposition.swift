import Foundation

public enum TextCompositionError: Error, Equatable { case tooLarge }

/// Order is supplied by the caller, never inferred from a Set or storage order.
public enum TextComposition {
    public static func join(
        _ texts: [String], separator: String, maximumUTF8Bytes: Int? = nil
    ) throws -> String {
        if let limit = maximumUTF8Bytes {
            var remaining = max(0, limit)
            for (index, text) in texts.enumerated() {
                if index > 0 {
                    guard separator.utf8.count <= remaining else {
                        throw TextCompositionError.tooLarge
                    }
                    remaining -= separator.utf8.count
                }
                guard text.utf8.count <= remaining else { throw TextCompositionError.tooLarge }
                remaining -= text.utf8.count
            }
        }
        return texts.joined(separator: separator)
    }
}
