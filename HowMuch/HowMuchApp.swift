//
//  HowMuchApp.swift
//  smallthings, bigmoney.
//
//  App entry point. Routes between Onboarding and Dashboard,
//  and gates the whole app behind Face ID / device passcode
//  when 앱 잠금 is enabled.
//  Requires iOS 17+.
//

import SwiftUI
import LocalAuthentication
import GoogleMobileAds

@main
struct HowMuchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var adConsent = AdConsentManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(adConsent)
                .preferredColorScheme(.dark) // High-end, high-contrast dark aesthetic
        }
    }
}

/// Keeps the app portrait-first. iPad review can run iPhone apps in compatibility
/// mode, where landscape made the dashboard easy to crop.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // AdMob starts after ATT has had a chance to appear.
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var adConsent: AdConsentManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var isLocked = false
    @State private var authInFlight = false
    @State private var adsStarted = false
    @State private var adsStartInFlight = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.hasOnboarded {
                DashboardView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }

            if isLocked {
                LockView(onUnlockTap: attemptUnlock)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: model.hasOnboarded)
        .animation(.easeInOut(duration: 0.25), value: isLocked)
        .onAppear {
            // Keep the screen awake while the live counter is on display
            UIApplication.shared.isIdleTimerDisabled = true
            // Keep the pre-checkout reminder in sync (no prompt if undecided).
            NotificationScheduler.rescheduleIfAuthorized(for: model.settings)
            if model.settings.appLockEnabled {
                isLocked = true
                attemptUnlock()
            } else {
                prepareAdsIfReady()
            }
        }
        .onChange(of: model.hasOnboarded) { _, _ in
            prepareAdsIfReady()
        }
        .onChange(of: isLocked) { _, locked in
            if !locked { prepareAdsIfReady() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                UIApplication.shared.isIdleTimerDisabled = false
                // Re-lock whenever the app leaves the foreground
                if model.settings.appLockEnabled { isLocked = true }
            case .active:
                UIApplication.shared.isIdleTimerDisabled = true
                if isLocked { attemptUnlock() }
                if !isLocked { prepareAdsIfReady() }
            default:
                break
            }
        }
    }

    private func prepareAdsIfReady() {
        guard model.hasOnboarded, !isLocked, !adsStarted, !adsStartInFlight else { return }
        guard TrackingAuthorization.canStartFlowNow else { return }
        adsStartInFlight = true

        TrackingAuthorization.requestIfNeeded {
            MobileAds.shared.start { _ in
                DispatchQueue.main.async {
                    adsStarted = true
                    adsStartInFlight = false
                    adConsent.refreshForCurrentLaunch()
                }
            }
        }
    }

    private func attemptUnlock() {
        guard !authInFlight else { return }

        let context = LAContext()
        var error: NSError?
        // Device has no passcode at all — locking is impossible, let the user in.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return
        }

        authInFlight = true
        context.evaluatePolicy(
            .deviceOwnerAuthentication, // Face ID / Touch ID, falls back to passcode
            localizedReason: "연봉 정보를 보호하기 위해 잠금을 해제합니다."
        ) { success, _ in
            DispatchQueue.main.async {
                authInFlight = false
                if success { isLocked = false }
            }
        }
    }
}

/// Full-screen cover shown while the app is locked.
struct LockView: View {
    var onUnlockTap: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.money)

                Text("철통 보안! 누가 훔쳐보지 못하게 잠겨 있어요.\n아무도 없는 곳에서 열어보세요!")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 28)

                Button(action: onUnlockTap) {
                    Text("잠금 해제")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color.money, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
