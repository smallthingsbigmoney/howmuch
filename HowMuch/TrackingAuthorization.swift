//
//  TrackingAuthorization.swift
//  smallthings, bigmoney.
//
//  Thin wrapper around App Tracking Transparency. The system shows the prompt
//  only once (while the status is .notDetermined) and only while the app is
//  active, so it's safe to call this after the user saves their settings.
//

import AppTrackingTransparency
import Foundation

enum TrackingAuthorization {
    /// Presents the ATT prompt if the user hasn't decided yet; otherwise no-op.
    /// Calling the ATT API without an `NSUserTrackingUsageDescription` string in
    /// Info.plist crashes the app, so we no-op when that string is missing.
    static func request() {
        let key = "NSUserTrackingUsageDescription"
        guard Bundle.main.object(forInfoDictionaryKey: key) != nil else { return }
        ATTrackingManager.requestTrackingAuthorization { _ in }
    }
}
