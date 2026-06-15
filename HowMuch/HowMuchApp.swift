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

/// Lets individual screens restrict device orientation (onboarding = portrait
/// only; dashboard = all). The mask is consulted by the system on every rotate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Initialize AdMob here — NOT in App.init(), which runs before the app
        // is fully set up and crashed on device during launch bundle resolution.
        MobileAds.shared.start(completionHandler: nil)
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

enum OrientationLock {
    /// Sets the allowed orientations and rotates to match right away.
    static func set(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var adConsent: AdConsentManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var isLocked = false
    @State private var authInFlight = false

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
                refreshAdConsentIfReady()
            }
        }
        .onChange(of: model.hasOnboarded) { _, _ in
            refreshAdConsentIfReady()
        }
        .onChange(of: isLocked) { _, locked in
            if !locked { refreshAdConsentIfReady() }
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
            default:
                break
            }
        }
    }

    private func refreshAdConsentIfReady() {
        guard model.hasOnboarded, !isLocked else { return }
        adConsent.refreshForCurrentLaunch()
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
