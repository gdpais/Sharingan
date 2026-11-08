import Foundation
import Observation
import SharinganCore

struct CodexSystemAccountPromotionUserFacingError: Error, Equatable {
    let title: String
    let message: String
}

@MainActor
@Observable
final class CodexAccountPromotionCoordinator {
    let service: CodexAccountPromotionService
    weak var managedAccountCoordinator: ManagedCodexAccountCoordinator?
    private(set) var isAuthenticatingLiveAccount = false
    private(set) var isPromotingSystemAccount = false
    private(set) var daemonRestartNote: String?

    init(
        service: CodexAccountPromotionService,
        managedAccountCoordinator: ManagedCodexAccountCoordinator? = nil)
    {
        self.service = service
        self.managedAccountCoordinator = managedAccountCoordinator
    }

    convenience init(
        settingsStore: SettingsStore,
        usageStore: UsageStore,
        managedAccountCoordinator: ManagedCodexAccountCoordinator? = nil)
    {
        self.init(
            service: CodexAccountPromotionService(settingsStore: settingsStore, usageStore: usageStore),
            managedAccountCoordinator: managedAccountCoordinator)
    }

    func promote(managedAccountID: UUID)
        async -> Result<CodexAccountPromotionResult, CodexSystemAccountPromotionUserFacingError>
    {
        guard !self.isInteractionBlocked() else {
            return .failure(Self.interactionBlockedError())
        }

        self.isPromotingSystemAccount = true
        self.daemonRestartNote = nil
        defer { self.isPromotingSystemAccount = false }

        do {
            let result = try await self.service.promoteManagedAccount(id: managedAccountID)
            self.daemonRestartNote = result.daemonRestartNote
            return .success(result)
        } catch {
            return .failure(Self.mapUserFacingError(error))
        }
    }

    func setLiveReauthenticationInProgress(_ isInProgress: Bool) {
        self.isAuthenticatingLiveAccount = isInProgress
    }

    func isInteractionBlocked() -> Bool {
        self.isPromotingSystemAccount ||
            self.isAuthenticatingLiveAccount ||
            self.managedAccountCoordinator?.hasConflictingManagedAccountOperationInFlight == true
    }

    private static func interactionBlockedError() -> CodexSystemAccountPromotionUserFacingError {
        CodexSystemAccountPromotionUserFacingError(
            title: L("Could not switch system account"),
            message: L("Finish the current managed account change before switching the system account."))
    }

    static func mapUserFacingError(_ error: Error) -> CodexSystemAccountPromotionUserFacingError {
        let title = L("Could not switch system account")

        if let error = error as? CodexAccountPromotionError {
            let message = switch error {
            case .targetManagedAccountNotFound:
                L("That account is no longer available in Sharingan. Refresh the account list and try again.")
            case .targetManagedAccountAuthMissing:
                L("Sharingan could not find saved auth for that account. Re-authenticate it and try again.")
            case .targetManagedAccountAuthUnreadable:
                L("Sharingan could not read saved auth for that account. Re-authenticate it and try again.")
            case .targetManagedAccountWorkspaceDiffersFromAuthDefault:
                L(
                    "That managed account uses a workspace that differs from its saved Codex auth default. " +
                        "Keep it as a managed account; Sharingan will not rewrite Codex-owned auth to promote it.")
            case .liveAccountUnreadable:
                L("Sharingan could not read the current system account on this Mac.")
            case .liveAccountMissingIdentityForPreservation:
                L("Sharingan could not safely preserve the current system account before switching.")
            case .liveAccountAPIKeyOnlyUnsupported:
                L("Sharingan can't replace a system account that is signed in with an API key only setup.")
            case .displacedLiveManagedAccountConflict:
                L(
                    "Sharingan found another managed account that already uses the current system account. " +
                        "Resolve the duplicate account before switching.")
            case .displacedLiveImportFailed:
                L("Sharingan could not save the current system account before switching.")
            case .managedStoreCommitFailed:
                L("Sharingan could not update managed account storage.")
            case .liveAuthSwapFailed:
                L("Sharingan could not replace the live Codex auth on this Mac.")
            case .liveAuthChangedDuringPromotion, .targetAuthChangedDuringPromotion, .liveHomeIsManaged:
                error.localizedDescription
            }

            return CodexSystemAccountPromotionUserFacingError(title: title, message: message)
        }

        return CodexSystemAccountPromotionUserFacingError(title: title, message: error.localizedDescription)
    }
}
