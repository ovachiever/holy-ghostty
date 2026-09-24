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
