# Phase 0 Baseline Capture

Use this note for the before/after capture that phases 0 through 3 compare against.

## Setup

1. Launch OmniWM with `OMNIWM_DEBUG_HOT_PATH_METRICS=1`.
2. Launch with `OMNIWM_DEBUG_RUNTIME_TRACE=1` only if you also want the summary trace ring.
3. Launch with `OMNIWM_DEBUG_RUNTIME_TRACE_VERBOSE=1` if you need the detailed trace formatting instead of the summary mode.
4. Start from a fresh OmniWM launch so the hot-path counters begin near zero.

## Scenario

- 20 rapid `alt+left/right` presses across a 12-column workspace
- 8+ visible windows
- at least one workspace switch during the capture

## Capture

1. Run the scenario once.
2. Record Instruments data for:
   - main-thread `tickScrollAnimation` self-time p99 per display-link tick
   - `swift_reflectionMirror_subscript` call count
   - visible dropped frames
3. Dump the app-side counters with:

```bash
omniwmctl query reconcile-debug
```

Copy the `HOT PATH METRICS` section into the run log below.

## Run Log

### Baseline

- Date:
- Commit:
- `tickScrollAnimation` p99:
- `swift_reflectionMirror_subscript` count:
- Dropped frames observed:
- Notes:

```text
HOT PATH METRICS
```

### After Phase 1

- Date:
- Commit:
- `tickScrollAnimation` p99:
- `swift_reflectionMirror_subscript` count:
- Dropped frames observed:
- Notes:

```text
HOT PATH METRICS
```
