//
//  TrackingAuthorization.swift
//  smallthings, bigmoney.
//
//  Thin wrapper around App Tracking Transparency. The system shows the prompt
//  only once while the status is .notDetermined, and only while the app is
//  active, so ad SDK startup waits until this flow has settled.
//

import AppTrackingTransparency
import Foundation
import UIKit

enum TrackingAuthorization {
    static var canStartFlowNow: Bool {
        let key = "NSUserTrackingUsageDescription"
        guard Bundle.main.object(forInfoDictionaryKey: key) != nil,
              ATTrackingManager.trackingAuthorizationStatus == .notDetermined
        else { return true }

        return UIApplication.shared.applicationState == .active
    }

    /// Runs `completion` on the main thread after the ATT state is settled.
    /// Calling the ATT API without an Info.plist usage string crashes the app,
    /// so this safely no-ops if the string is missing.
    static func requestIfNeeded(completion: @escaping () -> Void) {
        let key = "NSUserTrackingUsageDescription"
        guard Bundle.main.object(forInfoDictionaryKey: key) != nil else {
            DispatchQueue.main.async { completion() }
            return
        }

        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            DispatchQueue.main.async { completion() }
            return
        }

        guard UIApplication.shared.applicationState == .active else { return }

        ATTrackingManager.requestTrackingAuthorization { _ in
            DispatchQueue.main.async { completion() }
        }
    }
}
