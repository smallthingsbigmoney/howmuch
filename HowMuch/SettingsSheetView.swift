//
//  SettingsSheetView.swift
//  smallthings, bigmoney.
//
//  Screen 2 — Native sheet modal with salary / schedule configuration.
//  저장 commits the current draft and closes the sheet.
//

import SwiftUI
import LocalAuthentication

struct SettingsSheetView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var adConsent: AdConsentManager
    @Environment(\.dismiss) private var dismiss

    /// Called on dismissal. `true` when the settings were saved.
    var onComplete: (Bool) -> Void

    init(onComplete: @escaping (Bool) -> Void = { _ in }) {
        self.onComplete = onComplete
    }

    // Local draft state — committed to the model when 저장 is tapped.
    @State private var salaryType: SalaryType = .yearly
    @State private var salaryText: String = ""
    @State private var currency: Currency = .krw
    @State private var workingDays: Set<Weekday> = [.mon, .tue, .wed, .thu, .fri]
    @State private var checkInHour: Int = 9
    @State private var checkInMinute: Int = 0
    @State private var checkOutHour: Int = 18
    @State private var checkOutMinute: Int = 0
    @State private var startDate: Date = UserSettings.defaultStartDate
    @State private var notificationsEnabled: Bool = true
    @State private var showCheckInPicker = false
    @State private var showCheckOutPicker = false
    @State private var showStartDatePicker = false
    @State private var showResetAlert = false
    @State private var showNoAuthAlert = false
    @State private var showMissingSalaryAlert = false
    @State private var showMissingWorkingDayAlert = false

    @State private var salaryFieldFocused = false

    var body: some View {
        NavigationStack {
            Form {
                salarySection
                workScheduleSection
                startDateSection
                notificationSection
                securitySection
                if adConsent.privacyOptionsRequired {
                    adPrivacySection
                }
                actionSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("앱 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        closeAndSave()
                    } label: {
                        Text("저장")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.money)
                    }
                }

            }
        }
        .onAppear(perform: loadDraft)
        .interactiveDismissDisabled(true)
        .alert("초기화", isPresented: $showResetAlert) {
            Button("취소", role: .cancel) {}
            Button("확인", role: .destructive) { resetAll() }
        } message: {
            Text("지금까지 정보를 삭제하고 앱을 초기 상태로 돌립니다.")
        }
        .alert("앱 잠금을 사용할 수 없어요", isPresented: $showNoAuthAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("기기에 Face ID 또는 암호가 설정되어 있지 않아요. 기기 설정에서 먼저 설정한 뒤 다시 시도해 주세요.")
        }
        .alert("금액이 필요해요", isPresented: $showMissingSalaryAlert) {
            Button("확인", role: .cancel) {
                salaryFieldFocused = true
            }
        } message: {
            Text("금액이 없으면 저장할 수 없어요. 급여 금액을 입력해 주세요.")
        }
        .alert("근무 요일이 필요해요", isPresented: $showMissingWorkingDayAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("근무 요일을 하나 이상 선택해 주세요.")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    /// Two tight rows: 급여 형태 picker, then ₩ + amount kept right next to each other.
    private var salarySection: some View {
        Section("급여") {
            Menu {
                Picker("급여 형태", selection: $salaryType) {
                    ForEach(SalaryType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .onChange(of: salaryType) { _, _ in
                    dismissSalaryKeyboard()
                }
            } label: {
                HStack {
                    Text("급여 형태")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(salaryType.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.money)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { dismissSalaryKeyboard() })

            HStack(spacing: 5) {
                // "금액 ₩" — tap to switch currency (₩/$/¥/€)
                Menu {
                    Picker("통화 단위", selection: $currency) {
                        ForEach(Currency.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .onChange(of: currency) { _, _ in
                        dismissSalaryKeyboard()
                    }
                } label: {
                    HStack(spacing: 4) {
                        // Concrete gray — semantic .secondary turns blue inside Menu
                        Text("금액 \(currency.rawValue)")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(.secondaryLabel))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                Spacer()
                AmountTextField(
                    text: $salaryText,
                    isFocused: $salaryFieldFocused,
                    placeholder: "10,000,000"
                )
                .frame(minWidth: 120, maxWidth: 180, minHeight: 24)
            }
            .contentShape(Rectangle())
            .onTapGesture { salaryFieldFocused = true }
        }
    }

    private var workScheduleSection: some View {
        Section("근무 시간") {
            // 1) Weekly working days — horizontal multi-select toggles
            VStack(alignment: .leading, spacing: 8) {
                Text("주간 근무 요일")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Weekday.allCases) { day in
                        dayToggle(day)
                    }
                }
            }
            .padding(.vertical, 2)

            // 2) Check-in / Check-out — collapsed rows, tap to expand wheels.
            //    Daily working hours are derived from this span.
            timeRow(title: "출근 시간", hour: $checkInHour, minute: $checkInMinute, isExpanded: $showCheckInPicker)
            timeRow(title: "퇴근 시간", hour: $checkOutHour, minute: $checkOutMinute, isExpanded: $showCheckOutPicker)
        }
    }

    /// Collapsed row showing "2026년 1월 1일" — tap to reveal the calendar.
    private var startDateSection: some View {
        Section {
            Button {
                dismissSalaryKeyboard()
                withAnimation(.snappy(duration: 0.25)) { showStartDatePicker.toggle() }
            } label: {
                HStack {
                    Text("계산 시작 날짜")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(DateFormat.koreanDate(startDate))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.money)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                        .rotationEffect(.degrees(showStartDatePicker ? 180 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showStartDatePicker {
                DatePicker(
                    "계산 시작 날짜",
                    selection: $startDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ko_KR"))
                .onChange(of: startDate) { _, _ in
                    dismissSalaryKeyboard()
                    // Picking a date closes the calendar
                    withAnimation(.snappy(duration: 0.25)) { showStartDatePicker = false }
                }
            }
        } footer: {
            Text("급여 계산을 시작할 날짜를 선택해 주세요.")
        }
    }

    /// 퇴근 알림 토글 — 닫기 시점에 예약/해제됨.
    private var notificationSection: some View {
        Section {
            Toggle(isOn: notificationsBinding) {
                Text("퇴근 알림")
                    .font(.system(size: 15))
            }
            .tint(Color.money)
        } header: {
            Text("알림")
        } footer: {
            Text("퇴근 \(NotificationScheduler.leadMinutes)분 전, 오늘 번 돈을 확인할 수 있게 알려드려요.")
        }
    }

    /// App lock applies immediately (not tied to 닫기). Turning it ON triggers a
    /// biometric/passcode check right away — that surfaces the iOS Face ID
    /// permission prompt then and there, and confirms the user can unlock.
    private var securitySection: some View {
        Section {
            Toggle(isOn: appLockBinding) {
                Text("앱 잠금")
                    .font(.system(size: 15))
            }
            .tint(Color.money)
        } header: {
            Text("보안")
        } footer: {
            Text("앱을 열 때 Face ID 또는 기기 암호로 잠금을 해제합니다. 켜는 즉시 인증을 한 번 확인해요.")
        }
    }

    private var adPrivacySection: some View {
        Section {
            Button {
                dismissSalaryKeyboard()
                adConsent.presentPrivacyOptions()
            } label: {
                Text("광고 동의 관리")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
            }
        } header: {
            Text("개인정보")
        } footer: {
            Text("광고 개인정보 선택을 다시 확인할 수 있어요.")
        }
    }

    /// Toggling ON authenticates immediately; the lock turns on only on success.
    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { model.settings.appLockEnabled },
            set: { isOn in
                dismissSalaryKeyboard()
                if isOn { enableAppLock() }
                else { model.settings.appLockEnabled = false }
            }
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { isOn in
                dismissSalaryKeyboard()
                notificationsEnabled = isOn
            }
        )
    }

    private func enableAppLock() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            showNoAuthAlert = true // no Face ID / passcode set up on the device
            return
        }
        // Reflect the toggle right away, then confirm with the system prompt.
        model.settings.appLockEnabled = true
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "앱 잠금을 사용하려면 인증이 필요해요.") { success, _ in
            DispatchQueue.main.async {
                if !success { model.settings.appLockEnabled = false } // cancelled/failed → revert
            }
        }
    }

    /// 앱 초기화 — a standard row, red to signal it's destructive.
    private var actionSection: some View {
        Section {
            Button {
                dismissSalaryKeyboard()
                showResetAlert = true
            } label: {
                Text("앱 초기화")
                    .font(.system(size: 15))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Components

    private func dayToggle(_ day: Weekday) -> some View {
        let isOn = workingDays.contains(day)
        return Button {
            dismissSalaryKeyboard()
            withAnimation(.snappy(duration: 0.2)) {
                if isOn { workingDays.remove(day) } else { workingDays.insert(day) }
            }
        } label: {
            Text(day.shortName)
                .font(.system(size: 14, weight: isOn ? .bold : .regular))
                .foregroundStyle(isOn ? .black : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isOn ? Color.money : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    /// Collapsed row showing "09:00" — tap to reveal hour/minute wheels.
    @ViewBuilder
    private func timeRow(title: String,
                         hour: Binding<Int>,
                         minute: Binding<Int>,
                         isExpanded: Binding<Bool>) -> some View {
        Button {
            dismissSalaryKeyboard()
            withAnimation(.snappy(duration: 0.25)) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "%02d:%02d", hour.wrappedValue, minute.wrappedValue))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.money)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if isExpanded.wrappedValue {
            HStack(spacing: 0) {
                Picker(title + " 시", selection: hour) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d시", $0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()

                Picker(title + " 분", selection: minute) {
                    ForEach(0..<60, id: \.self) { Text(String(format: "%02d분", $0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .frame(height: 110)
        }
    }

    // MARK: - Logic

    private var salaryValue: Double {
        Double(salaryText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private func loadDraft() {
        let s = model.settings
        salaryType = s.salaryType
        currency = s.currency
        salaryText = s.salaryAmount > 0 ? Self.groupedDigits(from: String(Int(s.salaryAmount))) : ""
        workingDays = s.workingDays
        checkInHour = s.checkInMinutes / 60
        checkInMinute = s.checkInMinutes % 60
        checkOutHour = s.checkOutMinutes / 60
        checkOutMinute = s.checkOutMinutes % 60
        startDate = s.startDate
        notificationsEnabled = s.notificationsEnabled
    }

    private func closeAndSave() {
        dismissSalaryKeyboard()
        guard salaryValue > 0 else {
            showMissingSalaryAlert = true
            return
        }
        guard !workingDays.isEmpty else {
            showMissingWorkingDayAlert = true
            return
        }

        save()
    }

    private func save() {
        var s = UserSettings()
        s.salaryType = salaryType
        s.currency = currency
        s.salaryAmount = salaryValue
        s.workingDays = workingDays
        s.checkInMinutes = checkInHour * 60 + checkInMinute
        s.checkOutMinutes = checkOutHour * 60 + checkOutMinute
        s.startDate = Calendar.current.startOfDay(for: startDate)
        s.appLockEnabled = model.settings.appLockEnabled // applied live via the toggle
        s.notificationsEnabled = notificationsEnabled
        model.settings = s

        NotificationScheduler.refresh(for: s) {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                onComplete(true)
            }
        }
    }

    private func resetAll() {
        model.resetAll()
        dismiss()
        onComplete(false)
    }

    private func dismissSalaryKeyboard() {
        salaryFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// "10000000" -> "10,000,000" (digits only, comma-grouped)
    fileprivate static func groupedDigits(from text: String) -> String {
        let digits = text.filter(\.isNumber)
        guard let value = Int(digits) else { return "" }
        return value.formatted(.number.grouping(.automatic))
    }
}

private struct AmountTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let placeholder: String

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        context.coordinator.textField = textField
        textField.keyboardType = .numberPad
        textField.textAlignment = .right
        textField.placeholder = placeholder
        textField.textColor = UIColor(Color.money)
        textField.tintColor = UIColor(Color.money)
        textField.font = .monospacedDigitSystemFont(ofSize: 16, weight: .bold)
        textField.adjustsFontSizeToFitWidth = true
        textField.minimumFontSize = 12
        textField.inputAccessoryView = context.coordinator.makeAccessoryToolbar()
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self

        if textField.text != text {
            textField.text = text
        }

        if isFocused, !textField.isFirstResponder {
            DispatchQueue.main.async {
                guard context.coordinator.parent.isFocused else { return }
                textField.becomeFirstResponder()
            }
        } else if !isFocused, textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AmountTextField
        weak var textField: UITextField?

        init(parent: AmountTextField) {
            self.parent = parent
        }

        func makeAccessoryToolbar() -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            toolbar.items = [
                UIBarButtonItem.flexibleSpace(),
                UIBarButtonItem(title: "완료", style: .done, target: self, action: #selector(doneTapped))
            ]
            return toolbar
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }

        @objc func textDidChange(_ textField: UITextField) {
            let formatted = SettingsSheetView.groupedDigits(from: textField.text ?? "")
            if textField.text != formatted {
                textField.text = formatted
            }
            parent.text = formatted
        }

        @objc private func doneTapped() {
            parent.isFocused = false
            textField?.resignFirstResponder()
        }
    }
}

#Preview {
    SettingsSheetView()
        .environmentObject(AppModel())
        .preferredColorScheme(.dark)
}
