// SPDX-License-Identifier: GPL-2.0-only
import Foundation

/// Runtime-owned executor for typed controller actions.
///
/// These actions still orchestrate controller-owned collaborators, but the
/// command effect and any synchronous nested runtime mutations share the
/// submitted command transaction through `RuntimeMutationCoordinator`.
@MainActor
final class ControllerActionRuntime {
    private let mutationCoordinator: RuntimeMutationCoordinator
    private let controllerOperations: RuntimeControllerOperations

    init(
        mutationCoordinator: RuntimeMutationCoordinator,
        controllerOperations: RuntimeControllerOperations
    ) {
        self.mutationCoordinator = mutationCoordinator
        self.controllerOperations = controllerOperations
    }

    @discardableResult
    func perform(
        _ action: WMCommand.ControllerActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult {
        mutationCoordinator.performCommandEffect(
            kindForLog: "controller_action:\(action.kindForLog)",
            source: action.source,
            transactionEpoch: transactionEpoch,
            resultNotes: { result in ["external_result=\(String(describing: result))"] }
        ) {
            controllerOperations.performControllerAction(action)
        }
    }
}
