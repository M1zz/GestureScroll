import SwiftUI

struct PhoneContentView: View {
    @StateObject private var receiver = PhoneStatusReceiver()

    var body: some View {
        VStack(spacing: 22) {
            // The screen/frame, with the detected hand drawn where it actually is.
            HandFieldView(status: receiver.status)
                .frame(maxWidth: 460)

            Text(statusText(receiver.status))
                .font(.title2).bold()
                .multilineTextAlignment(.center)

            if !receiver.status.mode.isEmpty {
                Text("Mode: \(receiver.status.mode)")
                    .font(.title3).foregroundStyle(.secondary)
            }

            Label(receiver.connected ? "Mac connected" : "Searching for Mac…",
                  systemImage: receiver.connected ? "wifi" : "wifi.exclamationmark")
                .font(.callout)
                .foregroundStyle(receiver.connected ? .green : .secondary)
        }
        .padding()
    }

    /// English status text for the iPhone app (the shared StatusPresentation.text
    /// stays Korean for the Mac menu bar and Watch).
    private func statusText(_ s: GestureStatus) -> String {
        if let e = s.edge {
            switch e {
            case .left:  return "Move hand left"
            case .right: return "Move hand right"
            case .up:    return "Move hand up"
            case .down:  return "Move hand down"
            }
        }
        switch s.kind {
        case .off:       return "Off"
        case .noHand:    return "No hand detected"
        case .pinch:     return "🤏 Pinch — drag to scroll"
        case .command:   return "Action: \(s.lastGesture)"
        case .listening: return "Listening"
        case .idle:      return "Idle — raise palm ✋"
        }
    }
}

/// A rectangle standing in for the Mac's camera frame / screen, with the detected
/// hand rendered at its real position (normalized, mirrored) and its shape shown
/// as an emoji. Replaces the old single arrow badge.
private struct HandFieldView: View {
    let status: GestureStatus

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let color = StatusPresentation.color(status)
            ZStack {
                // The "screen" rectangle.
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                RoundedRectangle(cornerRadius: 20)
                    .stroke(color.opacity(0.6), lineWidth: 3)

                // Center crosshair for orientation.
                Path { p in
                    p.move(to: CGPoint(x: w / 2, y: 12)); p.addLine(to: CGPoint(x: w / 2, y: h - 12))
                    p.move(to: CGPoint(x: 12, y: h / 2)); p.addLine(to: CGPoint(x: w - 12, y: h / 2))
                }
                .stroke(Color.gray.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))

                if status.handDetected {
                    let x = CGFloat(status.handX) * w
                    let y = CGFloat(status.handY) * h
                    let progress = max(0, min(1, status.pinchProgress))
                    ZStack {
                        Circle().fill(color.opacity(0.22)).frame(width: 84, height: 84)
                        // Hold ring: fills clockwise from 12 o'clock while a
                        // Next/Previous pose is held; full = slide advanced.
                        if progress > 0 {
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 7)
                                .frame(width: 92, height: 92)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 92, height: 92)
                                .animation(.linear(duration: 0.12), value: progress)
                        }
                        Circle().fill(color).frame(width: 12, height: 12)   // exact point
                        Text(status.poseEmoji.isEmpty ? "🖐" : status.poseEmoji)
                            .font(.system(size: 40))
                            .offset(y: -2)
                    }
                    .position(x: x, y: y)
                    .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.8), value: status.handX)
                    .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.8), value: status.handY)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "hand.raised.slash")
                            .font(.system(size: 40, weight: .semibold))
                        Text(status.kind == .off ? "Off" : "No hand detected")
                            .font(.callout)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
    }
}

/// A circular border that drains from full to empty over `duration`, starting at
/// `start`. Used to visualize the Next/Previous "blocked" cooldown on the phone.
private struct CooldownRing: View {
    let start: Date?
    let duration: TimeInterval
    let size: CGFloat
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = remaining(at: timeline.date)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
                .rotationEffect(.degrees(-90))   // start draining from 12 o'clock
                .frame(width: size, height: size)
                .opacity(progress > 0 ? 1 : 0)
        }
    }

    /// Fraction of the cooldown still remaining (1 → full ring, 0 → gone).
    private func remaining(at now: Date) -> Double {
        guard let start, duration > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return max(0, min(1, 1 - elapsed / duration))
    }
}
