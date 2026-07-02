# iPhone · Apple Watch 컴패니언 앱

Mac 앱의 상태를 iPhone/Watch에서 **실시간**으로 보는 컴패니언 앱입니다.
전송 경로: **Mac → iPhone (MultipeerConnectivity, 기기 직접 연결)** → **Watch (WatchConnectivity)**.

## 타깃은 이미 만들어져 있습니다
`GestureScroll.xcodeproj`에 3개 타깃이 모두 구성돼 있고 빌드도 검증됨:
- **GestureScroll** (macOS) — 상태 송신 (StatusBroadcaster)
- **GestureScrollPhone** (iOS) — 수신 + Watch로 중계
- **GestureScrollWatch** (watchOS) — iPhone에서 받아 손목에 표시 (iPhone 앱에 임베드됨)

## 실행 방법
1. Xcode에서 `GestureScroll.xcodeproj` 열기
2. **Mac 앱 실행** (scheme: GestureScroll, ⌘R) → 첫 실행 시 "로컬 네트워크 사용 허용"
3. **iPhone 앱 실행**:
   - scheme를 **GestureScrollPhone**으로, 디바이스를 본인 iPhone(실기기)로 선택 → ⌘R
   - 첫 실행 시 iPhone에서 "로컬 네트워크 사용 허용"
   - iPhone과 Mac이 가까이 있으면 자동 연결 (같은 WiFi 불필요)
4. **Watch 앱 실행**:
   - iPhone 앱을 설치하면 페어링된 Watch에 GestureScrollWatch가 함께 설치됨
   - Watch에서 앱을 열면 상태가 표시됨 (scheme GestureScrollWatch로 직접 실행도 가능)

> 서명: 세 타깃 모두 팀 `QGAQ3AY3R3`로 자동 서명됩니다. 실기기 설치 시 한 번 더 권한/신뢰가 필요할 수 있어요.

## 실시간성 / 한계
- **iPhone**: Mac과 직접 연결, 지연 ~수십 ms (실시간) ✅
- **Watch**: iPhone 경유. **워치 앱 화면을 켜둔(포그라운드) 상태에서 실시간**.
  백그라운드/컴플리케이션은 애플이 갱신을 제한해 실시간이 아님
- 첫 실행 때 Mac·iPhone 양쪽에서 **로컬 네트워크 권한** 허용 필요

## 표시되는 상태 (3기기 공통: 색 원 + 흰 심볼)
| 색 | 심볼 | 의미 |
|---|---|---|
| 회색 | ⏸ | 꺼짐 |
| 빨강 | ✋̸ | 손 안 보임 |
| 주황 | ← ↑ → ↓ | 가장자리 이탈 — 그 방향으로 손 이동 |
| 청록 | ✍️ | 핀치 인식 |
| 파랑 | 👆 | 명령 동작 중 |
| 초록 | ✋ | Listening |
| 주황 | ✋ | Idle |

## 구성 파일
- 공유(3타깃 멤버): `GestureScroll/GestureStatus.swift`, `GestureScroll/StatusPresentation.swift`
- Mac: `GestureScroll/StatusBroadcaster.swift`
- iOS: `GestureScrollPhone/*`
- watchOS: `GestureScrollWatch/*`
