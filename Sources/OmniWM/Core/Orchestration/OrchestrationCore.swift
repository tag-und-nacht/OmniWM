enum OrchestrationCore {
    static func step(
        snapshot: OrchestrationSnapshot,
        event: OrchestrationEvent
    ) -> OrchestrationResult {
        OrchestrationKernel.step(snapshot: snapshot, event: event)
    }
}
