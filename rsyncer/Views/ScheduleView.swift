import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var pair: SyncPair
    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(hour: pair.schedule.hour, minute: pair.schedule.minute)) ?? Date() }, set: {
            var changed = pair
            changed.schedule.hour = Calendar.current.component(.hour, from: $0)
            changed.schedule.minute = Calendar.current.component(.minute, from: $0)
            pair = changed
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Give your sync a rhythm").font(.system(size: 16, weight: .semibold))
                Text("Automatic runs use this pair’s saved options.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Run this sync")
                Menu {
                    ForEach(ScheduleKind.allCases) { kind in
                        Button(kind.title) {
                            var changed = pair
                            changed.schedule.kind = kind
                            pair = changed
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(pair.schedule.kind.title)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 360, height: 48)
                    .background(Palette.insetFill, in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("Run this sync")
                .menuStyle(.borderlessButton)
            }
            if pair.schedule.kind == .daily || pair.schedule.kind == .weekly {
                DatePicker("At", selection: time, displayedComponents: .hourAndMinute).frame(maxWidth: 360)
            }
            if pair.schedule.kind == .weekly {
                Picker("On", selection: $pair.schedule.weekday) {
                    ForEach(1...7, id: \.self) { day in Text(Calendar.current.weekdaySymbols[day - 1]).tag(day) }
                }.frame(maxWidth: 360)
            }
            if let next = pair.nextRun {
                Label("Next run: \(next.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.system(size: 12)).foregroundStyle(Palette.accent)
            }
            if pair.schedule.kind == .onMount {
                Label("Runs when either saved location’s drive connects and both locations are available.", systemImage: "externaldrive.badge.plus")
                    .font(.system(size: 12)).foregroundStyle(Palette.accent)
            }
            if let status = store.scheduleStatus[pair.id] {
                Label("Waiting: \(status)", systemImage: "clock.badge.exclamationmark").font(.system(size: 11)).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Quietly working in the background", systemImage: "menubar.rectangle").font(.system(size: 12, weight: .medium))
                Text("Schedules run while rsyncer is open, including with its window closed. Missed timed runs resume after wake or relaunch. Unavailable drives are checked again automatically. Quitting rsyncer pauses scheduling.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(18).cardSurface(radius: 10, fill: Palette.accent.opacity(0.07), stroke: Palette.accent.opacity(0.2))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
