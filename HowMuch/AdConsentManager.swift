//
//  AdConsentManager.swift
//  smallthings, bigmoney.
//
//  Keeps Google UMP consent state in sync before ad requests are made.
//

import Foundation
import UserMessagingPlatform

@MainActor
final class AdConsentManager: ObservableObject {
    static let shared = AdConsentManager()

    @Published private(set) var canRequestAds = false
    @Published private(set) var privacyOptionsRequired = false

    private var isRefreshing = false
    private var didRefreshThisLaunch = false

    private init() {}

    func refreshForCurrentLaunch() {
        guard !didRefreshThisLaunch, !isRefreshing else { return }
        didRefreshThisLaunch = true
        isRefreshing = true

        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.finishRefresh(debugError: error)
                    return
                }

                do {
                    try await ConsentForm.loadAndPresentIfRequired(from: nil)
                    self.finishRefresh(debugError: nil)
                } catch {
                    self.finishRefresh(debugError: error)
                }
            }
        }
    }

    func presentPrivacyOptions() {
        Task { @MainActor in
            do {
                try await ConsentForm.presentPrivacyOptionsForm(from: nil)
                finishRefresh(debugError: nil)
            } catch {
                finishRefresh(debugError: error)
            }
        }
    }

    private func finishRefresh(debugError: Error?) {
        #if DEBUG
        if let debugError {
            print("Ad consent update failed:", debugError.localizedDescription)
        }
        #endif

        canRequestAds = ConsentInformation.shared.canRequestAds
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        isRefreshing = false
    }
}
