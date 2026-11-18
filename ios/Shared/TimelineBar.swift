import SwiftUI

/// The 24-hour bar: yellow = power, dark = outage, hatched = possible outage.
/// Used by the app cards and by every widget size.
struct TimelineBar: View {
    var day: DaySchedule
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 6
    var showsHours = false
    /// When set and it falls on `day`, draws a "now" marker.
    var now: Date?

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let segments = ScheduleMath.segments(day)
                let gaps = CGFloat(max(0, segments.count - 1)) * 2
                let unit = max(0, geo.size.width - gaps) / CGFloat(ScheduleMath.minutesPerDay)
                ZStack(alignment: .leading) {
                    if day.status != .scheduled && day.slots.isEmpty {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.surface2)
                    } else {
                        HStack(spacing: 2) {
                            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                                SegmentFill(kind: segment.kind)
                                    .frame(width: max(1, unit * CGFloat(segment.length)))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }

                    if let x = markerX(width: geo.size.width) {
                        Capsule()
                            .fill(Theme.fg)
                            .frame(width: 2, height: height + 8)
                            .offset(x: x - 1)
                    }
                }
                .frame(height: height)
            }
            .frame(height: height)

            if showsHours {
                HStack {
                    Text("00"); Spacer(); Text("06"); Spacer(); Text("12"); Spacer(); Text("18"); Spacer(); Text("24")
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.subtle)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func markerX(width: CGFloat) -> CGFloat? {
        guard let now, ScheduleMath.dateString(now) == day.date else { return nil }
        let c = ScheduleMath.calendar.dateComponents([.hour, .minute], from: now)
        let minute = CGFloat((c.hour ?? 0) * 60 + (c.minute ?? 0))
        return width * minute / CGFloat(ScheduleMath.minutesPerDay)
    }

    private var accessibilityText: String {
        let off = ScheduleMath.ranges(day, kind: .off)
        let maybe = ScheduleMath.ranges(day, kind: .maybe)
        if day.status != .scheduled && day.slots.isEmpty { return "Графіка немає" }
        var text = off.isEmpty ? "Вимкнень не заплановано" : "Вимкнення: \(off)"
        if !maybe.isEmpty { text += ". Можливі вимкнення: \(maybe)" }
        return text
    }
}

private struct SegmentFill: View {
    var kind: ScheduleMath.SegmentKind

    var body: some View {
        switch kind {
        case .on: Rectangle().fill(Theme.on)
        case .off: Rectangle().fill(Theme.off)
        case .maybe: Hatch()
        }
    }
}

/// Diagonal stripes — "possible outage" must be readable without colour.
struct Hatch: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.maybeBg))
            var x: CGFloat = -size.height
            while x < size.width {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(stripe, with: .color(Theme.off), lineWidth: 2.5)
                x += 7
            }
        }
    }
}

/// Legend under the bars.
struct TimelineLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(Rectangle().fill(Theme.on), "Світло є")
            item(Rectangle().fill(Theme.off), "Вимкнення")
            item(Hatch(), "Можливе")
        }
        .font(.caption)
        .foregroundStyle(Theme.muted)
    }

    private func item(_ swatch: some View, _ title: String) -> some View {
        HStack(spacing: 6) {
            swatch.frame(width: 14, height: 10).clipShape(RoundedRectangle(cornerRadius: 3))
            Text(title)
        }
    }
}

/// Bulb icon used for the on/off state (SF Symbols).
struct PowerIcon: View {
    var isOn: Bool
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: isOn ? "lightbulb.max" : "lightbulb.slash")
            .font(.system(size: size * 0.8, weight: .semibold))
            .foregroundStyle(isOn ? Theme.onText : Theme.offText)
            .frame(width: size * 1.8, height: size * 1.8)
            .background(isOn ? Theme.onSoft : Theme.offSoft, in: RoundedRectangle(cornerRadius: size * 0.55, style: .continuous))
            .accessibilityHidden(true)
    }
}
