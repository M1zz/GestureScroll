import SwiftUI

/// 앱 사용법을 단계별로 안내하는 페이지. ContentView에서 시트로 표시한다.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    intro
                    stepsSection
                    gesturesSection
                    modesSection
                    permissionsSection
                    tipsSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 520, height: 640)
    }

    // MARK: - 상단 바

    private var titleBar: some View {
        HStack {
            Label("사용 방법", systemImage: "questionmark.circle.fill")
                .font(.title2).bold()
            Spacer()
            Button("닫기") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - 소개

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GestureScroll이란?")
                .font(.headline)
            Text("카메라로 손동작을 인식해, 지금 화면 맨 앞에 떠 있는 앱(Safari, Keynote, PDF 등)을 손짓만으로 스크롤하거나 페이지를 넘기는 앱입니다. 발표할 때 노트북을 테이블에 두고 손을 흔들어 슬라이드를 넘기는 상황에 맞춰 만들어졌습니다.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 단계별 시작하기

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("시작하기", systemImage: "play.circle")

            step(1, "권한 허용",
                 "처음 실행 시 카메라 권한을 허용하고, ‘손동작으로 다른 앱을 조작’하려면 손쉬운 사용(Accessibility) 권한도 켜야 합니다. 아래 권한 섹션 참고.")
            step(2, "스위치 켜기",
                 "오른쪽 위 토글을 On으로 바꾸면 카메라 미리보기가 켜집니다. 사용할 카메라를 선택하세요(발표용은 외장 웹캠 권장).")
            step(3, "모드 선택",
                 "Scroll(웹/문서), Keynote/PDF(발표), Mouse(커서 제어) 중 상황에 맞는 모드를 고릅니다.")
            step(4, "손바닥으로 활성화",
                 "카메라를 향해 손바닥 ✋을 펼치면 ‘Listening(초록 배지)’ 상태가 됩니다. 이때만 손짓이 동작으로 인식돼, 평소 발표 제스처로 오작동하는 것을 막아줍니다.")
            step(5, "모드에 맞는 손동작",
                 "손동작의 의미는 모드마다 다릅니다. 브라우저는 핀치🤏로 위로 끌어 내리고 ☝️1개로 올리기, 발표는 ✌️2개 유지=다음·🤟3개 유지=이전, PDF는 전부 지원합니다. 자세한 건 아래 ‘모드’ 섹션을 보세요. (엄지는 세지 않습니다)")
        }
    }

    // MARK: - 제스처 표

    private var gesturesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("손동작", systemImage: "hand.draw")

            gestureRow("✋", "손바닥 (손가락 4개)", "Listening 켜기 — 모든 모드의 시작 신호")

            Label("손동작이 뜻하는 동작은 모드마다 다릅니다 — 아래 ‘모드’ 섹션을 참고하세요. 공통적으로: 스크롤은 모양을 들고 있으면 반복되고, 다음·이전은 포즈당 한 번만 + 최소 1.5초 간격이 보장됩니다(연속 오작동 방지). 손을 내리거나 약 6초간 안 쓰면 Listening이 꺼집니다. 엄지는 세지 않고, 인식은 5프레임 다수결로 보정됩니다.",
                  systemImage: "checkmark.seal")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    // MARK: - 모드 설명

    private var modesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("네 가지 모드", systemImage: "slider.horizontal.3")

            modeCard("Scroll (브라우저·웹/문서)",
                     "핀치(🤏 엄지+검지 붙이기)로 페이지를 ‘잡고’ 위·아래로 끌면 페이지가 손을 그대로 따라옵니다(터치 스크롤처럼). ☝️ 손가락 1개를 들고 있으면 일정 속도로 올라갑니다. ‘내리기 민감도’와 ‘올리기 속도’ 슬라이더로 따로 조절하세요.")
            modeCard("Keynote (발표)",
                     "다음(→): ✌️ 손가락 2개를 펴고 0.6초 유지. 이전(←): 🤟 손가락 3개를 펴고 0.6초 유지. 이 두 포즈만 동작하고 ☝️ 포인팅·✊ 주먹·✋ 펼친 손 등 발표 중 자연스러운 손짓은 아무 동작도 하지 않아, 말하면서 손을 써도 슬라이드가 실수로 넘어가지 않습니다. 연속으로 넘길 때는 1.5초 간격이 지켜집니다.")
            modeCard("PDF (전체)",
                     "모두 방향키로 동작합니다. ✊ 주먹 = 아래(↓), ☝️ 1개 = 위(↑), ✌️ 2개 = 다음(→), 🤟 3개 = 이전(←).")
            modeCard("Mouse (커서)",
                     "손을 움직이면 마우스 커서가 화면 위를 따라다닙니다(카메라 프레임 안쪽 70%가 전체 화면에 대응). ✊ 주먹을 쥐면 누르고 펴면 놓습니다 — 쥐었다 펴기 = 클릭, 쥔 채 움직이면 드래그. 손바닥 ✋으로 Listening을 켠 뒤 사용하세요.")
        }
    }

    // MARK: - 권한

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("필요한 권한", systemImage: "lock.shield")

            permissionRow("카메라",
                          "손동작 인식을 위해 필요합니다. 첫 실행 때 안내됩니다.")
            permissionRow("손쉬운 사용(Accessibility)",
                          "다른 앱에 스크롤·키 입력을 보내려면 필요합니다. 시스템 설정 ▸ 개인정보 보호 및 보안 ▸ 손쉬운 사용에서 GestureScroll을 켜세요. 앱 안의 ‘Grant’ 버튼으로 바로 설정 창을 열 수 있습니다.")

            Label("인식은 모두 기기 안에서(Vision 프레임워크) 처리됩니다. 네트워크 전송이나 클라우드 업로드는 없습니다.",
                  systemImage: "checkmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    // MARK: - 팁

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("잘 되게 하는 팁", systemImage: "lightbulb")

            tip("손 전체가 화면 안에 들어오게 하세요. 손이 화면 가장자리에서 잘리면 추적이 끊깁니다.")
            tip("손이 너무 멀거나 작으면 관절 인식 신뢰도가 떨어집니다. 시야각이 넉넉한 외장 웹캠을 권장합니다.")
            tip("반응에는 약 0.3~0.5초의 지연이 있습니다(프레임 처리 + 떨림 보정). 발표용으로는 충분합니다.")
            tip("동작이 두 번씩 인식되면 스와이프 간격을 조금 더 두세요.")
        }
    }

    // MARK: - 재사용 컴포넌트

    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.title3).bold()
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout).bold()
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func gestureRow(_ emoji: String, _ action: String, _ result: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.title2).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(action).bold()
                Text(result).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func modeCard(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).bold()
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func permissionRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .foregroundStyle(Color.accentColor)
                .font(.caption).bold()
                .padding(.top, 3)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    HelpView()
}
