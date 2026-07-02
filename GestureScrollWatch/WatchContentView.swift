import SwiftUI

struct WatchContentView: View {
    @StateObject private var receiver = WatchStatusReceiver()

    var body: some View {
        VStack(spacing: 8) {
            StatusBadge(status: receiver.status, size: 76)
                .animation(.easeInOut(duration: 0.15), value: receiver.status)
            Text(StatusPresentation.text(receiver.status))
                .font(.footnote).bold()
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .padding(6)
    }
}
