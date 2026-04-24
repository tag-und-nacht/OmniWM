// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct WMRuntimeIntakeRedactionTests {
    private static let sensitiveSubstrings: [String] = [
        "Safari",
        "Mail",
        "Slack",
        "secret",
        "session_token",
        "Bearer ",
        "password",
        "Untitled Document",
        "Re: confidential",
        "AXTitle",
        "AXDocument"
    ]

    @Test func kindForLogIsStableAndPayloadFreeForEveryWMEventCase() {
        let token = WindowToken(pid: 1234, windowId: 42)
        let workspaceId = UUID()
        let monitorId = Monitor.ID.fallback

        let cases: [(WMEvent, String)] = [
            (.windowAdmitted(
                token: token,
                workspaceId: workspaceId,
                monitorId: monitorId,
                mode: .tiling,
                source: .ax
            ), "window_admitted"),
            (.windowRekeyed(
                from: token,
                to: WindowToken(pid: 1234, windowId: 99),
                workspaceId: workspaceId,
                monitorId: monitorId,
                reason: .managedReplacement,
                source: .ax
            ), "window_rekeyed"),
            (.windowRemoved(
                token: token,
                workspaceId: workspaceId,
                source: .ax
            ), "window_removed"),
            (.workspaceAssigned(
                token: token,
                from: nil,
                to: workspaceId,
                monitorId: monitorId,
                source: .command
            ), "workspace_assigned"),
            (.windowModeChanged(
                token: token,
                workspaceId: workspaceId,
                monitorId: monitorId,
                mode: .floating,
                source: .command
            ), "window_mode_changed"),
            (.floatingGeometryUpdated(
                token: token,
                workspaceId: workspaceId,
                referenceMonitorId: monitorId,
                frame: .zero,
                restoreToFloating: false,
                source: .ax
            ), "floating_geometry_updated"),
            (.hiddenStateChanged(
                token: token,
                workspaceId: workspaceId,
                monitorId: monitorId,
                hiddenState: nil,
                source: .ax
            ), "hidden_state_changed"),
            (.nativeFullscreenTransition(
                token: token,
                workspaceId: workspaceId,
                monitorId: monitorId,
                isActive: true,
                source: .ax
            ), "native_fullscreen_transition"),
            (.managedReplacementMetadataChanged(
                token: token,
                workspaceId: workspaceId,
                monitorId: monitorId,
                source: .ax
            ), "managed_replacement_metadata_changed"),
            (.topologyChanged(
                displays: [],
                source: .workspaceManager
            ), "topology_changed"),
            (.activeSpaceChanged(source: .workspaceManager), "active_space_changed"),
            (.focusLeaseChanged(lease: nil, source: .focusPolicy), "focus_lease_changed"),
            (.managedFocusRequested(
                token: token,
                workspaceId: workspaceId,
                monitorId: monitorId,
                source: .focusPolicy
            ), "managed_focus_requested"),
            (.managedFocusConfirmed(
                token: token,
                workspaceId: workspaceId,
                monitorId: monitorId,
                appFullscreen: false,
                source: .ax,
                originatingTransactionEpoch: .invalid
            ), "managed_focus_confirmed"),
            (.managedFocusCancelled(
                token: token,
                workspaceId: workspaceId,
                source: .ax,
                originatingTransactionEpoch: .invalid
            ), "managed_focus_cancelled"),
            (.nonManagedFocusChanged(
                active: true,
                appFullscreen: false,
                preserveFocusedToken: false,
                source: .ax
            ), "non_managed_focus_changed"),
            (.systemSleep(source: .service), "system_sleep"),
            (.systemWake(source: .service), "system_wake")
        ]

        for (event, expectedKind) in cases {
            #expect(event.kindForLog == expectedKind)
            for sensitive in Self.sensitiveSubstrings {
                #expect(
                    !event.kindForLog.contains(sensitive),
                    "kindForLog must not contain sensitive substring \(sensitive) for \(expectedKind)"
                )
            }
        }
    }

    @Test func kindForLogIsPayloadFreeForEveryWMCommandCase() {
        let cases: [(WMCommand, String)] = [
            (.workspaceSwitch(.explicit(rawWorkspaceID: "secret-9000")), "workspace_switch_explicit"),
            (.workspaceSwitch(.relative(isNext: true, wrapAround: false)), "workspace_switch_relative"),
            (.focusAction(.focusNeighbor(.right, source: .ipc)), "focus_action:focus"),
            (.focusAction(.focusColumn(8888, source: .ipc)), "focus_action:focus_column"),
            (.focusAction(.focusMonitorLast(source: .command)), "focus_action:focus_monitor_last"),
            (.windowMoveAction(.moveWindow(.left, source: .command)), "window_move_action:move"),
            (.windowMoveAction(.moveColumnToWorkspace(7777, source: .ipc)), "window_move_action:move_column_to_workspace"),
            (.layoutMutationAction(.toggleNativeFullscreen(source: .command)), "layout_mutation_action:toggle_native_fullscreen"),
            (.layoutMutationAction(.resizeInDirection(.right, grow: true, source: .command)), "layout_mutation_action:resize_in_direction"),
            (.workspaceNavigationAction(.workspaceBackAndForth(source: .ipc)), "workspace_navigation_action:workspace_back_and_forth"),
            (.uiAction(.toggleOverview(source: .command)), "ui_action:toggle_overview")
        ]

        for (command, expectedKind) in cases {
            #expect(command.kindForLog == expectedKind)
            #expect(!command.kindForLog.contains("secret-9000"))
            #expect(!command.kindForLog.contains("right"))
            #expect(!command.kindForLog.contains("left"))
            #expect(!command.kindForLog.contains("8888"))
            #expect(!command.kindForLog.contains("7777"))
            #expect(!command.kindForLog.contains("="))
            #expect(!command.kindForLog.contains(" "))
        }
    }

    @Test @MainActor func kindForLogIsPayloadFreeForEveryInputBindingTriggerViaTypedPromotion() {
        let sentinelInts = [9999, 7777, 4242, 1234]

        let hotkeyCases: [(InputBindingTrigger, String)] = [
            (.focus(.left), "focus"),
            (.focusPrevious, "focus_previous"),
            (.move(.right), "move"),
            (.moveToWorkspace(9999), "move_to_workspace"),
            (.moveWindowToWorkspaceUp, "move_window_to_workspace_up"),
            (.moveWindowToWorkspaceDown, "move_window_to_workspace_down"),
            (.moveColumnToWorkspace(7777), "move_column_to_workspace"),
            (.moveColumnToWorkspaceUp, "move_column_to_workspace_up"),
            (.moveColumnToWorkspaceDown, "move_column_to_workspace_down"),
            (.switchWorkspace(4242), "switch_workspace"),
            (.switchWorkspaceNext, "switch_workspace_next"),
            (.switchWorkspacePrevious, "switch_workspace_previous"),
            (.focusMonitorPrevious, "focus_monitor_previous"),
            (.focusMonitorNext, "focus_monitor_next"),
            (.focusMonitorLast, "focus_monitor_last"),
            (.toggleFullscreen, "toggle_fullscreen"),
            (.toggleNativeFullscreen, "toggle_native_fullscreen"),
            (.moveColumn(.up), "move_column"),
            (.toggleColumnTabbed, "toggle_column_tabbed"),
            (.focusDownOrLeft, "focus_down_or_left"),
            (.focusUpOrRight, "focus_up_or_right"),
            (.focusColumnFirst, "focus_column_first"),
            (.focusColumnLast, "focus_column_last"),
            (.focusColumn(1234), "focus_column"),
            (.cycleColumnWidthForward, "cycle_column_width_forward"),
            (.cycleColumnWidthBackward, "cycle_column_width_backward"),
            (.toggleColumnFullWidth, "toggle_column_full_width"),
            (.swapWorkspaceWithMonitor(.left), "swap_workspace_with_monitor"),
            (.balanceSizes, "balance_sizes"),
            (.moveToRoot, "move_to_root"),
            (.toggleSplit, "toggle_split"),
            (.swapSplit, "swap_split"),
            (.resizeInDirection(.right, true), "resize_in_direction"),
            (.preselect(.down), "preselect"),
            (.preselectClear, "preselect_clear"),
            (.workspaceBackAndForth, "workspace_back_and_forth"),
            (.focusWorkspaceAnywhere(9999), "focus_workspace_anywhere"),
            (
                .moveWindowToWorkspaceOnMonitor(workspaceIndex: 7777, monitorDirection: .right),
                "move_window_to_workspace_on_monitor"
            ),
            (.openCommandPalette, "open_command_palette"),
            (.raiseAllFloatingWindows, "raise_all_floating_windows"),
            (.rescueOffscreenWindows, "rescue_offscreen_windows"),
            (.toggleFocusedWindowFloating, "toggle_focused_window_floating"),
            (.assignFocusedWindowToScratchpad, "assign_focused_window_to_scratchpad"),
            (.toggleScratchpadWindow, "toggle_scratchpad_window"),
            (.openMenuAnywhere, "open_menu_anywhere"),
            (.toggleWorkspaceBarVisibility, "toggle_workspace_bar_visibility"),
            (.toggleHiddenBar, "toggle_hidden_bar"),
            (.toggleQuakeTerminal, "toggle_quake_terminal"),
            (.toggleWorkspaceLayout, "toggle_workspace_layout"),
            (.toggleOverview, "toggle_overview")
        ]

        let typedPrefixes = [
            "workspace_switch_explicit",
            "workspace_switch_relative",
            "controller_action:",
            "focus_action:",
            "window_move_action:",
            "layout_mutation_action:",
            "workspace_navigation_action:",
            "ui_action:"
        ]

        for (hotkey, expectedHotkeyKind) in hotkeyCases {
            #expect(
                hotkey.kindForLog == expectedHotkeyKind,
                "InputBindingTrigger.kindForLog mismatch for expected \(expectedHotkeyKind)"
            )

            let command = WMRuntime.typedCommand(for: hotkey, source: .ipc)
            let kindForLog = command.kindForLog
            let hasTypedPrefix = typedPrefixes.contains { kindForLog.hasPrefix($0) }
            #expect(
                hasTypedPrefix,
                "kindForLog \(kindForLog) for hotkey \(expectedHotkeyKind) is not in any typed group"
            )

            for sensitive in Self.sensitiveSubstrings {
                #expect(
                    !kindForLog.contains(sensitive),
                    "kindForLog must not contain sensitive substring \(sensitive) for \(expectedHotkeyKind)"
                )
            }

            for sentinel in sentinelInts {
                #expect(
                    !kindForLog.contains(String(sentinel)),
                    "kindForLog must not contain sentinel \(sentinel) for \(expectedHotkeyKind)"
                )
            }

            #expect(!kindForLog.contains("="))
            #expect(!kindForLog.contains(" "))
        }
    }

    @Test func wmEventSourceIncludesRuntimeProvenanceCases() {
        let allCases: Set<WMEventSource> = [
            .ax,
            .workspaceManager,
            .service,
            .command,
            .keyboard,
            .config,
            .animation,
            .mouse,
            .focusPolicy,
            .ipc
        ]
        #expect(allCases.contains(.ipc))
        #expect(allCases.contains(.keyboard))
        #expect(allCases.contains(.config))
        #expect(allCases.contains(.animation))
        #expect(WMEventSource.ipc.rawValue == "ipc")
        #expect(WMEventSource.keyboard.rawValue == "keyboard")
        #expect(WMEventSource.config.rawValue == "config")
        #expect(WMEventSource.animation.rawValue == "animation")
    }

    @Test func wmCommandDefaultSourceForLogIsCommandUntilIPCRouting() {
        let command = WMCommand.workspaceSwitch(.explicit(rawWorkspaceID: "1"))
        #expect(command.sourceForLog == .command)
    }
}
