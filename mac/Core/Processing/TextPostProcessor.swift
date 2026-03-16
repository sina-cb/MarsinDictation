import Foundation

public class TextPostProcessor {
    public static func process(_ rawText: String) -> String {
        var text = rawText
        
        // Strip filler words
        let fillers = [
            "\\bum\\b", "\\buh\\b", "\\bmhm\\b", "\\buh-huh\\b", "\\bmm-hmm\\b"
        ]
        
        for filler in fillers {
            if let regex = try? NSRegularExpression(pattern: filler, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: text.utf16.count)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            }
        }
        
        // Clean double spaces
        text = text.replacingOccurrences(of: "  ", with: " ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Fix weird punctuations
        text = text.replacingOccurrences(of: " ,", with: ",")
        text = text.replacingOccurrences(of: " .", with: ".")
        
        return text
    }
}
