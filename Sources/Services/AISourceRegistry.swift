import Foundation

/// Registry of known AI assistant and large-language-model web hosts.
/// Used by PasteboardObserver to tag paste events that originate from AI tools.
enum AISourceRegistry {

    private static let aiHosts: [String] = [
        "chat.openai.com",
        "chatgpt.com",
        "claude.ai",
        "anthropic.com",
        "gemini.google.com",
        "aistudio.google.com",
        "perplexity.ai",
        "copilot.microsoft.com",
        "poe.com",
        "you.com",
        "character.ai",
        "mistral.ai",
        "chat.mistral.ai",
        "huggingface.co",
        "bing.com",
        "qwen.ai",
        "deepseek.com",
        "kagi.com",
        "phind.com",
        "groq.com",
    ]

    /// Returns `true` when `url`'s host matches a known AI assistant domain.
    /// Comparison is case-insensitive and handles subdomains (e.g. "app.claude.ai").
    static func isAISource(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return aiHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
