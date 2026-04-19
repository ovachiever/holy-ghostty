import Foundation
import SQLite3

struct HolyBudgetSample: Identifiable, Equatable {
    let id: Int64
    let sessionID: UUID
    let capturedAt: Date
    let runtime: HolySessionRuntime
    let taskID: UUID?
    let totalTokens: Int?
    let estimatedCostUSD: Double?
    let budgetStatus: HolySessionBudgetStatus
    let tokenLimit: Int?
    let costLimitUSD: Double?
}

struct HolyBudgetRuntimeRollup: Equatable {
    let runtime: HolySessionRuntime
    let sessionCount: Int
    let totalTokens: Int
    let totalCostUSD: Double

    var summaryText: String {
        let tokens = totalTokens.formatted(.number.grouping(.automatic))
        return "\(tokens) tokens · \(String(format: "$%.2f", totalCostUSD)) across \(sessionCount) sessions"
    }
}

struct HolyBudgetSessionIntelligence: Equatable {
    let sampleCount: Int
    let runtimeRollup: HolyBudgetRuntimeRollup?
    let projectedExhaustionAt: Date?
    let projectedLimitLabel: String?

    var projectionText: String {
        guard let projectedLimitLabel, let projectedExhaustionAt else {
            return "No durable projection yet"
        }

        return "\(projectedLimitLabel) at \(projectedExhaustionAt.formatted(date: .omitted, time: .shortened))"
    }
}

private struct HolyBudgetSampleDraft {
    let sessionID: UUID
    let runtime: HolySessionRuntime
    let taskID: UUID?
    let telemetry: HolySessionBudgetTelemetry
    let budget: HolySessionBudget
    let budgetStatus: HolySessionBudgetStatus
    let capturedAt: Date
}

enum HolyBudgetIntelligenceRepository {
    @MainActor
    static func appendSamples(
        activeSessions: [HolySession],
        archivedSessions: [HolyArchivedSession],
        in database: HolyDatabase
    ) throws {
        for session in activeSessions {
            try appendSampleIfNeeded(
                .init(
                    sessionID: session.id,
                    runtime: session.runtime,
                    taskID: session.record.launchSpec.task?.id,
                    telemetry: session.budgetTelemetry,
                    budget: session.budget,
                    budgetStatus: session.budgetStatus,
                    capturedAt: session.activityAt
                ),
                in: database
            )
        }

        for archivedSession in archivedSessions {
            try appendSampleIfNeeded(
                .init(
                    sessionID: archivedSession.sourceSessionID,
                    runtime: archivedSession.runtime,
                    taskID: archivedSession.record.launchSpec.task?.id,
                    telemetry: archivedSession.budgetTelemetry,
                    budget: archivedSession.record.launchSpec.budget ?? .none,
                    budgetStatus: budgetStatus(for: archivedSession),
                    capturedAt: archivedSession.lastActivityAt
                ),
                in: database
            )
        }
    }

    static func loadSessionIntelligence(
        sessionID: UUID,
        runtime: HolySessionRuntime,
        budget: HolySessionBudget
    ) -> HolyBudgetSessionIntelligence? {
        do {
            let database = try HolyDatabase.openAppDatabase(readOnly: true)
            return try loadSessionIntelligence(
                sessionID: sessionID,
                runtime: runtime,
                budget: budget,
                in: database
            )
        } catch {
            return nil
        }
    }

    private static func loadSessionIntelligence(
        sessionID: UUID,
        runtime: HolySessionRuntime,
        budget: HolySessionBudget,
        in database: HolyDatabase
    ) throws -> HolyBudgetSessionIntelligence? {
        let samples = try recentSamples(for: sessionID, limit: 24, in: database)
        guard !samples.isEmpty else { return nil }

        let rollup = try runtimeRollup(for: runtime, in: database)
        let projection = projectedExhaustion(for: samples, budget: budget)

        return .init(
            sampleCount: samples.count,
            runtimeRollup: rollup,
            projectedExhaustionAt: projection.date,
            projectedLimitLabel: projection.label
        )
    }

    private static func appendSampleIfNeeded(
        _ draft: HolyBudgetSampleDraft,
        in database: HolyDatabase
    ) throws {
        guard draft.telemetry.hasUsage else { return }

        let latestSample = try latestSample(for: draft.sessionID, in: database)
        let currentTokens = draft.telemetry.resolvedTotalTokens
        let currentCost = draft.telemetry.estimatedCostUSD

        if let latestSample,
           latestSample.totalTokens == currentTokens,
           latestSample.estimatedCostUSD == currentCost,
           latestSample.budgetStatus == draft.budgetStatus {
            let elapsed = draft.capturedAt.timeIntervalSince(latestSample.capturedAt)
            guard elapsed >= 300 else { return }
        }

        let sql = """
        INSERT INTO budget_samples (
            session_id, captured_at, runtime, source_task_id, total_tokens,
            estimated_cost_usd, budget_status, token_limit, cost_limit_usd
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try database.execute(sql, bindings: [
            .text(draft.sessionID.uuidString),
            .text(HolyPersistenceCoders.string(from: draft.capturedAt)),
            .text(draft.runtime.rawValue),
            draft.taskID.map { .text($0.uuidString) } ?? .null,
            currentTokens.map { .int64(Int64($0)) } ?? .null,
            currentCost.map(HolyDatabaseBinding.double) ?? .null,
            .text(draft.budgetStatus.rawValue),
            draft.budget.tokenLimit.map { .int64(Int64($0)) } ?? .null,
            draft.budget.costLimitUSD.map(HolyDatabaseBinding.double) ?? .null,
        ])
    }

    private static func latestSample(for sessionID: UUID, in database: HolyDatabase) throws -> HolyBudgetSample? {
        let sql = """
        SELECT id, session_id, captured_at, runtime, source_task_id, total_tokens,
               estimated_cost_usd, budget_status, token_limit, cost_limit_usd
        FROM budget_samples
        WHERE session_id = ?
        ORDER BY captured_at DESC, id DESC
        LIMIT 1;
        """

        var sample: HolyBudgetSample?
        try database.query(sql, bindings: [.text(sessionID.uuidString)]) { statement in
            sample = try decodeSample(statement)
        }
        return sample
    }

    private static func recentSamples(
        for sessionID: UUID,
        limit: Int,
        in database: HolyDatabase
    ) throws -> [HolyBudgetSample] {
        let sql = """
        SELECT id, session_id, captured_at, runtime, source_task_id, total_tokens,
               estimated_cost_usd, budget_status, token_limit, cost_limit_usd
        FROM budget_samples
        WHERE session_id = ?
        ORDER BY captured_at DESC, id DESC
        LIMIT ?;
        """

        var samples: [HolyBudgetSample] = []
        try database.query(sql, bindings: [.text(sessionID.uuidString), .int64(Int64(limit))]) { statement in
            samples.append(try decodeSample(statement))
        }
        return samples.sorted { $0.capturedAt < $1.capturedAt }
    }

    private static func runtimeRollup(
        for runtime: HolySessionRuntime,
        in database: HolyDatabase
    ) throws -> HolyBudgetRuntimeRollup? {
        let sql = """
        WITH latest_per_session AS (
            SELECT runtime, session_id, MAX(captured_at) AS captured_at
            FROM budget_samples
            WHERE runtime = ?
            GROUP BY runtime, session_id
        )
        SELECT
            COUNT(*) AS session_count,
            COALESCE(SUM(COALESCE(samples.total_tokens, 0)), 0) AS total_tokens,
            COALESCE(SUM(COALESCE(samples.estimated_cost_usd, 0)), 0) AS total_cost_usd
        FROM latest_per_session
        JOIN budget_samples AS samples
          ON samples.runtime = latest_per_session.runtime
         AND samples.session_id = latest_per_session.session_id
         AND samples.captured_at = latest_per_session.captured_at;
        """

        var rollup: HolyBudgetRuntimeRollup?
        try database.query(sql, bindings: [.text(runtime.rawValue)]) { statement in
            let sessionCount = Int(sqlite3_column_int64(statement, 0))
            guard sessionCount > 0 else { return }

            rollup = .init(
                runtime: runtime,
                sessionCount: sessionCount,
                totalTokens: Int(sqlite3_column_int64(statement, 1)),
                totalCostUSD: sqlite3_column_double(statement, 2)
            )
        }
        return rollup
    }

    private static func projectedExhaustion(
        for samples: [HolyBudgetSample],
        budget: HolySessionBudget
    ) -> (date: Date?, label: String?) {
        guard samples.count >= 2,
              let first = samples.first,
              let last = samples.last,
              last.capturedAt > first.capturedAt else {
            return (nil, nil)
        }

        let duration = last.capturedAt.timeIntervalSince(first.capturedAt)
        guard duration > 0 else { return (nil, nil) }

        var projections: [(Date, String)] = []

        if let tokenLimit = budget.tokenLimit,
           let firstTokens = first.totalTokens,
           let lastTokens = last.totalTokens,
           lastTokens > firstTokens {
            let rate = Double(lastTokens - firstTokens) / duration
            let remaining = Double(max(0, tokenLimit - lastTokens))
            if rate > 0, remaining > 0 {
                projections.append((last.capturedAt.addingTimeInterval(remaining / rate), "Token limit"))
            }
        }

        if let costLimitUSD = budget.costLimitUSD,
           let firstCost = first.estimatedCostUSD,
           let lastCost = last.estimatedCostUSD,
           lastCost > firstCost {
            let rate = (lastCost - firstCost) / duration
            let remaining = max(0, costLimitUSD - lastCost)
            if rate > 0, remaining > 0 {
                projections.append((last.capturedAt.addingTimeInterval(remaining / rate), "Cost limit"))
            }
        }

        guard let earliest = projections.min(by: { $0.0 < $1.0 }) else {
            return (nil, nil)
        }

        return earliest
    }

    private static func budgetStatus(for archivedSession: HolyArchivedSession) -> HolySessionBudgetStatus {
        let budget = archivedSession.record.launchSpec.budget ?? .none
        guard budget.isConfigured else { return .none }

        let tokenUtilization = utilization(
            used: archivedSession.budgetTelemetry.resolvedTotalTokens,
            limit: budget.tokenLimit
        )
        let costUtilization = utilization(
            used: archivedSession.budgetTelemetry.estimatedCostUSD,
            limit: budget.costLimitUSD
        )
        let utilization = max(tokenUtilization ?? 0, costUtilization ?? 0)

        if utilization >= 1 {
            return .exceeded
        }

        if utilization >= budget.warningThreshold {
            return .warning
        }

        return .healthy
    }

    private static func utilization(used: Int?, limit: Int?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return Double(used) / Double(limit)
    }

    private static func utilization(used: Double?, limit: Double?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return used / limit
    }

    private static func decodeSample(_ statement: OpaquePointer) throws -> HolyBudgetSample {
        let id = sqlite3_column_int64(statement, 0)
        let sessionIDString = try requiredText(statement, index: 1)
        guard let sessionID = UUID(uuidString: sessionIDString) else {
            throw CocoaError(.coderInvalidValue)
        }

        let capturedAt = try HolyPersistenceCoders.date(from: requiredText(statement, index: 2))
        let runtimeRaw = try requiredText(statement, index: 3)
        guard let runtime = HolySessionRuntime(rawValue: runtimeRaw) else {
            throw CocoaError(.coderInvalidValue)
        }

        let taskID = text(statement, index: 4).flatMap(UUID.init(uuidString:))
        let totalTokens = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 5))
        let estimatedCostUSD = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 6)
        let budgetStatusRaw = try requiredText(statement, index: 7)
        guard let budgetStatus = HolySessionBudgetStatus(rawValue: budgetStatusRaw) else {
            throw CocoaError(.coderInvalidValue)
        }

        let tokenLimit = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 8))
        let costLimitUSD = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 9)

        return .init(
            id: id,
            sessionID: sessionID,
            capturedAt: capturedAt,
            runtime: runtime,
            taskID: taskID,
            totalTokens: totalTokens,
            estimatedCostUSD: estimatedCostUSD,
            budgetStatus: budgetStatus,
            tokenLimit: tokenLimit,
            costLimitUSD: costLimitUSD
        )
    }

    private static func requiredText(_ statement: OpaquePointer, index: Int32) throws -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            throw CocoaError(.coderValueNotFound)
        }
        return String(cString: value)
    }

    private static func text(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }
}
