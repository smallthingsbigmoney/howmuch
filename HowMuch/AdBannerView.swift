//
//  AdBannerView.swift
//  smallthings, bigmoney.
//
//  Bottom Google AdMob anchored adaptive banner — fills the width and uses the
//  device-optimal height. The container reserves the adaptive height up front
//  and then matches the actually-loaded creative so nothing is clipped.
//
//  ⚠️ Production AdMob IDs are in use. On a REAL device this serves LIVE ads —
//  never tap your own ads (AdMob may suspend the account); register the device
//  as a test device in the AdMob console before testing on hardware.
//

import SwiftUI
import GoogleMobileAds

struct AdBannerView: View {
    let width: CGFloat

    /// Production banner ad unit (live ads).
    private let adUnitID = "ca-app-pub-3084145762115882/9435679499"

    /// Placeholder height until the banner loads; the delegate then reports the
    /// loaded creative's exact height. We must NOT compute the adaptive size
    /// here — at early view-init there's no active window/scene yet, and calling
    /// the SDK sizing function then crashes on a real device. It's computed in
    /// makeUIView instead, where the window is ready.
    @State private var height: CGFloat = 50

    var body: some View {
        BannerRepresentable(adUnitID: adUnitID, width: width, height: $height)
            .frame(width: max(width, 1))
            .frame(height: height)
            .clipped()
    }
}

/// Shared helpers for sizing the banner to the live window.
enum AdBannerLayout {
    /// Anchored adaptive banner — full width, device-optimal height — for the
    /// current orientation and window width.
    static func adaptiveSize(width: CGFloat? = nil) -> AdSize {
        largeAnchoredAdaptiveBanner(width: max(width ?? windowWidth(), 1))
    }

    static func windowWidth() -> CGFloat {
        keyWindow()?.bounds.width ?? UIScreen.main.bounds.width
    }

    /// Required for the banner to lay out and render correctly.
    static func rootViewController() -> UIViewController? {
        keyWindow()?.rootViewController
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first(where: \.isKeyWindow)
    }
}

/// Wraps the SDK's UIKit `BannerView` for SwiftUI, reporting the loaded height.
private struct BannerRepresentable: UIViewRepresentable {
    let adUnitID: String
    let width: CGFloat
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> BannerView {
        let adSize = AdBannerLayout.adaptiveSize(width: width)
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.rootViewController = AdBannerLayout.rootViewController()
        banner.delegate = context.coordinator
        context.coordinator.requestAdIfReady(for: banner, adSize: adSize)
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        let rootViewController = AdBannerLayout.rootViewController()
        if banner.rootViewController !== rootViewController {
            banner.rootViewController = rootViewController
        }

        let adSize = AdBannerLayout.adaptiveSize(width: width)
        context.coordinator.requestAdIfNeeded(for: banner, adSize: adSize)
    }

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var height: CGFloat
        private var didRequestAd = false
        private var requestedWidth: CGFloat = 0

        init(height: Binding<CGFloat>) { _height = height }

        func requestAdIfReady(for banner: BannerView, adSize: AdSize) {
            guard banner.rootViewController != nil else { return }
            requestedWidth = adSize.size.width
            didRequestAd = true
            banner.load(AdRequestFactory.nonPersonalizedRequest())
        }

        func requestAdIfNeeded(for banner: BannerView, adSize: AdSize) {
            let widthChanged = abs(requestedWidth - adSize.size.width) > 0.5
            guard !didRequestAd || widthChanged else { return }

            banner.adSize = adSize
            requestAdIfReady(for: banner, adSize: adSize)
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            // Match the SwiftUI frame to the actually-loaded creative.
            height = bannerView.adSize.size.height
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            // Most common on a brand-new production unit: "no fill" (code 3) —
            // the unit simply isn't serving yet. Logged only in development.
            #if DEBUG
            print("⚠️ AdMob banner failed to load:", error.localizedDescription)
            #endif
        }
    }
}

enum AdRequestFactory {
    static func nonPersonalizedRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }
}
