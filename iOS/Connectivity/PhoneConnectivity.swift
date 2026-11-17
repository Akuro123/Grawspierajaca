import Foundation
import WatchConnectivity

/// Cienka warstwa nad WCSession po stronie iPhone'a.
final class PhoneConnectivity: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var isReachable = false
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    var onMessage: ((WatchMessage) -> Void)?

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let s = session else { return }
        s.delegate = self
        s.activate()
    }

    /// Zwraca false, gdy wiadomości nie dało się wysłać od razu.
    @discardableResult
    func send(_ message: PhoneMessage, requireReachable: Bool = true) -> Bool {
        guard let s = session, s.activationState == .activated, let dict = Wire.encode(message) else { return false }
        if s.isReachable {
            s.sendMessage(dict, replyHandler: nil, errorHandler: { _ in
                // Rezerwowa, gwarantowana dostawa; duplikaty odrzuca odbiorca.
                if !requireReachable { s.transferUserInfo(dict) }
            })
            return true
        }
        if !requireReachable { s.transferUserInfo(dict); return true }
        return false
    }

    private func refresh(_ s: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = s.isReachable
            #if os(iOS)
            self.isPaired = s.isPaired
            self.isWatchAppInstalled = s.isWatchAppInstalled
            #endif
        }
    }

    private func deliver(_ dict: [String: Any]) {
        guard let m = Wire.decode(WatchMessage.self, from: dict) else { return }
        DispatchQueue.main.async { self.onMessage?(m) }
    }

    func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) { refresh(s) }
    func sessionReachabilityDidChange(_ s: WCSession) { refresh(s) }
    func sessionWatchStateDidChange(_ s: WCSession) { refresh(s) }
    func sessionDidBecomeInactive(_ s: WCSession) { refresh(s) }
    func sessionDidDeactivate(_ s: WCSession) { s.activate() }
    func session(_ s: WCSession, didReceiveMessage message: [String: Any]) { deliver(message) }
    func session(_ s: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { deliver(userInfo) }
}
