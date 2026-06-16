//
//  OnboardingView.swift
//  smallthings, bigmoney.
//
//  Screen 1 — Pure black, typewriter headline, then a staged reveal:
//  sub copy → live demo counter (average worker) → ticker preview + CTA.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    private let headline = "당신의 시간,\n지금 얼마를 벌고 있을까요?"

    /// 대한민국 근로자 평균 총급여 4,332만 원 (국세청 2023년 귀속 연말정산 통계),
    /// 주 5일 · 09–18시 근무 기준 (기본 설정값과 동일).
    private static let averageYearlySalary: Double = 43_320_000

    /// Single source of truth: the SAME engine that drives the preview ticker,
    /// so the counter's per-second rate matches the ticker's "1초" value exactly.
    private var averagePerSecond: Double { demoEngine.perSecond }

    @State private var visibleCount = 0
    @State private var showSubtitles = false
    @State private var showCounter = false
    @State private var showFooter = false
    @State private var demoStart: Date?
    @State private var showSettings = false
    @State private var typingTimer: Timer?

    /// Demo engine that drives the preview ticker at the bottom.
    private var demoEngine: EarningsEngine {
        var settings = UserSettings()
        settings.salaryAmount = Self.averageYearlySalary
        return EarningsEngine(settings: settings)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Typewriter headline + staged sub copy.
                // The invisible full text reserves the final layout size
                // so the headline doesn't shift vertically while typing.
                VStack(spacing: 14) {
                    ZStack {
                        Text(headline)
                            .opacity(0)
                        Text(String(headline.prefix(visibleCount)))
                            .foregroundStyle(.white)
                    }
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                    VStack(spacing: 4) {
                        Text("출근한 순간부터 1초도 빠짐없이,")
                        Text("그 시간이 돈이 되고 있어요.")
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .opacity(showSubtitles ? 1 : 0)
                }
                .padding(.horizontal, 24)

                // Live demo counter — proof before the pitch, in a card.
                VStack(spacing: 10) {
                    Text("지금 이 화면을 보는 동안,")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)

                    // Recompute every frame so the decimals flutter, matching
                    // the dashboard's live counter.
                    TimelineView(.animation) { context in
                        let earned = demoStart.map {
                            max(context.date.timeIntervalSince($0), 0) * averagePerSecond
                        } ?? 0
                        Text(MoneyFormat.won(earned))
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.money)
                    }

                    (Text("평균 직장인들은\n초당 약 ").foregroundStyle(.secondary)
                     + Text(MoneyFormat.won(averagePerSecond)).foregroundStyle(Color.money).bold()
                     + Text("씩 돈을 쌓고 있어요").foregroundStyle(.secondary))
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)

                    Text("(평균 연봉 4,332만 원 기준)")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .opacity(showCounter ? 1 : 0)

                Spacer()

                // Ticker preview + CTA
                VStack(spacing: 14) {
                    TickerMarquee(engine: demoEngine)

                    Button {
                        showSettings = true
                    } label: {
                        Text("나도 확인해보기")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.money, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 16)
                .opacity(showFooter ? 1 : 0)
            }
        }
        .onAppear {
            startTyping()
        }
        .onDisappear { typingTimer?.invalidate() }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView { saved in
                if saved {
                    model.hasOnboarded = true
                }
            }
        }
    }

    private func startTyping() {
        visibleCount = 0
        showSubtitles = false
        showCounter = false
        showFooter = false
        demoStart = nil
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { timer in
            if visibleCount < headline.count {
                visibleCount += 1
            } else {
                timer.invalidate()
                // Staged reveal after typing completes
                withAnimation(.easeIn(duration: 0.6).delay(0.3)) { showSubtitles = true }
                withAnimation(.easeIn(duration: 0.7).delay(1.0)) { showCounter = true }
                withAnimation(.easeIn(duration: 0.7).delay(1.7)) { showFooter = true }
                // The demo counter starts ticking the moment it becomes visible
                demoStart = Date().addingTimeInterval(1.0)
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppModel())
        .preferredColorScheme(.dark)
}
