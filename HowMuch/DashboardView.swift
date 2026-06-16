//
//  DashboardView.swift
//  smallthings, bigmoney.
//
//  Screen 3 — Live earnings dashboard with a 1-second tick,
//  rolling-number hero counter (tap to cycle 오늘/이번 주/이번 달/올해),
//  and a seamless, drag-scrollable ticker marquee.
//

import SwiftUI
import UIKit

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var adConsent: AdConsentManager

    @State private var now: Date = .now
    @State private var showSettings = false
    @State private var scope: PeriodScope = .today
    @State private var dashboardMode: DashboardMode = .earnings

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var engine: EarningsEngine { model.engine }
    private var symbol: String { model.settings.currency.rawValue }

    private enum DashboardMode {
        case earnings
        case countdown
    }

    private struct CountdownState {
        let title: String
        let target: Date
        let currentTimeColor: Color
    }

    private struct DashboardLayout {
        let size: CGSize
        let isPad: Bool
        let safeAreaInsets: EdgeInsets

        var isLandscape: Bool { size.width > size.height }
        var isCompactPadWindow: Bool { isPad && isLandscape && size.width < 1_100 }

        var frameWidth: CGFloat { max(size.width, 1) }

        var leadingPadding: CGFloat {
            if isCompactPadWindow { return max(92, safeAreaInsets.leading + 44) }
            return 16
        }

        var trailingPadding: CGFloat {
            return 16
        }

        var horizontalPadding: CGFloat { max(leadingPadding, trailingPadding) }

        var heroSidePadding: CGFloat {
            if isCompactPadWindow { return 24 }
            return 16
        }

        var heroMaxWidth: CGFloat {
            let available = max(frameWidth - heroSidePadding * 2, 240)
            if isCompactPadWindow { return min(available, 620) }
            if isPad { return min(available, isLandscape ? 820 : 720) }
            return available
        }

        var heroAmountFontSize: CGFloat {
            if isCompactPadWindow { return min(64, max(46, heroMaxWidth * 0.1)) }
            if isPad { return min(isLandscape ? 84 : 82, max(56, heroMaxWidth * 0.105)) }
            if isLandscape { return min(70, max(44, size.height * 0.16)) }
            return min(56, max(42, size.width * 0.13))
        }

        var heroSpacing: CGFloat { isLandscape ? 10 : 16 }
        var topPadding: CGFloat {
            if isCompactPadWindow { return max(48, safeAreaInsets.top + 20) }
            if isPad { return max(isLandscape ? 18 : 16, safeAreaInsets.top + 10) }
            return isLandscape ? 8 : 12
        }
        var topBarBottomPadding: CGFloat { isLandscape ? 4 : 8 }
    }

    var body: some View {
        GeometryReader { geo in
            let layout = DashboardLayout(
                size: geo.size,
                isPad: UIDevice.current.userInterfaceIdiom == .pad,
                safeAreaInsets: geo.safeAreaInsets
            )

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar(layout: layout)

                    heroSection(layout: layout)
                        .frame(width: layout.frameWidth)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .clipped()

                    TickerMarquee(
                        engine: engine,
                        mode: dashboardMode == .countdown ? .remainingWork : .earnings
                    )
                    .frame(width: layout.frameWidth)

                    if adConsent.canRequestAds {
                        AdBannerView(width: layout.frameWidth)
                            .frame(width: layout.frameWidth)
                    }
                }
                .frame(width: layout.frameWidth, height: geo.size.height, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(tick) {
            now = $0
            if dashboardMode == .countdown && countdownState(at: $0) == nil {
                dashboardMode = .earnings
            }
        }
        .onAppear {
            dashboardMode = .earnings
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView()
        }
    }

    // MARK: - Top Bar

    private func topBar(layout: DashboardLayout) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(statusText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = statusSubtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                topBarTapped()
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .frame(width: 36, height: 36)
        }
        .frame(width: max(layout.frameWidth - layout.leadingPadding - layout.trailingPadding, 1),
               alignment: .topLeading)
        .padding(.leading, layout.leadingPadding)
        .padding(.trailing, layout.trailingPadding)
        .padding(.top, layout.topPadding)
        .padding(.bottom, layout.topBarBottomPadding)
        .background(Color.black.opacity(0.001))
        .frame(width: layout.frameWidth, alignment: .topLeading)
    }

    /// Small subtitle under the status line.
    private var statusSubtitle: String? {
        switch engine.phase(at: now) {
        case .working(_, let remaining):
            return "퇴근까지 \(DurationFormat.hoursMinutes(remaining)) 남음"
        case .afterWork, .dayOff:
            return nextShiftSubtitle
        default:
            return nil
        }
    }

    /// 다음 출근 안내 — 내일이면 시각("내일 출근은 9시!"), 아니면 요일("다음 출근은 월요일이에요").
    private var nextShiftSubtitle: String? {
        guard let next = engine.nextWorkingDay(after: now) else { return nil }
        if Calendar.current.isDateInTomorrow(next) {
            return "내일 출근은 \(checkInTimeText)!"
        }
        return "다음 출근은 \(DateFormat.relativeWeekday(next))이에요"
    }

    /// 설정된 출근 시각 — "9시" 또는 "9시 30분".
    private var checkInTimeText: String {
        let m = model.settings.checkInMinutes
        let (h, min) = (m / 60, m % 60)
        return min == 0 ? "\(h)시" : "\(h)시 \(min)분"
    }

    private var statusText: String {
        switch engine.phase(at: now) {
        case .dayOff:
            return "오늘은 쉬는 날이에요 🎉"
        case .beforeWork(let startsIn):
            return "출근까지 \(DurationFormat.hoursMinutes(startsIn)) 남음 ☕️"
        case .working(let elapsed, _):
            return "근무 시작 후 \(DurationFormat.hoursMinutes(elapsed))째 돈 버는 중..."
        case .afterWork:
            return "오늘 일 끝! 수고했어요 👏"
        }
    }

    private func topBarTapped() {
        if dashboardMode == .countdown {
            returnToEarnings()
        } else {
            toggleCountdownMode()
        }
    }

    private func toggleCountdownMode() {
        guard countdownState(at: now) != nil else { return }
        withAnimation(.snappy(duration: 0.3)) {
            dashboardMode = dashboardMode == .countdown ? .earnings : .countdown
        }
    }

    // MARK: - Hero

    /// Before check-in, "오늘 벌어온 돈 ₩ 0.00" feels off — show today's
    /// expected earnings instead. Tap-cycling to 이번 주/이번 달/올해 still works.
    private var isBeforeWork: Bool {
        if case .beforeWork = engine.phase(at: now) { return true }
        return false
    }

    private var isPreWorkToday: Bool { scope == .today && isBeforeWork }

    private var isDayOff: Bool {
        if case .dayOff = engine.phase(at: now) { return true }
        return false
    }

    private var isAfterWork: Bool {
        if case .afterWork = engine.phase(at: now) { return true }
        return false
    }

    /// 퇴근 후·쉬는 날의 금액 분해 서브텍스트.
    /// 오늘 퇴근 후: "초당 ₩8.48 × 8시간 동안 벌어온 돈"
    /// 오늘 쉬는 날: "오늘은 근무가 없는 날이에요"
    /// 그 외: "일당 ₩80,522.48 × 5일 동안 벌어온 돈"
    private var heroBreakdown: Text {
        if scope == .today {
            if isDayOff {
                return Text("오늘은 근무가 없는 날이에요").foregroundStyle(.secondary)
            }

            let hours = DurationFormat.hoursMinutesCompact(Double(engine.dailyWorkMinutes * 60))
            return Text("초당 ").foregroundStyle(.secondary)
                + Text(MoneyFormat.won(engine.perSecond, symbol: symbol)).foregroundStyle(Color.money).bold()
                + Text(" × \(hours) 동안 벌어온 돈").foregroundStyle(.secondary)
        } else {
            let days = completedDaysForHeroBreakdown
            return Text("일당 ").foregroundStyle(.secondary)
                + Text(MoneyFormat.won(engine.perDay, symbol: symbol)).foregroundStyle(Color.money).bold()
                + Text(" × \(days)일 동안 벌어온 돈").foregroundStyle(.secondary)
        }
    }

    private var completedDaysForHeroBreakdown: Int {
        let completedDays = engine.completedWorkingDays(scope, at: now)
        let todayCountsAsCompleted = isAfterWork && engine.earnedToday(at: now) > 0
        return completedDays + (todayCountsAsCompleted ? 1 : 0)
    }

    private var heroLabel: String {
        guard isBeforeWork else { return scope.label }
        if scope == .today { return "오늘 벌 예정인 돈" }

        let days = engine.completedWorkingDays(scope, at: now)
        guard days > 0 else { return scope.label }
        let period = switch scope {
        case .today: ""
        case .week:  "이번 주"
        case .month: "이번 달"
        case .year:  "올해"
        }
        return "\(period) \(days)일 출근해서 번 돈"
    }

    @ViewBuilder
    private func heroSection(layout: DashboardLayout) -> some View {
        if dashboardMode == .countdown {
            countdownHeroSection(layout: layout)
        } else {
            earningsHeroSection(layout: layout)
        }
    }

    private func earningsHeroSection(layout: DashboardLayout) -> some View {
        VStack(spacing: layout.heroSpacing) {
            Text(heroLabel)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)

            // Recompute every frame (~60fps) so the decimals flutter smoothly
            // while money is live-accruing, rather than ticking once per second.
            // Decimals only while money is live (hidden before work / day off).
            TimelineView(.animation) { context in
                let value = heroAmount(at: context.date)
                Text(MoneyFormat.won(value, symbol: symbol, decimals: showsHeroAmountDecimals))
                    .font(.system(size: layout.heroAmountFontSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.money)
                    .lineLimit(1)
                    .minimumScaleFactor(0.22)
                    .allowsTightening(true)
                    .frame(maxWidth: layout.heroMaxWidth, alignment: .center)
            }

            Group {
                if scope != .today {
                    TimelineView(.animation) { context in
                        Text(purchaseAnalogy(for: heroAmount(at: context.date),
                                             at: context.date,
                                             landscape: layout.isLandscape))
                            .foregroundStyle(.secondary)
                    }
                } else if isDayOff || isAfterWork {
                    heroBreakdown
                } else if isBeforeWork {
                    (Text("출근하면 초당 ").foregroundStyle(.secondary)
                     + Text(MoneyFormat.won(engine.perSecond, symbol: symbol)).foregroundStyle(Color.money).bold()
                     + Text("씩 쌓여요").foregroundStyle(.secondary))
                } else {
                    (Text("초당 ").foregroundStyle(.secondary)
                     + Text(MoneyFormat.won(engine.perSecond, symbol: symbol)).foregroundStyle(Color.money).bold()
                     + Text("씩 돈 버는 중...").foregroundStyle(.secondary))
                }
            }
            .font(.system(size: 17, weight: .regular))
            .lineLimit(layout.isLandscape ? 1 : 2)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .frame(maxWidth: layout.heroMaxWidth)

            // 오늘이 아닌 기간을 볼 때만 노출되는 복귀 버튼.
            // 버튼이 없을 땐 공간을 예약하지 않아, 본문이 상하 중앙에 놓임.
            if scope != .today {
                Button {
                    withAnimation(.snappy(duration: 0.3)) { scope = .today }
                } label: {
                    Label("오늘로 돌아가기", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.money, in: Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, layout.heroSidePadding)
        .frame(width: layout.frameWidth)
        .frame(maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            advanceHero()
        }
    }

    private func heroAmount(at date: Date) -> Double {
        isPreWorkToday ? engine.perDay : engine.earned(scope, at: date)
    }

    private var showsHeroAmountDecimals: Bool {
        scope == .today && !(isBeforeWork || isDayOff)
    }

    private struct PurchaseAnalogy {
        let price: Double
        let name: String
        let unit: String
        let punchline: String
    }

    private struct PurchaseAnalogyTier {
        let minimum: Double
        let messages: [String]
    }

    private static let smallPurchaseAnalogies: [PurchaseAnalogy] = [
        PurchaseAnalogy(price: 1_500, name: "삼각김밥", unit: "개", punchline: "편의점 한 칸은 접수했어요"),
        PurchaseAnalogy(price: 2_000, name: "컵라면", unit: "개", punchline: "야근 냄새가 살짝 나요"),
        PurchaseAnalogy(price: 4_500, name: "아메리카노", unit: "잔", punchline: "카페인 통장 충전 중"),
        PurchaseAnalogy(price: 5_500, name: "편의점 도시락", unit: "개", punchline: "전자레인지 앞에서 당당해져요"),
        PurchaseAnalogy(price: 8_000, name: "떡볶이", unit: "인분", punchline: "매운맛으로 노동을 씻어내요"),
        PurchaseAnalogy(price: 15_000, name: "영화표", unit: "장", punchline: "팝콘은 다음 탭에 맡겨요"),
        PurchaseAnalogy(price: 16_000, name: "책", unit: "권", punchline: "지식도 할부 없이 갑니다"),
        PurchaseAnalogy(price: 23_000, name: "치킨", unit: "마리", punchline: "퇴근길 명분은 충분해요"),
        PurchaseAnalogy(price: 30_000, name: "피자", unit: "판", punchline: "반반 선택권이 생겼어요"),
        PurchaseAnalogy(price: 80_000, name: "운동화", unit: "켤레", punchline: "출근길 발걸음이 조금 가벼워져요"),
    ]

    private static let purchaseAnalogyTiers: [PurchaseAnalogyTier] = [
        PurchaseAnalogyTier(minimum: 100_000_000, messages: [
            "억 단위가 되면 장바구니가 아니라 인생 계획표가 열려요.\n숫자가 갑자기 어른스러워졌어요",
            "이쯤 되면 사고 싶은 물건보다 살고 싶은 방식이 먼저 떠올라요.\n통장이 회의를 소집합니다",
            "가격표보다 계약서가 먼저 떠오르는 구간이에요.\n계산기도 말수가 줄었어요",
            "통장 앱이 숫자를 다시 확인하게 만드는 금액이에요.\n쉼표가 존재감을 드러냅니다",
            "검색창보다 계산기가 더 진지해지는 돈이에요.\n오늘은 숫자가 무겁습니다",
            "목표라는 단어가 현실 쪽으로 걸어와요.\n괜히 자세를 고쳐 앉게 됩니다",
        ]),
        PurchaseAnalogyTier(minimum: 50_000_000, messages: [
            "차 한 대를 고르는 상상이 꽤 구체적이에요.\n옵션표가 갑자기 말을 겁니다",
            "전세 보증금이라는 단어가 멀리서 손을 흔들어요.\n숫자가 생활 쪽으로 다가왔습니다",
            "큰 결정 앞에서 한 번 숨 고르게 되는 돈이에요.\n장바구니보단 메모장이 어울립니다",
            "가볍게 넘길 금액은 확실히 아니에요.\n통장도 목소리를 낮춥니다",
        ]),
        PurchaseAnalogyTier(minimum: 30_000_000, messages: [
            "차 견적서가 제법 자연스럽게 열리는 금액이에요.\n색상 고민까지는 무료입니다",
            "긴 여행이 아니라 삶의 속도를 바꾸는 돈이에요.\n달력보다 계획표가 먼저 열려요",
            "큰 가전 몇 개가 아니라 집 분위기가 바뀌는 금액이에요.\n공간이 먼저 설렙니다",
            "숫자가 커지니 소비보다 선택지가 먼저 보여요.\n이건 꽤 기분 좋은 무게감이에요",
        ]),
        PurchaseAnalogyTier(minimum: 10_000_000, messages: [
            "중고차 검색창이 슬쩍 현실로 내려오는 금액이에요.\n손가락은 아직 침착한 척",
            "가전 매장 한 바퀴가 진지해지는 돈이에요.\n냉장고도 눈치를 봅니다",
            "큰 여행 계획이 슬쩍 현실로 내려왔어요.\n달력 앱이 바빠질 차례",
            "견적서가 말을 걸기 시작하는 금액이에요.\n통장은 오늘 꽤 당당해요",
            "가족 식사 한 번이 아니라 가족회의 안건이 되는 돈이에요.\n메뉴판 밖으로 나왔습니다",
        ]),
        PurchaseAnalogyTier(minimum: 5_000_000, messages: [
            "프리미엄 가전 하나는 당당히 고를 수 있는 돈이에요.\n후기 정독 모드 진입",
            "여행지가 가까운 곳에서 먼 곳으로 바뀌는 금액이에요.\n여권이 살짝 들뜹니다",
            "노트북과 주변기기까지 한 번에 상상되는 돈이에요.\n책상이 미래를 봅니다",
            "큰 결제 앞에서도 손이 덜 떨리는 구간이에요.\n멋진 척하기 딱 좋아요",
        ]),
        PurchaseAnalogyTier(minimum: 3_000_000, messages: [
            "노트북에 모니터까지 고민되는 돈이에요.\n책상이 갑자기 좁아 보여요",
            "이사 비용이라는 단어가 현실감을 얻었어요.\n박스부터 사면 안 됩니다",
            "주말 여행이 아니라 꽤 큰 여행이 보여요.\n연차 달력이 반짝입니다",
            "가전 하나는 당당히 데려올 수 있어요.\n장바구니가 자세를 고쳐 앉았어요",
            "운동 장비보다 운동할 마음까지 살 수 있을 것 같아요.\n문제는 내일의 나",
        ]),
        PurchaseAnalogyTier(minimum: 1_000_000, messages: [
            "프리미엄 노트북이 장바구니에서 손을 흔들어요.\n아직은 눈싸움 중",
            "최신 스마트폰이 꽤 현실적인 금액이에요.\n케이스 색부터 고르면 위험합니다",
            "월세나 관리비가 떠오르는 묵직한 돈이에요.\n생활감이 갑자기 선명해져요",
            "작은 호캉스가 아니라 제대로 쉬는 계획이에요.\n침대가 먼저 초대장을 보냅니다",
            "취미 하나쯤은 꽤 진지하게 시작할 수 있어요.\n장비부터 사면 안 됩니다",
            "고장 난 물건 교체가 아니라 업그레이드가 보이는 돈이에요.\n눈높이가 올라갑니다",
        ]),
        PurchaseAnalogyTier(minimum: 500_000, messages: [
            "로봇청소기에게 바닥을 맡길 수 있는 돈이에요.\n청소는 점점 협상 대상",
            "괜찮은 헤드폰과 여유가 같이 보이는 금액이에요.\n소음 차단 예산 확보",
            "주말을 꽤 그럴듯하게 바꿀 수 있어요.\n집 밖 공기가 후보에 올랐습니다",
            "가방 하나쯤은 진지하게 비교하게 되는 돈이에요.\n후기 정독 모드 진입",
            "고급 의자 하나가 허리를 설득하는 금액이에요.\n자세가 갑자기 중요해집니다",
        ]),
        PurchaseAnalogyTier(minimum: 100_000, messages: [
            "장바구니 무료배송 문턱은 가볍게 넘겼어요.\n이제 마음의 문턱이 문제",
            "괜찮은 운동화가 시야에 들어오는 금액이에요.\n출근길 핑계가 생겼습니다",
            "맛있는 저녁을 꽤 자신 있게 고를 수 있어요.\n메뉴판 앞에서 덜 작아져요",
            "필요했던 물건 하나는 해결 가능한 돈이에요.\n핑계보다 결제가 빨라질 수 있어요",
            "마트 계산대 앞에서 덜 놀랄 수 있는 금액이에요.\n장바구니가 조금 당당합니다",
            "선물 하나 고를 때 예산부터 숨지 않아도 돼요.\n마음이 살짝 넓어집니다",
        ]),
    ]

    private func purchaseAnalogy(for amount: Double, at date: Date, landscape: Bool) -> String {
        guard model.settings.currency == .krw else {
            return landscape ? "이 금액도 차곡차곡 쌓이는 중..." : "이 금액도\n차곡차곡 쌓이는 중..."
        }

        let value = max(amount, 0)
        guard let cheapest = Self.smallPurchaseAnalogies.first,
              value >= cheapest.price else {
            let remaining = max((Self.smallPurchaseAnalogies.first?.price ?? 1_500) - value, 0)
            let line = "삼각김밥 하나까지 \(MoneyFormat.won(remaining, symbol: symbol, decimals: false)) 남았어요"
            return line
        }

        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        let seed = abs(day + scope.rawValue * 7)

        if let tier = Self.purchaseAnalogyTiers.first(where: { value >= $0.minimum }) {
            let message = tier.messages[seed % tier.messages.count]
            return landscape ? message.replacingOccurrences(of: "\n", with: " ") : message
        }

        let candidates = Self.smallPurchaseAnalogies.filter {
            value >= $0.price && Int(value / $0.price) <= 8
        }
        let fallbackCandidates = Self.smallPurchaseAnalogies.filter { value >= $0.price }
        let pool = candidates.isEmpty ? fallbackCandidates : candidates
        guard !pool.isEmpty else {
            return landscape ? "이 금액도 차곡차곡 쌓이는 중..." : "이 금액도\n차곡차곡 쌓이는 중..."
        }

        let item = pool[seed % pool.count]
        let count = max(1, Int(value / item.price))
        let lead = "이 돈이면 \(item.name) \(count.formatted(.number))\(item.unit)쯤."
        return landscape ? "\(lead) \(item.punchline)" : "\(lead)\n\(item.punchline)"
    }

    private func advanceHero() {
        withAnimation(.snappy(duration: 0.3)) {
            if scope == .year, countdownState(at: now) != nil {
                dashboardMode = .countdown
                return
            }

            let next = scope.next
            scope = next
        }
    }

    private func countdownHeroSection(layout: DashboardLayout) -> some View {
        VStack(spacing: layout.heroSpacing) {
            TimelineView(.animation) { context in
                if let state = countdownState(at: context.date) {
                    VStack(spacing: layout.heroSpacing) {
                        Text(state.title)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)

                        Text(DurationFormat.clockCountdown(state.target.timeIntervalSince(context.date)))
                            .font(.system(size: layout.heroAmountFontSize, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.timeAccent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.22)
                            .allowsTightening(true)
                            .frame(maxWidth: layout.heroMaxWidth, alignment: .center)
                            .contentTransition(.numericText())

                        Text("현재 시간 \(DateFormat.clockTime(context.date))")
                            .font(.system(size: 17, weight: .regular).monospacedDigit())
                            .foregroundStyle(state.currentTimeColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: layout.heroMaxWidth)
                    }
                }
            }

            Button {
                returnToEarnings()
            } label: {
                Label("지금 얼마!?로 돌아가기", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.timeAccent, in: Capsule())
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
        .padding(.horizontal, layout.heroSidePadding)
        .frame(width: layout.frameWidth)
        .frame(maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            returnToEarnings()
        }
    }

    private func returnToEarnings() {
        withAnimation(.snappy(duration: 0.3)) {
            dashboardMode = .earnings
            scope = .today
        }
    }

    private func countdownState(at date: Date) -> CountdownState? {
        switch engine.phase(at: date) {
        case .beforeWork(let startsIn):
            return CountdownState(
                title: "다음 출근까지",
                target: date.addingTimeInterval(startsIn),
                currentTimeColor: .white.opacity(0.9)
            )
        case .working(_, let remaining):
            return CountdownState(
                title: "오늘 퇴근까지 남은 시간",
                target: date.addingTimeInterval(remaining),
                currentTimeColor: .secondary
            )
        case .afterWork, .dayOff:
            guard let next = engine.nextWorkingDay(after: date) else { return nil }
            return CountdownState(
                title: "다음 출근까지",
                target: engine.checkIn(on: next),
                currentTimeColor: .white.opacity(0.9)
            )
        }
    }

}

// MARK: - Ticker Marquee

/// Horizontal auto-scrolling ticker (Apple Stocks style).
/// The content repeats enough times to cover any screen width (no gaps,
/// even in landscape), wraps seamlessly via modulo offset, and can be
/// dragged freely — auto-scroll resumes from wherever the drag leaves it.
struct TickerMarquee: View {
    let engine: EarningsEngine
    var mode: Mode = .earnings

    enum Mode {
        case earnings
        case remainingWork
    }

    @State private var contentWidth: CGFloat = 0
    @State private var dragAccumulated: CGFloat = 0
    @GestureState private var dragCurrent: CGFloat = 0

    private var earningsItems: [(label: String, value: Double)] {
        [
            ("1초",   engine.perSecond),
            ("1분",   engine.perMinute),
            ("1시간", engine.perHour),
            ("하루",  engine.perDay),
            ("1주",   engine.perWeek),
            ("1달",   engine.perMonth),
            ("1년",   engine.perYear),
        ]
    }

    var body: some View {
        GeometryReader { container in
            TimelineView(.animation) { timeline in
                let speed: CGFloat = 35 // points per second
                let t = CGFloat(timeline.date.timeIntervalSinceReferenceDate)

                // Enough copies that the strip always covers the full width.
                let copies = contentWidth > 0
                    ? max(2, Int((container.size.width / contentWidth).rounded(.up)) + 1)
                    : 2

                // Auto-scroll minus drag, wrapped into [0, contentWidth).
                let raw = t * speed - dragAccumulated - dragCurrent
                let offset = contentWidth > 0
                    ? ((raw.truncatingRemainder(dividingBy: contentWidth)) + contentWidth)
                        .truncatingRemainder(dividingBy: contentWidth)
                    : 0

                HStack(spacing: 0) {
                    measuredContent(at: timeline.date)
                    ForEach(1..<copies, id: \.self) { _ in
                        tickerContent(at: timeline.date)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: -offset)
                .frame(width: container.size.width,
                       height: container.size.height,
                       alignment: .leading)
            }
        }
        .frame(height: 48)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($dragCurrent) { value, state, _ in
                    state = value.translation.width
                }
                .onEnded { value in
                    dragAccumulated += value.translation.width
                }
        )
        .overlay(alignment: .top) { Divider().background(.white.opacity(0.1)) }
    }

    /// First copy carries the width measurement; re-measures when digits change.
    private func measuredContent(at date: Date) -> some View {
        tickerContent(at: date).background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { contentWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in
                        contentWidth = newWidth
                    }
            }
        )
    }

    @ViewBuilder
    private func tickerContent(at date: Date) -> some View {
        switch mode {
        case .earnings:
            earningsTickerContent
        case .remainingWork:
            remainingWorkTickerContent(at: date)
        }
    }

    private var earningsTickerContent: some View {
        HStack(spacing: 0) {
            ForEach(earningsItems, id: \.label) { item in
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(MoneyFormat.won(item.value,
                                         symbol: engine.settings.currency.rawValue,
                                         decimals: item.value < 1000))
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.money)
                }
                .padding(.horizontal, 14)

                Text("|")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.15))
            }
        }
    }

    private func remainingWorkTickerContent(at date: Date) -> some View {
        let items = remainingWorkItems(at: date)

        return HStack(spacing: 0) {
            ForEach(items, id: \.label) { item in
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.timeAccent)
                    Text(item.suffix)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)

                Text("|")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.15))
            }
        }
    }

    private func remainingWorkItems(at date: Date) -> [(label: String, value: String, suffix: String)] {
        [
            dailyRemainingWorkItem(at: date),
            (
                "이번 주 근무",
                DurationFormat.hoursMinutesCompact(engine.remainingWorkSecondsThisWeek(at: date)),
                "남음"
            ),
            (
                "이번 달 근무",
                DurationFormat.hoursMinutesCompact(engine.remainingWorkSecondsThisMonth(at: date)),
                "남음"
            ),
            (
                "이번 달 근무일",
                "\(engine.remainingWorkingDaysThisMonth(at: date))일",
                "남음"
            ),
        ]
    }

    private func dailyRemainingWorkItem(at date: Date) -> (label: String, value: String, suffix: String) {
        switch engine.phase(at: date) {
        case .beforeWork:
            let seconds = engine.remainingWorkSeconds(on: date, at: date)
            return ("오늘 근무", DurationFormat.hoursMinutesCompact(seconds), "남음")
        case .working(_, let remaining):
            return ("오늘 근무", DurationFormat.hoursMinutesCompact(remaining), "남음")
        case .afterWork, .dayOff:
            guard let next = engine.nextWorkingDay(after: date) else {
                return ("다음 근무", "0분", "예정")
            }
            let seconds = engine.remainingWorkSeconds(
                on: next,
                at: Calendar.current.startOfDay(for: next)
            )
            return ("다음 근무", DurationFormat.hoursMinutesCompact(seconds), "예정")
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppModel())
        .preferredColorScheme(.dark)
}
