import AppKit
import Foundation

/// Reports whether anyone can currently see the menu bar: false while the display sleeps or the
/// session is locked. Event-driven only; it never polls.
@MainActor
final class DisplayActivityMonitor {
    struct State: Equatable {
        var screensAsleep = false
        var sessionLocked = false

        var isInactive: Bool {
            self.screensAsleep || self.sessionLocked
        }
    }

    enum Event: Sendable {
        case screensDidSleep
        case screensDidWake
        case sessionDidLock
        case sessionDidUnlock
    }

    private static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

    private let onChange: @MainActor (Bool) -> Void
    private var state = State()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
    }

    nonisolated static func reduce(_ state: State, _ event: Event) -> State {
        var next = state
        switch event {
        case .screensDidSleep:
            next.screensAsleep = true
        case .screensDidWake:
            next.screensAsleep = false
        case .sessionDidLock:
            next.sessionLocked = true
        case .sessionDidUnlock:
            next.sessionLocked = false
        }
        return next
    }

    func start() {
        guard self.workspaceObservers.isEmpty, self.distributedObservers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceEvents: [(Notification.Name, Event)] = [
            (NSWorkspace.screensDidSleepNotification, .screensDidSleep),
            (NSWorkspace.screensDidWakeNotification, .screensDidWake),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionDidLock),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionDidUnlock),
        ]
        self.workspaceObservers = workspaceEvents.map { name, event in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
        let distributedCenter = DistributedNotificationCenter.default()
        let distributedEvents: [(Notification.Name, Event)] = [
            (Self.screenLockedNotification, .sessionDidLock),
            (Self.screenUnlockedNotification, .sessionDidUnlock),
        ]
        self.distributedObservers = distributedEvents.map { name, event in
            distributedCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in self.workspaceObservers {
            workspaceCenter.removeObserver(observer)
        }
        self.workspaceObservers.removeAll()
        let distributedCenter = DistributedNotificationCenter.default()
        for observer in self.distributedObservers {
            distributedCenter.removeObserver(observer)
        }
        self.distributedObservers.removeAll()
    }

    func handle(_ event: Event) {
        let wasInactive = self.state.isInactive
        self.state = Self.reduce(self.state, event)
        guard self.state.isInactive != wasInactive else { return }
        self.onChange(self.state.isInactive)
    }
}
