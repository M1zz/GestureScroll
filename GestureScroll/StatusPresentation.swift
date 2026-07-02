import SwiftUI

/// Maps a GestureStatus to the symbol / color / text shown identically on the
/// Mac menu bar, the iPhone, and the Apple Watch. SHARED across all three targets.
enum StatusPresentation {
    static func symbol(_ s: GestureStatus) -> String {
        if let e = s.edge {
            switch e {
            case .left:  return "arrow.left"
            case .right: return "arrow.right"
            case .up:    return "arrow.up"
            case .down:  return "arrow.down"
            }
        }
        switch s.kind {
        case .off:       return "pause.circle.fill"
        case .noHand:    return "hand.raised.slash"
        case .pinch:     return "hand.draw.fill"
        case .command:   return "hand.point.up.left.fill"
        case .listening: return "hand.raised.fill"
        case .idle:      return "hand.raised"
        }
    }

    static func color(_ s: GestureStatus) -> Color {
        if s.edge != nil { return .orange }
        switch s.kind {
        case .off:       return .gray
        case .noHand:    return .red
        case .pinch:     return .teal
        case .command:   return .blue
        case .listening: return .green
        case .idle:      return .orange
        }
    }

    static func text(_ s: GestureStatus) -> String {
        if let e = s.edge {
            switch e {
            case .left:  return "손을 왼쪽으로"
            case .right: return "손을 오른쪽으로"
            case .up:    return "손을 위로"
            case .down:  return "손을 아래로"
            }
        }
        switch s.kind {
        case .off:       return "꺼짐"
        case .noHand:    return "손이 안 보임"
        case .pinch:     return "🤏 핀치 — 끌어서 스크롤"
        case .command:   return "동작 중: \(s.lastGesture)"
        case .listening: return "Listening"
        case .idle:      return "Idle — 손바닥 ✋"
        }
    }
}

/// Reusable color-filled circle badge with a white symbol. Used on every device.
struct StatusBadge: View {
    let status: GestureStatus
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            Circle().fill(StatusPresentation.color(status))
            Image(systemName: StatusPresentation.symbol(status))
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
