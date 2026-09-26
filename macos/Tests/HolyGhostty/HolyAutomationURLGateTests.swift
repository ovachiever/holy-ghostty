import AppKit
import Foundation
import Testing
@testable import Ghostty

/// One hostile shape per case. `underFullPolicy` states what the gate does
/// once the user has allowed both spawn URLs and commands: a `.refused` shape
/// never yields a launch spec at all; a `.confirmSpawn` shape still creates
/// nothing until the sheet's non-default button is clicked. Under the shipped
/// default every shape is refused before it is even parsed (mn-e9f9a9).
struct HolyAutomationHostileShape: Sendable, CustomTestStringConvertible {
    enum Outcome: Sendable {
        case refused
        case confirmSpawn
    }

    let name: String
    let url: String
    let underFullPolicy: Outcome

    var testDescription: String { name }

    static let all: [HolyAutomationHostileShape] = [
        .init(name: "double quotes in command",
              url: "holy-ghostty://spawn?command=%22touch%20/tmp/x%22%3B%20id", underFullPolicy: .confirmSpawn),
        .init(name: "single quotes in command",
              url: "holy-ghostty://spawn?command=echo%20%27%3B%20touch%20/tmp/x%3B%20%27", underFullPolicy: .confirmSpawn),
        .init(name: "newline in command",
              url: "holy-ghostty://spawn?command=echo%0Atouch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "carriage return in command",
              url: "holy-ghostty://spawn?command=echo%0Dtouch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "NUL in command",
              url: "holy-ghostty://spawn?command=touch%00/tmp/x", underFullPolicy: .refused),
        .init(name: "escape sequence in command",
              url: "holy-ghostty://spawn?command=touch%20/tmp/x%1B%5B2J", underFullPolicy: .refused),
        .init(name: "tab in command",
              url: "holy-ghostty://spawn?command=touch%09/tmp/x", underFullPolicy: .refused),
        .init(name: "DEL in command",
              url: "holy-ghostty://spawn?command=touch%20/tmp/x%7F", underFullPolicy: .refused),
        .init(name: "newline in initialInput",
              url: "holy-ghostty://spawn?initialInput=rm%20-rf%20~%0A", underFullPolicy: .refused),
        .init(name: "newline in title",
              url: "holy-ghostty://spawn?title=hi%0Atouch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "newline in workingDirectory",
              url: "holy-ghostty://spawn?workingDirectory=/tmp%0A", underFullPolicy: .refused),
        .init(name: "bidi override in title",
              url: "holy-ghostty://spawn?title=%E2%80%AEsafe&command=touch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "file URL as workingDirectory",
              url: "holy-ghostty://spawn?workingDirectory=file:///tmp&command=touch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "file URL as command",
              url: "holy-ghostty://spawn?command=file:///etc/passwd", underFullPolicy: .confirmSpawn),
        .init(name: "javascript URL as command",
              url: "holy-ghostty://spawn?command=javascript:alert(1)", underFullPolicy: .confirmSpawn),
        .init(name: "javascript URL as initialInput",
              url: "holy-ghostty://spawn?initialInput=javascript:fetch(%27http://x%27)", underFullPolicy: .confirmSpawn),
        .init(name: "double percent-encoding",
              url: "holy-ghostty://spawn?command=touch%2520/tmp/x", underFullPolicy: .confirmSpawn),
        .init(name: "percent-encoded parameter name",
              url: "holy-ghostty://spawn?%63ommand=touch%20/tmp/x", underFullPolicy: .confirmSpawn),
        .init(name: "invalid UTF-8 escape",
              url: "holy-ghostty://spawn?command=%FF", underFullPolicy: .refused),
        .init(name: "truncated percent escape",
              url: "holy-ghostty://spawn?command=touch%20/tmp/x%0", underFullPolicy: .confirmSpawn),
        .init(name: "plus-encoded spaces",
              url: "holy-ghostty://spawn?command=touch+/tmp/x", underFullPolicy: .confirmSpawn),
        .init(name: "duplicate command parameter",
              url: "holy-ghostty://spawn?command=ls&command=touch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "unknown parameter",
              url: "holy-ghostty://spawn?exec=touch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "userinfo smuggling",
              url: "holy-ghostty://user:pw@spawn?command=touch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "port smuggling",
              url: "holy-ghostty://spawn:22?command=touch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "fragment smuggling",
              url: "holy-ghostty://spawn?command=touch%20/tmp/x#x", underFullPolicy: .refused),
        .init(name: "extra path after route",
              url: "holy-ghostty://spawn/extra?command=touch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "ssh option injection via host",
              url: "holy-ghostty://spawn?host=-oProxyCommand%3Dtouch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "space in host",
              url: "holy-ghostty://spawn?host=studio%20-oProxyCommand%3Dtouch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "tmux socket path traversal",
              url: "holy-ghostty://spawn?tmuxSocket=../../../tmp/x&tmuxSession=a", underFullPolicy: .refused),
        .init(name: "unknown runtime",
              url: "holy-ghostty://spawn?runtime=bash&command=touch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "ssh transport without host",
              url: "holy-ghostty://spawn?transport=ssh", underFullPolicy: .refused),
        .init(name: "relative workingDirectory",
              url: "holy-ghostty://spawn?workingDirectory=..%2F..%2Fetc", underFullPolicy: .refused),
        .init(name: "command and bootstrapCommand together",
              url: "holy-ghostty://spawn?command=ls&bootstrapCommand=touch%20/tmp/x", underFullPolicy: .refused),
        .init(name: "uppercase scheme and route",
              url: "HOLY-GHOSTTY://SPAWN?command=touch%20/tmp/x", underFullPolicy: .confirmSpawn),
    ]
}

struct HolyAutomationURLGateTests {
    private typealias Policy = HolyAutomationURLGate.Policy

    private let fullPolicy = Policy(allowSpawnURL: true, allowSpawnURLCommands: true)
    private let spawnOnlyPolicy = Policy(allowSpawnURL: true, allowSpawnURLCommands: false)
    private let hostile = "holy-ghostty://spawn?command=touch%20/tmp/pwned&runtime=shell"

    private func url(_ text: String) throws -> URL {
        try #require(URL(string: text), "\(text) is not a URL")
    }

    // MARK: - The shipped default

    @Test func shippedDefaultRefusesASpawnWithACommand() throws {
        #expect(HolyAutomationURLGate.decide(try url(hostile), policy: .shippedDefault)
                == .refused(.spawnURLsDisabled))
    }

    @Test func shippedDefaultRefusesABareSpawnWithoutACommand() throws {
        #expect(HolyAutomationURLGate.decide(try url("holy-ghostty://spawn?runtime=shell"), policy: .shippedDefault)
                == .refused(.spawnURLsDisabled))
        #expect(HolyAutomationURLGate.decide(try url("holy-ghostty://spawn"), policy: .shippedDefault)
                == .refused(.spawnURLsDisabled))
    }

    @Test(arguments: HolyAutomationHostileShape.all)
    func shippedDefaultRefusesEveryHostileShapeBeforeParsing(shape: HolyAutomationHostileShape) throws {
        #expect(HolyAutomationURLGate.decide(try url(shape.url), policy: .shippedDefault)
                == .refused(.spawnURLsDisabled))
    }

    @Test func policyReadsFalseFromMissingDefaultsAndTrueOnlyWhenWritten() throws {
        let defaults = try #require(UserDefaults(suiteName: "holy.automation.tests.\(UUID().uuidString)"))
        #expect(Policy.fromUserDefaults(defaults) == .shippedDefault)
        defaults.set(true, forKey: Policy.DefaultsKey.allowSpawnURL)
        #expect(Policy.fromUserDefaults(defaults) == spawnOnlyPolicy)
        defaults.set(true, forKey: Policy.DefaultsKey.allowSpawnURLCommands)
        #expect(Policy.fromUserDefaults(defaults) == fullPolicy)
        defaults.set("yes", forKey: Policy.DefaultsKey.allowSpawnURL)
        #expect(Policy.fromUserDefaults(defaults).allowSpawnURL)
        defaults.set("maybe", forKey: Policy.DefaultsKey.allowSpawnURL)
        #expect(!Policy.fromUserDefaults(defaults).allowSpawnURL)
    }

    // MARK: - Commands need their own opt-in

    @Test(arguments: ["command", "bootstrapCommand", "initialInput"])
    func spawnAllowedWithoutCommandsRefusesEachCommandBearingField(field: String) throws {
        let decision = HolyAutomationURLGate.decide(
            try url("holy-ghostty://spawn?runtime=shell&\(field)=touch%20/tmp/x"),
            policy: spawnOnlyPolicy
        )
        #expect(decision == .refused(.commandsDisabled(fields: [field])))
    }

    @Test func spawnAllowedWithoutCommandsAsksForABareRuntimeOpen() throws {
        let decision = HolyAutomationURLGate.decide(
            try url("holy-ghostty://spawn?runtime=claude&workingDirectory=/tmp&tmuxSession=lane"),
            policy: spawnOnlyPolicy
        )
        guard case let .confirmSpawn(request) = decision else {
            Issue.record("expected a confirmation, got \(decision)")
            return
        }
        #expect(request.commandFields.isEmpty)
        #expect(!request.carriesCommand)
        #expect(request.launchSpec.runtime == .claude)
        #expect(request.launchSpec.workingDirectory == "/tmp")
        #expect(request.launchSpec.tmux?.sessionName == "lane")
        #expect(request.launchSpec.command == nil)
        #expect(request.launchSpec.initialInput == nil)
    }

    @Test func fullPolicyStillOnlyAsks() throws {
        let decision = HolyAutomationURLGate.decide(try url(hostile), policy: fullPolicy)
        guard case let .confirmSpawn(request) = decision else {
            Issue.record("expected a confirmation, got \(decision)")
            return
        }
        #expect(request.commandFields == ["command"])
        #expect(request.carriesCommand)
        #expect(request.launchSpec.command == "touch /tmp/pwned")
        #expect(request.launchSpec.runtime == .shell)
        #expect(request.url.absoluteString == hostile)
        #expect(request.auditDetail.contains("with command"))
    }

    /// The exact query scripts/holy-spawn-session.sh emits (urlencode with
    /// quote_via=quote), so Erik's automations keep working after opt-in.
    @Test func scriptShapedURLIsAdmittedForConfirmationWithEveryFieldIntact() throws {
        let decision = HolyAutomationURLGate.decide(
            try url("holy-ghostty://spawn?title=studio%2Ftemp&runtime=claude&transport=ssh&host=erik%40studio"
                    + "&tmuxSession=temp&tmuxSocket=holy&workingDirectory=%7E/Custom-Coding/holy-ghostty"
                    + "&bootstrapCommand=agent-do%20coord%20touch&initialInput=hello&createIfMissing=true"),
            policy: fullPolicy
        )
        guard case let .confirmSpawn(request) = decision else {
            Issue.record("expected a confirmation, got \(decision)")
            return
        }
        let spec = request.launchSpec
        #expect(spec.title == "studio/temp")
        #expect(spec.runtime == .claude)
        #expect(spec.transport.kind == .ssh)
        #expect(spec.transport.sshDestination == "erik@studio")
        #expect(spec.tmux == HolySessionTmuxSpec(socketName: "holy", sessionName: "temp", createIfMissing: true))
        #expect(spec.workingDirectory == "~/Custom-Coding/holy-ghostty")
        #expect(spec.command == "agent-do coord touch")
        #expect(spec.initialInput == "hello")
        #expect(request.commandFields == ["bootstrapCommand", "initialInput"])
    }

    // MARK: - Hostile shapes never yield a spec without the click

    @Test(arguments: HolyAutomationHostileShape.all)
    func hostileShapeUnderFullPolicyIsRefusedOrOnlyAsks(shape: HolyAutomationHostileShape) throws {
        let decision = HolyAutomationURLGate.decide(try url(shape.url), policy: fullPolicy)
        switch (shape.underFullPolicy, decision) {
        case (.refused, .refused(.malformed(_))):
            break
        case let (.confirmSpawn, .confirmSpawn(request)):
            #expect(request.carriesCommand, "every confirm-shaped case carries a command")
        default:
            Issue.record("\(shape.name): expected \(shape.underFullPolicy), got \(decision)")
        }
    }

    @Test func refusalReasonsNameTheExactOptIn() {
        #expect(HolyAutomationURLGate.Refusal.spawnURLsDisabled.reason
                    .contains(HolyAutomationURLGate.Policy.DefaultsKey.allowSpawnURL))
        #expect(HolyAutomationURLGate.Refusal.commandsDisabled(fields: ["command"]).reason
                    .contains(HolyAutomationURLGate.Policy.DefaultsKey.allowSpawnURLCommands))
        #expect(HolyAutomationURLGate.Refusal.commandsDisabled(fields: ["initialInput"]).reason
                    .contains("initialInput"))
        #expect(HolyAutomationURLGate.Refusal.malformed("x").reason == "malformed spawn URL: x")
    }

    @Test func refusalTextForAControlCharacterNamesItWithoutRepeatingIt() throws {
        let decision = HolyAutomationURLGate.decide(
            try url("holy-ghostty://spawn?command=echo%0Atouch%20/tmp/x"), policy: fullPolicy
        )
        guard case let .refused(.malformed(problem)) = decision else {
            Issue.record("expected a malformed refusal, got \(decision)")
            return
        }
        #expect(problem == "control character U+A in command")
        #expect(!problem.contains("\n"))
        #expect(HolyAutomationURLGate.printable("a\nb\u{202E}") == "\"a\\u{A}b\\u{202E}\"")
    }

    // MARK: - The other routes

    @Test(arguments: [HolyAutomationURLGate.Policy.shippedDefault,
                      HolyAutomationURLGate.Policy(allowSpawnURL: true, allowSpawnURLCommands: false),
                      HolyAutomationURLGate.Policy(allowSpawnURL: true, allowSpawnURLCommands: true)])
    func boardRouteIsUntouchedByThePolicy(policy: HolyAutomationURLGate.Policy) throws {
        let board = try url("holy-ghostty://board?item=mn-abcdef")
        #expect(HolyAutomationURLGate.decide(board, policy: policy) == .board(itemID: "mn-abcdef"))
        #expect(HolyAutomationURLParser.boardItemID(from: board) == "mn-abcdef")
        #expect(HolyAutomationURLParser.launchSpec(from: board) == nil)
    }

    @Test(arguments: ["holy-ghostty://nothing?command=x", "holy-ghostty://?command=x",
                      "https://spawn?command=x", "holy-ghostty://board?item=mn-abcdef&item=mn-123456"])
    func routesTheAppDoesNotServeAreReportedNotRefused(text: String) throws {
        #expect(HolyAutomationURLGate.decide(try url(text), policy: fullPolicy) == .unsupported)
    }

    // MARK: - Audit line and sheet

    @Test func auditLineCarriesTheVerdictTheDetailAndTheFullURL() throws {
        let target = try url(hostile)
        let entry = HolyAutomationURLAuditEntry(
            verdict: .refused, detail: HolyAutomationURLGate.Refusal.spawnURLsDisabled.reason, url: target
        )
        #expect(entry.line.hasPrefix("holy-ghostty automation URL refused ("))
        #expect(entry.line.hasSuffix("): \(hostile)"))
        #expect(entry.line.contains(HolyAutomationURLGate.Policy.DefaultsKey.allowSpawnURL))
    }

    @Test @MainActor func confirmationSheetDefaultsToCancelAndNamesEverything() throws {
        let decision = HolyAutomationURLGate.decide(
            try url("holy-ghostty://spawn?runtime=codex&host=studio&transport=ssh&tmuxSession=lane"
                    + "&workingDirectory=/srv/repo&title=Lane&command=make%20test&initialInput=go"),
            policy: fullPolicy
        )
        guard case let .confirmSpawn(request) = decision else {
            Issue.record("expected a confirmation, got \(decision)")
            return
        }
        let origin = HolyAutomationURLOrigin(processIdentifier: 4242, applicationName: "Safari", bundleIdentifier: "com.apple.Safari")
        let alert = HolyAutomationSpawnConfirmation.makeAlert(for: request, origin: origin)

        #expect(alert.buttons.count == 2)
        #expect(alert.buttons[0].title == HolyAutomationSpawnConfirmation.cancelTitle)
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[1].title == HolyAutomationSpawnConfirmation.createTitle)
        #expect(alert.buttons[1].keyEquivalent == "")
        #expect(alert.buttons[1].hasDestructiveAction)
        #expect(HolyAutomationSpawnConfirmation.createResponse == .alertSecondButtonReturn)
        #expect(alert.messageText == "Run a command from a link?")

        let text = alert.informativeText
        for needle in ["Safari (pid 4242)", "Codex", "SSH to studio", "session lane", "/srv/repo",
                       "Lane", "make test", "go", request.url.absoluteString, "Nothing has run yet."] {
            #expect(text.contains(needle), "sheet text lacks \(needle)")
        }
    }

    @Test @MainActor func bareRuntimeSheetIsNotMarkedDestructive() throws {
        let decision = HolyAutomationURLGate.decide(try url("holy-ghostty://spawn?runtime=shell"), policy: fullPolicy)
        guard case let .confirmSpawn(request) = decision else {
            Issue.record("expected a confirmation, got \(decision)")
            return
        }
        let alert = HolyAutomationSpawnConfirmation.makeAlert(for: request, origin: nil)
        #expect(alert.messageText == "Open a session from a link?")
        #expect(!alert.buttons[1].hasDestructiveAction)
        #expect(alert.informativeText.contains("Requested by: not reported by macOS"))
        #expect(alert.informativeText.contains("Command: none"))
    }

    @Test func appleEventWithoutASenderYieldsNoOrigin() {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        #expect(HolyAutomationURLOrigin.from(appleEvent: event) == nil)
        #expect(HolyAutomationURLOrigin.from(appleEvent: nil) == nil)
    }
}

// MARK: - Non-command fields are inert at both sinks (mn-e6e3d0)

/// One shell metacharacter class, spliced around a benign base value.
struct HolyAutomationMetacharacterClass: Sendable, CustomTestStringConvertible {
    let name: String
    let prefix: String
    let suffix: String

    var testDescription: String { name }

    func applied(to base: String) -> String { prefix + base + suffix }

    static let all: [HolyAutomationMetacharacterClass] = [
        .init(name: "semicolon", prefix: "", suffix: "; touch /tmp/holy-e6e3d0"),
        .init(name: "ampersand", prefix: "", suffix: " & touch /tmp/holy-e6e3d0"),
        .init(name: "and-list", prefix: "", suffix: "&&touch /tmp/holy-e6e3d0"),
        .init(name: "pipe", prefix: "", suffix: "|tee /tmp/holy-e6e3d0"),
        .init(name: "command substitution", prefix: "", suffix: "$(touch /tmp/holy-e6e3d0)"),
        .init(name: "backticks", prefix: "", suffix: "`touch /tmp/holy-e6e3d0`"),
        .init(name: "parameter expansion", prefix: "", suffix: "${HOME}$USER"),
        .init(name: "arithmetic expansion", prefix: "", suffix: "$((1+1))"),
        .init(name: "output redirection", prefix: "", suffix: ">/tmp/holy-e6e3d0"),
        .init(name: "input redirection", prefix: "", suffix: "</etc/passwd"),
        .init(name: "subshell", prefix: "", suffix: "(touch /tmp/holy-e6e3d0)"),
        .init(name: "brace group", prefix: "", suffix: "{touch,/tmp/holy-e6e3d0}"),
        .init(name: "glob", prefix: "", suffix: "*?[a-z]"),
        .init(name: "history bang", prefix: "", suffix: "!!"),
        .init(name: "comment", prefix: "", suffix: " #rest"),
        .init(name: "tmux format", prefix: "", suffix: "#{session_name}#(touch /tmp/holy-e6e3d0)"),
        .init(name: "single quote", prefix: "", suffix: "'; touch /tmp/holy-e6e3d0; '"),
        .init(name: "double quote", prefix: "", suffix: "\"; touch /tmp/holy-e6e3d0; \""),
        .init(name: "backslash", prefix: "", suffix: "\\'\\\"\\"),
        .init(name: "space", prefix: "", suffix: " -x y"),
        .init(name: "tilde", prefix: "", suffix: "~root"),
        .init(name: "tmux target colon", prefix: "", suffix: ":0"),
        .init(name: "tmux target dot", prefix: "", suffix: ".1"),
        .init(name: "tmux id sigils", prefix: "", suffix: "$0@1%2"),
        .init(name: "tmux exact-match prefix", prefix: "=", suffix: ""),
        .init(name: "leading dash", prefix: "-o", suffix: ""),
        .init(name: "trailing semicolon", prefix: "", suffix: ";"),
        .init(name: "escaped trailing semicolon", prefix: "", suffix: "\\;"),
        .init(name: "equals percent at", prefix: "", suffix: "=%41@x"),
        .init(name: "path separator", prefix: "", suffix: "/../x"),
        .init(name: "non-ASCII letter", prefix: "", suffix: "\u{E9}"),
    ]
}

/// Every non-command field of the spawn route, with the benign value each
/// case starts from and the rule the gate must apply to it.
enum HolyAutomationNonCommandField: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case tmuxSession, tmuxSocket, workingDirectory, title, objective, host

    var testDescription: String { rawValue }

    var benign: String {
        switch self {
        case .tmuxSession: "lane"
        case .tmuxSocket: "holytest"
        case .workingDirectory: "/tmp/benign"
        case .title: "Benign"
        case .objective: "benign"
        case .host: "studio"
        }
    }

    /// `host` only means something over SSH.
    var transports: [HolySessionTransportKind] {
        self == .host ? [.ssh] : [.local, .ssh]
    }

    /// Stated independently of the gate's own code: what it must admit.
    func gateMustAdmit(_ value: String) -> Bool {
        func matches(_ pattern: String) -> Bool {
            value.range(of: pattern, options: .regularExpression) != nil
        }
        switch self {
        case .tmuxSession:
            return matches("^[A-Za-z0-9_-]+$")
        case .tmuxSocket:
            return matches("^[A-Za-z0-9._-]+$") && !matches("^\\.+$")
        case .workingDirectory:
            return (value.hasPrefix("/") || value.hasPrefix("~")) && !value.hasSuffix(";")
        case .title, .objective:
            return true
        case .host:
            return HolySSHTransportManager.isValidDestination(value)
        }
    }
}

/// A lexer for the POSIX/zsh subset the builders emit. It separates what a
/// shell would treat as syntax from what it would treat as literal data:
/// the `skeleton` keeps every active character and collapses each run of
/// inert quoted text to one `◊`, so two scripts that differ only inside
/// quotes have equal skeletons. It also decodes words and groups them into
/// simple commands, so the test can descend into the strings a shell hands
/// to another shell: `sh|zsh|bash -c|-lc <script>`, tmux `new-session`'s
/// pane command, and ssh's remote command.
struct HolyShellLexer {
    private(set) var skeleton = ""
    private(set) var words: [String] = []
    private(set) var commands: [[String]] = []

    private let scalars: [Unicode.Scalar]
    private var index = 0
    private var inertRun = false
    private var word: String?
    private var argv: [String] = []
    private var redirectTarget = false

    init(_ script: String) {
        scalars = Array(script.unicodeScalars)
        lexNormal(insideSubstitution: false)
        boundary()
    }

    private var current: Unicode.Scalar? { index < scalars.count ? scalars[index] : nil }
    private var next: Unicode.Scalar? { index + 1 < scalars.count ? scalars[index + 1] : nil }

    private mutating func active(_ text: String) {
        skeleton += text
        inertRun = false
    }

    private mutating func inert() {
        if !inertRun { skeleton += "◊" }
        inertRun = true
    }

    private mutating func append(_ scalar: Unicode.Scalar) {
        word = (word ?? "") + String(Character(scalar))
    }

    private mutating func endWord() {
        guard let finished = word else { return }
        words.append(finished)
        if redirectTarget {
            redirectTarget = false
        } else {
            argv.append(finished)
        }
        word = nil
    }

    private mutating func boundary() {
        endWord()
        if !argv.isEmpty { commands.append(argv) }
        argv = []
        redirectTarget = false
    }

    /// `$( ... )` restarts quoting inside, wherever it appears.
    private mutating func substitution() {
        active("$(")
        index += 2
        let saved = (word, argv, redirectTarget)
        word = nil
        argv = []
        redirectTarget = false
        lexNormal(insideSubstitution: true)
        boundary()
        (word, argv, redirectTarget) = saved
        active(")")
        word = (word ?? "") + "$(…)"
    }

    private mutating func lexNormal(insideSubstitution: Bool) {
        var depth = 0
        while let scalar = current {
            switch scalar {
            case " ", "\t":
                active(String(scalar)); endWord(); index += 1
            case "\n":
                active("\n"); boundary(); index += 1
            case "'":
                inert()
                word = word ?? ""
                index += 1
                while let quoted = current, quoted != "'" {
                    append(quoted); index += 1
                }
                index += 1
            case "\"":
                lexDouble()
            case "\\":
                active("\\")
                index += 1
                if let escaped = current {
                    inert(); append(escaped); index += 1
                }
            case "$" where next == "(":
                substitution()
            case ";", "&", "|":
                active(String(scalar)); boundary(); index += 1
            case "(":
                active("("); boundary(); index += 1
                if insideSubstitution { depth += 1 }
            case ")":
                if insideSubstitution, depth == 0 {
                    index += 1
                    return
                }
                active(")"); boundary(); index += 1
                if insideSubstitution { depth -= 1 }
            case "<", ">":
                active(String(scalar))
                if let pending = word, !pending.isEmpty,
                   pending.unicodeScalars.allSatisfy({ ("0" ... "9").contains($0) }) {
                    word = nil
                } else {
                    endWord()
                }
                redirectTarget = true
                index += 1
            default:
                active(String(scalar)); append(scalar); index += 1
            }
        }
    }

    private mutating func lexDouble() {
        inert()
        word = word ?? ""
        index += 1
        while let scalar = current, scalar != "\"" {
            switch scalar {
            case "\\":
                active("\\")
                index += 1
                if let escaped = current {
                    inert(); append(escaped); index += 1
                }
            case "$" where next == "(":
                substitution()
            case "$", "`":
                active(String(scalar)); append(scalar); index += 1
            default:
                inert(); append(scalar); index += 1
            }
        }
        inert()
        index += 1
    }

    /// Strings in this layer that a shell will parse again.
    var nestedScripts: [String] {
        var scripts: [String] = []
        for command in commands {
            let names = command.map { ($0 as NSString).lastPathComponent }
            for position in command.indices.dropFirst().dropLast()
            where ["-c", "-lc"].contains(command[position])
                && ["sh", "zsh", "bash"].contains(names[position - 1]) {
                scripts.append(command[position + 1])
            }
            if names.contains("tmux"), command.contains("new-session"), let last = command.last {
                scripts.append(last)
            }
            if let ssh = names.firstIndex(of: "ssh"),
               let separator = command[ssh...].firstIndex(of: "--"),
               separator + 2 < command.count {
                scripts.append(command[(separator + 2)...].joined(separator: " "))
            }
        }
        return scripts
    }
}

struct HolyAutomationNonCommandFieldSinkTests {
    private let fullPolicy = HolyAutomationURLGate.Policy(allowSpawnURL: true, allowSpawnURLCommands: true)

    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// A spawn URL with every non-command field set to its benign value,
    /// except `field`, which carries `value`. Everything outside RFC 3986's
    /// unreserved set is percent-encoded, `+` included.
    private func spawnURL(
        field: HolyAutomationNonCommandField,
        value: String,
        transport: HolySessionTransportKind
    ) throws -> URL {
        var fields: [(String, String)] = [
            ("runtime", "shell"),
            ("transport", transport.rawValue),
            ("createIfMissing", "true"),
        ]
        for other in HolyAutomationNonCommandField.allCases where other != .host || transport == .ssh {
            fields.append((other.rawValue, other == field ? value : other.benign))
        }
        let query = fields.map { name, raw in
            "\(name)=\(raw.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? "")"
        }.joined(separator: "&")
        return try #require(URL(string: "holy-ghostty://spawn?\(query)"))
    }

    private func admittedSpec(_ url: URL) -> HolySessionLaunchSpec? {
        guard case let .confirmSpawn(request) = HolyAutomationURLGate.decide(url, policy: fullPolicy) else {
            return nil
        }
        return request.launchSpec
    }

    /// Descends every shell layer of `hostile` and `benign` in step and
    /// names the first layer whose skeleton differs, or whose nested script
    /// count differs; nil means the hostile value never became syntax at any
    /// depth. `words` collects every word the hostile side decoded.
    static func structuralDifference(
        _ hostile: String,
        _ benign: String,
        layer: String,
        words: inout [String]
    ) -> String? {
        let hostileLayer = HolyShellLexer(hostile)
        let benignLayer = HolyShellLexer(benign)
        words += hostileLayer.words
        if hostileLayer.skeleton != benignLayer.skeleton {
            return "shell structure changed at \(layer)"
        }
        let hostileScripts = hostileLayer.nestedScripts
        let benignScripts = benignLayer.nestedScripts
        if hostileScripts.count != benignScripts.count {
            return "nested script count changed at \(layer)"
        }
        for (offset, pair) in zip(hostileScripts, benignScripts).enumerated() {
            if let difference = structuralDifference(pair.0, pair.1, layer: "\(layer) > \(offset)", words: &words) {
                return difference
            }
        }
        return nil
    }

    @Test(arguments: HolyAutomationNonCommandField.allCases, HolyAutomationMetacharacterClass.all)
    @MainActor
    func metacharacterInANonCommandFieldIsRefusedOrOnlyQuoted(
        field: HolyAutomationNonCommandField,
        metacharacter: HolyAutomationMetacharacterClass
    ) throws {
        let value = metacharacter.applied(to: field.benign)
        for transport in field.transports {
            let hostileURL = try spawnURL(field: field, value: value, transport: transport)
            let benignURL = try spawnURL(field: field, value: field.benign, transport: transport)
            let benignSpec = try #require(admittedSpec(benignURL), "benign \(field) over \(transport) must be admitted")

            guard let hostileSpec = admittedSpec(hostileURL) else {
                #expect(!field.gateMustAdmit(value), "\(transport): the gate refused \(value), which it must admit")
                guard case .refused(.malformed(_)) = HolyAutomationURLGate.decide(hostileURL, policy: fullPolicy) else {
                    Issue.record("\(transport): a refusal of \(value) must be a malformed refusal")
                    continue
                }
                continue
            }
            #expect(field.gateMustAdmit(value), "\(transport): the gate admitted \(value), which it must refuse")

            let hostileConfig = HolyTmuxCommandBuilder.surfaceConfiguration(for: hostileSpec)
            let benignConfig = HolyTmuxCommandBuilder.surfaceConfiguration(for: benignSpec)
            let hostileCommand = try #require(hostileConfig.command, "\(transport): no command was built")
            let benignCommand = try #require(benignConfig.command)
            #expect(hostileConfig.initialInput == nil)

            var words: [String] = []
            let difference = Self.structuralDifference(
                hostileCommand, benignCommand, layer: "\(transport) command", words: &words
            )
            #expect(difference == nil, "\(value): \(difference ?? "")")
            #expect(words.contains { $0.contains(value) },
                    "\(transport): \(value) never reached the command as one literal word")

            switch (transport, field) {
            case (.local, .workingDirectory):
                #expect(hostileConfig.workingDirectory == value, "the local cwd is handed over as argv")
            case (.local, _):
                #expect(hostileConfig.workingDirectory == benignConfig.workingDirectory)
            case (.ssh, _):
                #expect(hostileConfig.workingDirectory == nil)
            }
        }
    }

    /// The lexer must see through the builder's own quoting idiom and must
    /// catch a value that escapes it, or the test above proves nothing.
    @Test func lexerSeparatesQuotedDataFromSyntax() {
        let quoted = HolyShellLexer("'zsh' '-lc' 'echo '\"'\"'a;b'\"'\"''")
        #expect(quoted.skeleton == "◊ ◊ ◊")
        #expect(quoted.commands == [["zsh", "-lc", "echo 'a;b'"]])
        #expect(quoted.nestedScripts == ["echo 'a;b'"])
        #expect(HolyShellLexer("echo 'a;b'").skeleton != HolyShellLexer("echo 'a';b").skeleton)
        #expect(HolyShellLexer("x=\"$(id)\"").skeleton != HolyShellLexer("x=\"id\"").skeleton)
        #expect(HolyShellLexer("x=\"$('a' 'b')\"").skeleton == HolyShellLexer("x=\"$('abc' 'd e')\"").skeleton)
        #expect(HolyShellLexer("'ssh' '--' 'h' 'zsh -lc x' 2> \"$f\"").nestedScripts == ["zsh -lc x"])
        #expect(HolyShellLexer("'tmux' 'new-session' '-c' '/d' 'sh -lc y'; z").nestedScripts == ["sh -lc y"])
    }

    /// The differential check itself must fail when a value escapes its
    /// quotes in a nested layer of a real builder command.
    @Test @MainActor func differentialCheckCatchesAValueSplicedOutsideItsQuotes() throws {
        let benignURL = try spawnURL(field: .title, value: "Benign", transport: .local)
        let spec = try #require(admittedSpec(benignURL))
        let benign = try #require(HolyTmuxCommandBuilder.surfaceConfiguration(for: spec).command)
        let outer = HolyShellLexer(benign)
        #expect(outer.commands.first?.first == "zsh")
        let script = try #require(outer.nestedScripts.first)
        #expect(script.contains("'@holy_title' 'Benign'"))

        func requoted(_ localScript: String) -> String {
            ["zsh", "-lc", localScript]
                .map { "'" + $0.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
                .joined(separator: " ")
        }
        var words: [String] = []
        #expect(Self.structuralDifference(requoted(script), benign, layer: "control", words: &words) == nil)

        let escaped = script.replacingOccurrences(of: "'@holy_title' 'Benign'", with: "'@holy_title' Benign;id")
        words = []
        #expect(Self.structuralDifference(requoted(escaped), benign, layer: "local command", words: &words)
                == "shell structure changed at local command > 0")

        let doubleQuoted = script.replacingOccurrences(of: "'@holy_title' 'Benign'", with: "'@holy_title' \"$(id)\"")
        words = []
        #expect(Self.structuralDifference(requoted(doubleQuoted), benign, layer: "local command", words: &words)
                != nil)
    }

    @Test(arguments: ["lane", "lane_1", "LANE-2", "-lane", "0"])
    func sessionNamesOnTheAllowlistAreAdmitted(name: String) {
        #expect(HolyAutomationURLGate.isAllowedTmuxSessionName(name))
    }

    @Test(arguments: ["", "a:b", "a.b", "a b", "a;", "=a", "$1", "@1", "%1", "a*", "~a", "a/b", "\u{E9}", "a\u{0}"])
    func sessionNamesOffTheAllowlistAreRefused(name: String) {
        #expect(!HolyAutomationURLGate.isAllowedTmuxSessionName(name))
    }

    @Test(arguments: ["holy", "holy.test", "a_b-c", ".hidden", "a..b"])
    func socketNamesOnTheAllowlistAreAdmitted(name: String) {
        #expect(HolyAutomationURLGate.isAllowedTmuxSocketName(name))
    }

    @Test(arguments: ["", ".", "..", "...", "a/b", "../x", "a:b", "a b", "a;", "\u{E9}"])
    func socketNamesOffTheAllowlistAreRefused(name: String) {
        #expect(!HolyAutomationURLGate.isAllowedTmuxSocketName(name))
    }

    /// The sheet and the audit line are how a human sees what a link asks
    /// for, so every non-command field must appear in both, verbatim.
    @Test @MainActor func sheetAndAuditLineShowEveryNonCommandFieldVerbatim() throws {
        let values: [HolyAutomationNonCommandField: String] = [
            .tmuxSession: "lane_7-x",
            .tmuxSocket: "sock.test",
            .workingDirectory: "/tmp/a b;$(id)`x`'q'\"d\"",
            .title: "T;$(id)|`x`>y 'q' \"d\" #{session_name}",
            .objective: "O&&$HOME ${x} *?[a] !! ~root",
            .host: "erik@studio:22",
        ]
        var components = URLComponents()
        components.scheme = "holy-ghostty"
        components.host = "spawn"
        components.percentEncodedQueryItems = [URLQueryItem(name: "transport", value: "ssh")]
            + HolyAutomationNonCommandField.allCases.map { field in
                URLQueryItem(
                    name: field.rawValue,
                    value: values[field]?.addingPercentEncoding(withAllowedCharacters: Self.unreserved)
                )
            }
        let url = try #require(components.url)

        guard case let .confirmSpawn(request) = HolyAutomationURLGate.decide(url, policy: fullPolicy) else {
            Issue.record("expected a confirmation for \(url)")
            return
        }

        let lines = HolyAutomationSpawnConfirmation.summaryLines(for: request, origin: nil)
        func line(_ label: String) -> String? { lines.first { $0.label == label }?.value }
        #expect(line("tmux") == "socket sock.test, session lane_7-x, create if missing")
        #expect(line("Working directory") == values[.workingDirectory])
        #expect(line("Title") == values[.title])
        #expect(line("Objective") == values[.objective])
        #expect(line("Transport") == "SSH to erik@studio:22")
        #expect(line("URL") == url.absoluteString)
        let sheet = HolyAutomationSpawnConfirmation.makeAlert(for: request, origin: nil).informativeText
        for value in values.values {
            #expect(sheet.contains(value), "sheet lacks \(value)")
        }

        for verdict in [HolyAutomationURLAuditEntry.Verdict.prompted, .confirmed, .cancelled] {
            let entry = HolyAutomationURLAuditEntry(verdict: verdict, detail: request.auditDetail, url: url)
            let prefix = "holy-ghostty automation URL \(verdict.rawValue) (\(request.auditDetail)): "
            #expect(entry.line.hasPrefix(prefix))
            let logged = try #require(URL(string: String(entry.line.dropFirst(prefix.count))))
            let loggedComponents = try #require(URLComponents(url: logged, resolvingAgainstBaseURL: false))
            let decoded = try #require(HolyAutomationURLParser.decodedQueryItems(in: loggedComponents))
            for field in HolyAutomationNonCommandField.allCases {
                #expect(decoded.first { $0.name == field.rawValue }?.value == values[field],
                        "audit line loses \(field)")
            }
        }
    }
}
