import Foundation
import Domain

/// Stores the one active training plan and its edit log.
public protocol PlanRepository: Sendable {
    /// Saves `plan` as the active plan, replacing any other active plan in one transaction.
    func save(_ plan: TrainingPlan) async throws
    func loadActive() async -> TrainingPlan?
    func hasActivePlan() async -> Bool
    func deleteActive() async throws
    /// Applies `edit` in one transaction and appends it to the log. Inside the
    /// transaction it checks the sessions are still where the edit expects;
    /// otherwise it throws `PlanRepositoryError.stalePlan` and changes nothing.
    func applyEdit(planId: String, edit: PlanEdit) async throws -> EditReceipt
    /// Restores the sessions an edit touched and marks it undone. Throws
    /// `PlanRepositoryError.cannotUndo` when it is already undone or the sessions
    /// have changed since.
    func undoEdit(planId: String, editId: Int64) async throws
    /// Newest first.
    func recentEdits(planId: String, limit: Int) async throws -> [PlanEditRecord]
}

public enum PlanRepositoryError: Error, Sendable, Equatable {
    case noActivePlan
    case stalePlan
    case cannotUndo
}

/// The id of a logged edit.
public struct EditReceipt: Sendable, Equatable {
    public let editId: Int64

    public init(editId: Int64) {
        self.editId = editId
    }
}

/// One entry of the edit log.
public struct PlanEditRecord: Sendable, Equatable {
    public let id: Int64
    public let createdAt: Date
    public let edit: PlanEdit
    public let change: PlanChange
    public let undoneAt: Date?

    public init(id: Int64, createdAt: Date, edit: PlanEdit, change: PlanChange, undoneAt: Date?) {
        self.id = id
        self.createdAt = createdAt
        self.edit = edit
        self.change = change
        self.undoneAt = undoneAt
    }
}
