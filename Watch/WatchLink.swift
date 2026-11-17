import Foundation
import WatchConnectivity

/// Warstwa WCSession po stronie zegarka.
final class WatchLink: NSObject, WCSessionDelegate {
    var onMessage: ((PhoneMessage) -> Void)?
    var onReachability: ((Bool) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var isReachable: Bool { WCSession.isSupported() && WCSession.default.isReachable }

    /// `guaranteed`: gdy sendMessage zawiedzie, wysyła przez transferUserInfo (iPhone odrzuca duplikaty).
    func send(_ message: WatchMessage, guaranteed: Bool) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let dict = Wire.encode(message) else { return }
        let s = WCSession.default
        if s.isReachable {
            s.sendMessage(dict, replyHandler: nil, errorHandler: { _ in
                if guaranteed { s.transferUserInfo(dict) }
            })
        } else if guaranteed {
            s.transferUserInfo(dict)
        }
    }

    private func deliver(_ dict: [String: Any]) {
        guard let m = Wire.decode(PhoneMessage.self, from: dict) else { return }
        DispatchQueue.main.async { self.onMessage?(m) }
    }

    func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.onReachability?(s.isReachable) }
    }
    func sessionReachabilityDidChange(_ s: WCSession) { DispatchQueue.main.async { self.onReachability?(s.isReachable) } }
    func session(_ s: WCSession, didReceiveMessage message: [String: Any]) { deliver(message) }
    func session(_ s: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { deliver(userInfo) }
}
