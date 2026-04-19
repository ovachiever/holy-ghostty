import SwiftUI

struct HolyBudgetIntelligenceSection: View {
    let sessionID: UUID
    let runtime: HolySessionRuntime
    let budget: HolySessionBudget
    let refreshID: String

    @State private var intelligence: HolyBudgetSessionIntelligence?

    var body: some View {
        Group {
            if let intelligence {
                VStack(alignment: .leading, spacing: 6) {
                    contextRow("Ledger", "\(intelligence.sampleCount) samples")
                    contextRow("Projection", intelligence.projectionText)

                    if let runtimeRollup = intelligence.runtimeRollup {
                        contextRow("Runtime Spend", runtimeRollup.summaryText)
                    }
                }
            }
        }
        .task(id: refreshID) {
            await loadIntelligence()
        }
    }

    private func loadIntelligence() async {
        let result = await Task.detached(priority: .utility) {
            HolyBudgetIntelligenceRepository.loadSessionIntelligence(
                sessionID: sessionID,
                runtime: runtime,
                budget: budget
            )
        }.value

        intelligence = result
    }

    private func contextRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .frame(width: 70, alignment: .trailing)

            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
