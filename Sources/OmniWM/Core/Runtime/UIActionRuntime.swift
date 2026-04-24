// SPDX-License-Identifier: GPL-2.0-only
import Foundation

/// Runtime-owned executor for presentation-only command actions.
///
/// UI actions do not mutate durable workspace state, but they still flow
/// through the same command transaction as other typed actions so command
/// telemetry and effect supersession have one owner.
@MainActor
final class UIActionRuntime {
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
        _ action: WMCommand.UIActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult {
        mutationCoordinator.performCommandEffect(
            kindForLog: "ui_action:\(action.kindForLog)",
            source: action.source,
            transactionEpoch: transactionEpoch,
            resultNotes: { result in ["external_result=\(String(describing: result))"] }
        ) {
            controllerOperations.performUIAction(action)
        }
    }
}
