import SwiftUI

/// Landing time (UTC) and required operating duration. Editable only in the original phase;
/// otherwise an explicit "Edit Plan…" asks before discarding the comparison.
struct MissionParametersSection: View {
    @Environment(MissionStore.self) private var store
    @Environment(AppContainer.self) private var container
    @Environment(AppNavigationState.self) private var navigation
    @State private var isEditingStart = false

    var body: some View {
        if let plan = store.committedPlan {
            PanelCard {
                VStack(alignment: .leading, spacing: LunaviSpacing.m) {
                    Text("Landing time (UTC)")
                        .lunaviSectionLabel()
                    startButton(plan)
                    Text("Required operating duration")
                        .lunaviSectionLabel()
                    DurationSelector(
                        selected: plan.durationHours,
                        options: store.durationOptions,
                        isEnabled: store.canEditParameters
                    ) { hours in
                        store.updateDuration(hours)
                    }
                    KeyValueRow("Window", "\(UTCFormat.dayMonthTime(plan.start)) → \(UTCFormat.dayMonthTime(plan.end)) UTC")
                        .accessibilityIdentifier("parameters.window")
                    if !store.canEditParameters {
                        HStack(alignment: .center, spacing: LunaviSpacing.s) {
                            Text("Parameters are locked while a comparison is open.")
                                .font(LunaviTypography.micro)
                                .foregroundStyle(LunaviColors.textMuted)
                            Spacer(minLength: 4)
                            Button("Edit Plan…") {
                                navigation.isEditConfirmationPresented = true
                            }
                            .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                            .accessibilityIdentifier("parameters.editPlan")
                        }
                    }
                }
            }
        }
    }

    private func startButton(_ plan: MissionPlan) -> some View {
        Button {
            isEditingStart = true
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(UTCFormat.dayMonthYear(plan.start))
                        .font(LunaviTypography.measurementLarge)
                        .foregroundStyle(LunaviColors.textPrimary)
                    Text(UTCFormat.timeUTC(plan.start))
                        .font(LunaviTypography.measurement)
                        .foregroundStyle(LunaviColors.selectedTime)
                }
                Spacer()
                if store.canEditParameters {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(LunaviColors.textMuted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!store.canEditParameters)
        .popover(isPresented: $isEditingStart) {
            StartTimeEditor(initial: plan.start, allowedRange: container.selectableStartRange,
                            rangesNote: container.computedRangesDescription) { newValue in
                _ = container.setMissionStart(newValue)
            }
        }
        .accessibilityLabel("Landing time")
        .accessibilityValue(UTCFormat.spoken(plan.start))
        .accessibilityHint(store.canEditParameters ? "Opens the UTC date and time editor." : "Locked while a comparison is open.")
        .accessibilityIdentifier("parameters.landingTime")
    }
}

struct DurationSelector: View {
    let selected: Int
    let options: [Int]
    let isEnabled: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, hours in
                if index > 0 {
                    Hairline(vertical: true)
                        .frame(height: 24)
                }
                Button {
                    onSelect(hours)
                } label: {
                    Text("\(hours) h")
                        .font(LunaviTypography.bodyEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(hours == selected ? LunaviColors.background : LunaviColors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: LunaviSpacing.minimumTouchTarget)
                        .background(hours == selected ? LunaviColors.selectedTime : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(hours) hours")
                .accessibilityAddTraits(hours == selected ? .isSelected : [])
                .accessibilityIdentifier("duration.\(hours)")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall + 2))
        .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall + 2).stroke(LunaviColors.border, lineWidth: 1))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
    }
}

/// UTC date/time editor. The pickers run in UTC regardless of the device time zone.
///
/// Start times are limited to the computed data coverage (`allowedRange`): the app never offers a date
/// for which no scientific data was generated. Without coverage (no data at all) the editor is unrestricted
/// and every result stays Unknown.
struct StartTimeEditor: View {
    let initial: Date
    let allowedRange: ClosedRange<Date>?
    var rangesNote: String? = nil
    let onCommit: (Date) -> Void
    @State private var draft: Date
    @Environment(\.dismiss) private var dismiss

    init(initial: Date, allowedRange: ClosedRange<Date>? = nil, rangesNote: String? = nil, onCommit: @escaping (Date) -> Void) {
        self.initial = initial
        self.allowedRange = allowedRange
        self.rangesNote = rangesNote
        self.onCommit = onCommit
        _draft = State(initialValue: initial)
    }

    private var pickerRange: ClosedRange<Date> {
        allowedRange ?? Date.distantPast...Date.distantFuture
    }

    private func clamped(_ date: Date) -> Date {
        guard let allowedRange else { return date }
        return min(max(date, allowedRange.lowerBound), allowedRange.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.m) {
            Text("Landing time (UTC)")
                .font(LunaviTypography.headline)
                .foregroundStyle(LunaviColors.textPrimary)
            DatePicker("Date", selection: $draft, in: pickerRange, displayedComponents: [.date])
                .datePickerStyle(.graphical)
            HStack {
                Text("Time (UTC)")
                    .font(LunaviTypography.body)
                Spacer()
                DatePicker("Time (UTC)", selection: $draft, in: pickerRange, displayedComponents: [.hourAndMinute])
                    .labelsHidden()
            }
            HStack(spacing: LunaviSpacing.s) {
                step("−1 d", -86_400)
                step("−1 h", -3_600)
                step("+1 h", 3_600)
                step("+1 d", 86_400)
            }
            Text(UTCFormat.full(draft))
                .font(LunaviTypography.measurement)
                .foregroundStyle(LunaviColors.selectedTime)
            if let rangesNote {
                Text(rangesNote)
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("startEditor.ranges")
            } else if let allowedRange {
                Text("Computed data covers \(UTCFormat.full(allowedRange.lowerBound)) – \(UTCFormat.full(allowedRange.upperBound.addingTimeInterval(60))). Later dates need a new pipeline run.")
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("startEditor.coverage")
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                Spacer()
                Button("Apply") {
                    onCommit(draft)
                    dismiss()
                }
                .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                .accessibilityIdentifier("startEditor.apply")
            }
        }
        .padding(LunaviSpacing.xl - 4)
        .frame(width: 360)
        .environment(\.timeZone, UTCFormat.timeZone)
        .environment(\.calendar, UTCFormat.calendar)
        .presentationBackground(LunaviColors.backgroundSecondary)
    }

    private func step(_ title: String, _ seconds: TimeInterval) -> some View {
        Button(title) {
            draft = clamped(draft.addingTimeInterval(seconds))
        }
        .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
        .monospacedDigit()
    }
}
