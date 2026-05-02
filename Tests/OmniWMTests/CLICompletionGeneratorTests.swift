// SPDX-License-Identifier: GPL-2.0-only
import Testing

@testable import OmniWMCtl

@Suite struct CLICompletionGeneratorTests {
    @Test func zshScriptIncludesNestedManifestBackedSuggestions() throws {
        let script = CLICompletionGenerator.script(for: .zsh)
        let focusMonitorSuggestions = try commandSecondTokenSuggestions(in: script, for: "focus-monitor")
        let switchWorkspaceSuggestions = try commandSecondTokenSuggestions(in: script, for: "switch-workspace")

        #expect(script.contains("query_name"))
        #expect(script.contains("rule-actions"))
        #expect(script.contains("--fields"))
        #expect(script.contains("--display"))
        #expect(!script.contains("--monitor"))
        #expect(!script.contains("monitors"))
        #expect(script.contains("down left right up"))
        #expect(script.contains("default"))
        #expect(script.contains("niri"))
        #expect(script.contains("dwindle"))
        #expect(script.contains("grow"))
        #expect(script.contains("shrink"))
        #expect(script.contains("--focused --pid --window") || script.contains("--focused --window --pid"))
        #expect(script.contains("switch-workspace"))
        #expect(script.contains("previous"))
        #expect(script.contains("back"))
        #expect(focusMonitorSuggestions.contains("prev"))
        #expect(!focusMonitorSuggestions.contains("previous"))
        #expect(switchWorkspaceSuggestions.contains("prev"))
        #expect(switchWorkspaceSuggestions.contains("back-and-forth"))
        #expect(!switchWorkspaceSuggestions.contains("previous"))
        #expect(!switchWorkspaceSuggestions.contains("back"))
    }

    @Test func bashScriptIncludesRuleApplyQueryAndSubscriptionFlags() throws {
        let script = CLICompletionGenerator.script(for: .bash)
        let focusMonitorSuggestions = try commandSecondTokenSuggestions(in: script, for: "focus-monitor")
        let switchWorkspaceSuggestions = try commandSecondTokenSuggestions(in: script, for: "switch-workspace")

        #expect(script.contains("complete -F _omniwmctl omniwmctl"))
        #expect(script.contains("query_name"))
        #expect(script.contains("rule-actions"))
        #expect(script.contains("--display"))
        #expect(!script.contains("--monitor"))
        #expect(!script.contains("monitors"))
        #expect(script.contains("--pid"))
        #expect(script.contains("--window"))
        #expect(script.contains("--all"))
        #expect(script.contains("--no-send-initial"))
        #expect(script.contains("--exec"))
        #expect(script.contains("focused-monitor"))
        #expect(focusMonitorSuggestions.contains("prev"))
        #expect(!focusMonitorSuggestions.contains("previous"))
        #expect(switchWorkspaceSuggestions.contains("prev"))
        #expect(switchWorkspaceSuggestions.contains("back-and-forth"))
        #expect(!switchWorkspaceSuggestions.contains("previous"))
        #expect(!switchWorkspaceSuggestions.contains("back"))
    }

    @Test func fishScriptIncludesQueryFieldsAndCommandValueHints() {
        let script = CLICompletionGenerator.script(for: .fish)

        #expect(script.contains("__omniwmctl_prev_arg_is"))
        #expect(script.contains("rule-actions"))
        #expect(script.contains("--fields"))
        #expect(script.contains("pid"))
        #expect(script.contains("dwindle"))
        #expect(script.contains("grow"))
        #expect(script.contains("shrink"))
        #expect(script.contains("--display"))
        #expect(!script.contains("--monitor"))
        #expect(!script.contains("monitors"))
        #expect(script.contains("--window"))
        #expect(script.contains("--pid"))
        #expect(!script.contains("__fish_seen_subcommand_from focus-monitor' -a 'previous'"))
        #expect(!script.contains("__fish_seen_subcommand_from switch-workspace' -a 'previous'"))
        #expect(!script.contains("__fish_seen_subcommand_from switch-workspace' -a 'back'"))
    }
}

private enum CompletionTestError: Error {
    case missingCase(String)
    case missingSuggestions(String)
}

private func commandSecondTokenSuggestions(in script: String, for firstWord: String) throws -> Set<String> {
    let marker = "\"\(firstWord)\")"
    guard let markerRange = script.range(of: marker) else {
        throw CompletionTestError.missingCase(firstWord)
    }

    let suffix = script[markerRange.upperBound...]
    let suggestionsPrefix = "suggestions=\""
    guard let prefixRange = suffix.range(of: suggestionsPrefix) else {
        throw CompletionTestError.missingSuggestions(firstWord)
    }

    let suggestionsStart = prefixRange.upperBound
    guard let suggestionsEnd = suffix[suggestionsStart...].firstIndex(of: "\"") else {
        throw CompletionTestError.missingSuggestions(firstWord)
    }

    return Set(suffix[suggestionsStart..<suggestionsEnd].split(separator: " ").map(String.init))
}
