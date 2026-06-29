import Foundation

/// Aggregated token counts parsed from local Claude Code JSONL logs.
struct TokenSummary {
    var input: Int = 0
    var output: Int = 0
    var cacheCreation: Int = 0
    var cacheRead: Int = 0

    var total: Int { input + output + cacheCreation + cacheRead }

    static func + (lhs: TokenSummary, rhs: TokenSummary) -> TokenSummary {
        TokenSummary(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheCreation: lhs.cacheCreation + rhs.cacheCreation,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }
}
