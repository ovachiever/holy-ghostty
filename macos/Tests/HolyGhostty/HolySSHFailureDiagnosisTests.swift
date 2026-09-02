import Testing
@testable import Ghostty

struct HolySSHFailureDiagnosisTests {
    @Test func keyExchangeResetIsExplicitServerSaturation() throws {
        let diagnosis = try #require(HolySSHFailureDiagnosis.diagnose(
            destination: "studio",
            exitCode: 255,
            stderr: "kex_exchange_identification: read: Connection reset by peer"
        ))

        #expect(diagnosis.kind == .serverAdmissionRejected)
        #expect(diagnosis.headline == "SSH instance saturation")
        #expect(diagnosis.userMessage.contains("server instance limit is saturated"))
        #expect(!diagnosis.userMessage.contains("could not reach"))
    }

    @Test(arguments: [
        "ssh: Could not resolve hostname studio: nodename nor servname provided",
        "ssh: connect to host studio port 22: Operation timed out",
        "ssh: connect to host studio port 22: Connection refused",
    ])
    func transportNetworkFailuresStayDistinctFromSaturation(stderr: String) throws {
        let diagnosis = try #require(HolySSHFailureDiagnosis.diagnose(
            destination: "studio",
            exitCode: 255,
            stderr: stderr
        ))

        #expect(diagnosis.kind == .network)
        #expect(diagnosis.headline == "SSH network failure")
    }

    @Test func hostTrustAndAuthenticationHaveDifferentRecoveryStates() throws {
        let trust = try #require(HolySSHFailureDiagnosis.diagnose(
            destination: "studio",
            exitCode: 255,
            stderr: "Host key verification failed."
        ))
        let authentication = try #require(HolySSHFailureDiagnosis.diagnose(
            destination: "erik@studio",
            exitCode: 255,
            stderr: "Permission denied (publickey)."
        ))

        #expect(trust.kind == .hostVerification)
        #expect(authentication.kind == .authentication)
        #expect(trust.userMessage.contains("trust"))
        #expect(authentication.userMessage.contains("key"))
    }

    @Test func stageMarkerProvesRemoteCommandRanEvenWhenItReturns255() throws {
        let diagnosis = try #require(HolySSHFailureDiagnosis.diagnose(
            destination: "studio",
            exitCode: 255,
            stderr: "HOLY_TMUX_STAGE:kill\ntmux server exited unexpectedly"
        ))

        #expect(diagnosis.kind == .remoteCommand)
        #expect(diagnosis.userMessage.contains("connection itself was healthy"))
    }

    @Test func unclassifiedExit255StaysAnHonestTransportFailure() throws {
        let diagnosis = try #require(HolySSHFailureDiagnosis.diagnose(
            destination: "studio",
            exitCode: 255,
            stderr: "ssh failed without a recognizable reason"
        ))

        #expect(diagnosis.kind == .transport)
        #expect(diagnosis.userMessage.contains("before Holy could prove"))
    }

    @Test func synchronousSurfaceReporterUsesTheSameExplicitCategories() {
        let script = HolySSHFailureDiagnosis.shellReporterScript(destination: "studio")

        #expect(script.contains("SSH instance saturation"))
        #expect(script.contains("SSH network failure"))
        #expect(script.contains("SSH host verification failed"))
        #expect(script.contains("SSH authentication failed"))
        #expect(script.contains("Remote command failed"))
        #expect(script.contains("SSH transport failed"))
        #expect(!script.contains("could not reach"))
    }
}
