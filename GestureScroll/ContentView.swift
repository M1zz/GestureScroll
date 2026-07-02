import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var engine: GestureEngine
    @State private var flash = false
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 16) {
            header

            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        if engine.enabled {
                            CameraPreview(session: engine.camera.previewSession)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(detectionOverlay)
                        } else {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.black.opacity(0.85))
                                .overlay(Text("Camera off")
                                    .foregroundStyle(.white.opacity(0.6)))
                        }
                    }
                    .frame(height: 360)
                    .overlay(alignment: .topLeading) { statusBadges.padding(12) }
                    .overlay(alignment: .bottom) { edgeHintBanner.padding(.bottom, 14) }
                    .animation(.easeInOut(duration: 0.15), value: engine.edgeHint)

                    gestureReadout
                    controls

                    gesturePanel

                    if engine.cameraDenied { cameraDeniedBanner }
                    if !engine.hasPermission { permissionBanner }

                    instructions
                }
                .padding(.bottom, 4)
            }
        }
        .padding(20)
        .sheet(isPresented: $showHelp) { HelpView() }
        .onAppear { engine.refreshPermission() }
        .onChange(of: engine.lastGestureTime) { _ in
            flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { flash = false }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill").font(.largeTitle)
            Text("GestureScroll").font(.largeTitle).bold()
            Spacer()
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle").font(.title)
            }
            .buttonStyle(.borderless)
            .help("사용 방법 보기")
            Toggle(isOn: Binding(get: { engine.enabled },
                                 set: { _ in engine.toggle() })) {
                Text(engine.enabled ? "On" : "Off").font(.title3).bold()
            }
            .toggleStyle(.switch)
            .controlSize(.large)
        }
    }

    private var detectionOverlay: some View {
        GeometryReader { geo in
            if let tip = engine.camera.indexTip, engine.camera.handDetected {
                Circle()
                    .fill(engine.armed ? Color.green : Color.yellow)
                    .frame(width: 30, height: 30)
                    .position(x: tip.x * geo.size.width,
                              y: tip.y * geo.size.height)
                    .animation(.linear(duration: 0.05), value: tip)
            }
        }
    }

    @ViewBuilder private var edgeHintBanner: some View {
        if engine.enabled, let hint = engine.edgeHint {
            HStack(spacing: 12) {
                Image(systemName: hint.arrow).font(.title).bold()
                Text(hint.text).font(.title2).bold()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.orange, in: Capsule())
            .foregroundStyle(.white)
            .shadow(radius: 5)
        }
    }

    private var statusBadges: some View {
        HStack(spacing: 10) {
            badge(engine.camera.handDetected ? "Hand ✓" : "No hand",
                  color: engine.camera.handDetected ? .green : .gray)
            badge(engine.armed ? "Listening ✋" : "Idle",
                  color: engine.armed ? .green : .orange)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.title3).bold()
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(color.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
    }

    private var gestureReadout: some View {
        HStack(spacing: 14) {
            Text("Last:").font(.title2).foregroundStyle(.secondary)
            Text(engine.lastGesture)
                .font(.system(size: 46, weight: .heavy))
                .foregroundStyle(flash ? .green : .primary)
                .scaleEffect(flash ? 1.12 : 1.0)
                .animation(.spring(response: 0.2), value: flash)
                .lineLimit(1).minimumScaleFactor(0.5)
            Spacer()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            // No custom font inside the segments — NSSegmentedControl renders its
            // own label metrics, and an overridden font shifts the text off-center.
            Picker("Mode", selection: $engine.mode) {
                ForEach(GestureEngine.ControlMode.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            Picker("Camera", selection: Binding(
                get: { engine.selectedCameraID },
                set: { engine.selectCamera($0) })) {
                Text("Default").tag(String?.none)
                ForEach(engine.camera.availableCameras, id: \.uniqueID) { cam in
                    Text(cam.localizedName).tag(String?.some(cam.uniqueID))
                }
            }
            .controlSize(.large)
            .font(.title3)

            if engine.mode == .scroll {
                VStack(spacing: 10) {
                    sliderRow("내리기 민감도", value: $engine.dragSensitivity, range: 3...20)
                    sliderRow("올리기 속도", value: $engine.upSpeed, range: 2...20)
                }
            }

            Toggle(isOn: Binding(get: { engine.launchAtLogin },
                                 set: { engine.launchAtLogin = $0 })) {
                Text("로그인할 때 자동 시작").font(.title3)
            }
            .toggleStyle(.switch)
            .controlSize(.large)
        }
    }

    private func sliderRow(_ label: String, value: Binding<Int32>,
                           range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.title3).frame(width: 130, alignment: .leading)
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Int32($0) }),
                   in: range, step: 1)
            .controlSize(.large)
            Text("\(value.wrappedValue)").font(.title3).bold()
                .monospacedDigit().frame(width: 36)
        }
    }

    private var cameraDeniedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "video.slash.fill")
                .font(.title).foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("카메라 권한이 꺼져 있어요").font(.title3).bold()
                Text("시스템 설정 › 개인정보 보호 › 카메라에서 GestureScroll을 켜주세요.")
                    .font(.body).foregroundStyle(.secondary)
            }
            Spacer()
            Button("설정 열기") { engine.openCameraPrivacySettings() }
                .controlSize(.large)
        }
        .padding(16)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility permission needed").font(.title3).bold()
                Text("Grant it so the app can send scroll/key events.")
                    .font(.body).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant") { engine.requestPermission() }
                .controlSize(.large)
        }
        .padding(16)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    /// The gestures for the currently selected mode (emoji, description, accent color).
    private var currentModeGestures: [(symbol: String, text: String, color: Color)] {
        switch engine.mode {
        case .scroll:
            return [("🤏", "핀치로 페이지 잡고 끌기 — 위·아래 모두", .indigo),
                    ("☝️", "손가락 1개 — 일정 속도로 올리기", .green)]
        case .keynote:
            return [("✌️", "손가락 2개 펴고 0.6초 유지 — 다음 (→)", .orange),
                    ("🤟", "손가락 3개 펴고 0.6초 유지 — 이전 (←)", .pink)]
        case .pdf:
            return [("✊", "주먹 — 아래 (↓)", .indigo),
                    ("☝️", "손가락 1개 — 위 (↑)", .green),
                    ("✌️", "손가락 2개 — 다음 (→)", .orange),
                    ("🤟", "손가락 3개 — 이전 (←)", .pink)]
        case .cursor:
            return [("🖐", "손을 움직이면 커서가 따라감", .indigo),
                    ("🤏", "엄지+검지 집었다 놓기 — 클릭 (집은 채 이동 = 드래그)", .orange)]
        }
    }

    /// Big, prominent panel showing the gestures available in the current mode.
    private var gesturePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.title).foregroundStyle(Color.accentColor)
                Text("사용 가능한 제스처").font(.title).bold()
                Spacer()
                Text(engine.mode.rawValue)
                    .font(.title3).bold()
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }

            ForEach(currentModeGestures, id: \.text) { g in
                HStack(spacing: 18) {
                    Text(g.symbol)
                        .font(.system(size: 52))
                        .frame(width: 120, alignment: .center)
                        .padding(.vertical, 8)
                        .background(g.color.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                    Text(g.text)
                        .font(.title).bold()
                        .foregroundStyle(g.color)
                        .lineLimit(2).minimumScaleFactor(0.6)
                    Spacer()
                }
                .padding(.vertical, 12).padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(g.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(g.color.opacity(0.4), lineWidth: 1))
            }
        }
        .padding(20)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "hand.wave.fill").font(.title2).foregroundStyle(Color.accentColor)
                Text("처음 사용하기").font(.title2).bold()
                Spacer()
                Button("자세히") { showHelp = true }
                    .buttonStyle(.link)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 10) {
                step(1, "카메라 · 손쉬운 사용 권한 허용")
                step(2, "오른쪽 위 토글을 On + 카메라 선택")
                step(3, "위에서 모드 선택 (Scroll / Keynote / PDF)")
                step(4, "카메라에 손바닥 ✋ → 초록 Listening")
                step(5, "위 ‘사용 가능한 제스처’대로 손동작")
            }

            Label("손을 내리거나 약 6초간 안 쓰면 Listening이 꺼집니다. 다시 손바닥 ✋으로 켜세요.",
                  systemImage: "timer")
                .font(.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(n)")
                .font(.title3).bold()
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor, in: Circle())
            Text(text).font(.title3)
            Spacer()
        }
    }
}
