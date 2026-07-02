# GestureScroll TODO

## 진행 중 / 완료
- [x] 스크롤 뚝뚝 끊김 해소
  - [x] 스크롤 이벤트를 카메라 프레임(~15-30fps)에서 분리 — pendingScroll에 쌓고 120Hz 타이머로 잘게 드레인 (지수 글라이드, 손 멈추면 ~30ms 내 정지)
  - [x] 카메라 세션 프리셋 .high → .vga640x480 (Vision 추론 속도↑ → 유효 프레임레이트↑)
  - [x] 모드 전환/OFF/deinit 시 펌프 정리 (stopScrollPump)

- [x] Keynote 제스처 개선 (핀치 1.5초/쥐폈쥐폈 → 손가락 포즈 방식)
  - [x] 다음 = ✌️ 2개 0.6초 유지, 이전 = 🤟 3개 0.6초 유지 (포즈당 1회)
  - [x] ☝️ 포인팅·✊ 주먹·✋ 펼친 손은 무동작 — 발표 손짓 오작동 방지
  - [x] navCooldown 4초 → 1.5초 (연속 넘기기 개선)
  - [x] 핀치홀드/펌프 로직 제거, pinchProgress를 포즈 유지 진행률로 재사용 (컴패니언 링 그대로 동작)
  - [x] ContentView/HelpView/PhoneContentView 안내 문구 갱신, 빌드 확인

- [x] 사용 방법 안내 페이지 추가 (`HelpView.swift`)
  - [x] 단계별 시작하기, 손동작 표, 모드 설명, 권한, 팁 섹션 구성
  - [x] 헤더에 도움말(?) 버튼 → 시트로 표시
  - [x] 메인 화면 하단 "처음 사용하시나요?" 배너 → 같은 페이지로 연결
  - [x] Xcode 프로젝트에 파일 등록 + 빌드 성공 확인

- [x] 제스처 인식 쉽게 개선
  - [x] 임계값 완화: swipeThreshold 0.18→0.10, swipeMaxDuration 0.6→1.2s, armWindow 4→6s
  - [x] 검지 끝(indexTip) 대신 손목(wrist) 추적 — 손목 꺾을 필요 없이 손 전체 이동으로 인식
  - [x] 특정 손가락 모양 요구 제거 (편한 손으로 방향만 이동)
  - [x] 도움말/배너 문구 업데이트

- [x] 권한 경고 배너 개선
  - [x] 권한 상태 1.5초 주기 재확인 → 권한 있으면 배너 안 뜨게
- [x] 코드 서명 고정 (재빌드마다 권한 풀리는 문제 해결)
  - [x] DEVELOPMENT_TEAM = QGAQ3AY3R3 (Xcode 로그인 팀, 4UCCGQP7T8 아님)
  - [x] 정식 서명 확인: TeamIdentifier=QGAQ3AY3R3, hardened runtime (ad-hoc 아님)

- [x] 제스처를 스와이프 → 손가락 개수(정지 포즈) 방식으로 변경
  - [x] 1개=ScrollUp, 2개=ScrollDown, 주먹=Next, 3개=Previous, 4개=Listening
  - [x] 엄지 제외(검지·중지·약지·새끼만 카운트) — 1↔2 오인 방지
  - [x] 0.25초 포즈 유지 디바운스 + 들고 있으면 쿨다운 간격 반복
  - [x] 도움말/배너 문구 갱신

- [x] Next/Previous(주먹·3개)는 한 번만 실행 (연속 입력 방지)
  - [x] 스크롤(1·2개)은 계속 반복 유지, 페이지 이동은 hold당 1회 (firedThisHold 래치)

- [x] Next/Previous 절대 2초 간격 보장 (navCooldown=2.0, lastNavFire 가드)
  - 포즈를 바꿨다 다시 만들어도 2초 안엔 신호 안 나감 (입력은 드롭 않고 2초 시점에 발사)

- [x] Slides 모드를 Keynote/PDF로 분리
  - [x] Keynote: Next(→)/Previous(←)만, 스크롤 포즈(1·2개)는 무시 (발표 오작동 방지)
  - [x] PDF: 1=↑, 2=↓, 주먹=→, 3개=← 전체 동작
  - [x] 모드 3개로 picker/도움말 갱신

- [x] 인식 신뢰도 강화: 5프레임 다수결 voting + MCP 기준 펴짐 판정 + 엄지 제외
- [x] 모드별 손동작 분리 (mode를 recognizer에 전달)
  - [x] Scroll(브라우저): ✊=아래, ☝️=위 (위아래만, 반복)
  - [x] Keynote(발표): ✋→✊ 폈다쥐기=다음(open→fist), ☝️ 유지=이전
  - [x] PDF: ✊=아래, ☝️=위, ✌️=다음, 🤟=이전 (전체)
  - [x] 충돌 회피: clench-release(다음)는 발표 모드에만 (정적 주먹과 같은 모드 금지)

- [x] 첫 사용 설명을 메인 화면에 인라인 표시 (시트 대신)
  - [x] 전체를 ScrollView로 감싸 잘림 방지 (헤더는 고정)
  - [x] 현재 선택한 모드에 맞는 손동작을 실시간으로 보여줌
  - [x] HelpView 시트는 '자세히' 링크로 유지

- [x] 멀리서도 잘 보이게 UI 확대
  - [x] "Last:" 실시간 표시 46pt heavy, 상태 뱃지 title3, 감지 점 30px
  - [x] 제목/토글/모드·카메라 선택기/슬라이더 large + 큰 폰트
  - [x] 첫 사용 설명 글씨 확대(title3), 창 최소 크기 680x820

- [x] '사용 가능한 제스처'를 가장 눈에 띄게 표시
  - [x] 모드 선택 바로 아래 큰 전용 패널 (이모지 56pt + title 굵게, 강조 테두리)
  - [x] 모드 전환 시 실시간 갱신, 첫사용 카드의 중복 목록 제거

- [x] Scroll 모드: 내리기=핀치 끌어내리기, 올리기=손가락 1개
  - [x] 핀치 인식(엄지+검지 거리 < 손바닥크기*0.6, 다수결 보정) → FingerExtension.pinch
  - [x] 핀치 드래그를 부드럽게: 매 프레임 손 이동량 비례 픽셀 스크롤(onScroll 콜백 + scrollPixels)
  - [x] 분수 픽셀 누적(scrollAccum)으로 느린 드래그도 매끄럽게, gain=strength*380
  - [x] 올리기도 매끄럽게: ☝️ 1개 유지 시 매 프레임 연속 픽셀 스크롤(upScrollRate)
- [x] 핀치 인식 실시간 피드백
  - [x] engine.pinchActive (Scroll+armed+pinch) 게시
  - [x] 메뉴바 아이콘 teal+hand.draw.fill, 드롭다운 "🤏 핀치 인식됨 — 끌어서 스크롤"
- [x] No hand 상태 메뉴바 표시 (handVisible 게시, 빨강 hand.raised.slash, "손이 안 보임")
  - [x] Off 아이콘은 pause.circle.fill로 분리

- [x] 메뉴바 상태 아이콘 (MenuBarExtra)
  - [x] 꺼짐/Idle/Listening/동작중 4상태 — 아이콘 모양+색으로 구분
  - [x] commandActive 플래그(0.5초 펄스)로 명령 실행 시각화
  - [x] 드롭다운: 상태 텍스트, On/Off, 모드 선택, 종료

- [x] 스크롤 조절 분리: dragSensitivity(내리기 양) + upSpeed(올리기 속도) 두 슬라이더
  - [x] handleSmoothScroll에서 delta 부호로 민감도/속도 구분 적용
- [x] 영역 이탈 방향 안내 (edgeHint)
  - [x] 손이 가장자리 근접(margin 0.15) 또는 이탈 후(0.30) 시 중앙 방향 화살표+텍스트
  - [x] 카메라 프리뷰 하단 주황 배너로 "손을 ← 왼쪽으로" 등 표시
  - [x] 방향 화살표를 드롭다운→메뉴바 아이콘 자체로 표시 (edgeHint 우선순위 상향)
  - [x] 메뉴바 아이콘을 색 채운 원 + 흰색 심볼 배지로 (선 색 변경 방식 폐지)

- [x] iPhone/Watch 네이티브 컴패니언 (실시간 상태 동기화)
  - [x] 공유 모델 GestureStatus + StatusPresentation/StatusBadge (3타깃 공용)
  - [x] Mac: StatusBroadcaster(MultipeerConnectivity 광고), engine 통합·송신
  - [x] Mac Info.plist에 Local Network/Bonjour 키 추가
  - [x] iOS 앱 소스(GestureScrollPhone): Multipeer 수신 + WatchConnectivity 중계
  - [x] watchOS 앱 소스(GestureScrollWatch): WatchConnectivity 수신
  - [x] iOS(GestureScrollPhone)·watchOS(GestureScrollWatch) 타깃을 pbxproj에 직접 생성
  - [x] 워치 앱 임베드(Embed Watch Content)+의존성, 타깃별 Info.plist
  - [x] 3타깃 빌드 검증 완료 (mac / watchsimulator / iphonesimulator)

- [x] Keynote 다음 슬라이드 오인식 방지 (장표 막 넘어감 해결)
  - [x] 펼친 손(✋)을 openStableTime(0.35s) 유지해야 "준비"되도록 dwell 게이트 추가
  - [x] 닫은 주먹(✊)도 fistStableTime(0.30s) 유지해야 발사 (첫 프레임 즉시 발사 제거)
  - [x] clenchWindow 1.2→0.9s 단축, navCooldown 2s 유지
  - [x] 손 내림/화면이탈/순간 오판이 open→fist로 새지 않게 차단, 빌드 성공

- [x] 핀치 스크롤 방향 반전 (반대로 동작하던 문제 해결)
  - [x] GestureRecognizer 핀치 dy = (y - last) → (last - y): 핀치하고 위로 끌면 아래로 스크롤
  - [x] ContentView/HelpView 안내 문구 "위로 끌기"로 갱신

- [x] Keynote를 핀치 좌우 스와이프로 변경 (실수로 다음 장 넘어감 방지)
  - [x] open→fist(폈다쥐기)·손가락1개 방식 제거 → 🤏 핀치한 채 오른쪽=다음, 왼쪽=이전
  - [x] swipeDistance(0.16) 이상 가로 이동해야 발사 — 손모양·위아래 움직임으로 오작동 안 함
  - [x] 핀치당 1회만(swipeFiredThisPinch) + navCooldown 4s 유지
  - [x] Keynote에서도 핀치 실시간 피드백(pinchActive) 표시
  - [x] ContentView/HelpView 키노트 안내 문구 갱신, 빌드 성공

- [x] Keynote '이전'을 실수 방지 동작(주먹 쥐폈쥐폈)으로 변경
  - [x] 핀치 왼쪽=이전 제거 → ✊ open→fist 클렌치 2회(pumpClenchesForPrev)로 이전 발사
  - [x] ✋ 본 직후의 ✊만 클렌치로 카운트(pumpWasOpen), pumpWindow(2s) 내 2회면 발사
  - [x] 핀치 중(fingers.pinch)인 주먹은 클렌치로 안 셈 — 다음 동작과 교차 오작동 방지
  - [x] 다음은 핀치 오른쪽 스와이프만 유지(dx>0), navCooldown 4s 유지
  - [x] ContentView/HelpView 안내 문구 갱신, 빌드 성공

- [x] iOS 앱에 이벤트 차단(navCooldown) 시간 타이머 링 표시
  - [x] GestureStatus에 navCooldown(지속), navSeq(이벤트마다 1 증가) 추가 — dedup 깨지 않음
  - [x] GestureEngine: Next/Prev 발사 시 navSeq 증가 + 즉시 송신
  - [x] PhoneStatusReceiver: navSeq 변경 감지 → 로컬 시계로 cooldownStart 스탬프(시계 오차 회피)
  - [x] PhoneContentView: CooldownRing(TimelineView)로 4초간 줄어드는 원 테두리 표시
  - [x] mac/iOS 빌드 성공

- [x] iPhone에 손 위치·모양 실시간 표시 (화살표만 나오던 것 개선)
  - [x] GestureStatus에 handDetected/handX/handY/poseEmoji 추가 (정규화 0~1, 미러 좌표)
  - [x] GestureEngine: wrist/tip 좌표 1% 반올림 송신 + poseEmoji(✊☝️✌️🤟✋🤏) 계산
  - [x] PhoneContentView: 화면을 뜻하는 사각형(16:10)에 손 위치 점 + 모양 이모지 표시(HandFieldView)
  - [x] 기존 단일 화살표 뱃지 대체, mac/iOS 빌드 성공

- [x] Safari 웹 익스텐션 별도 제작 (웹페이지 전용 버전)
  - [x] SafariExtension/extension: MV3 매니페스트 + content/gesture/engine/popup + panel.css
  - [x] 손 인식 MediaPipe Hands(로컬 번들: lib/wasm/model ~17MB, 네트워크 X)
  - [x] 손가락 판정·5프레임 투표·GestureRecognizer 로직을 gesture.js로 그대로 포팅
  - [x] Scroll=window.scrollBy, Slides/PDF=화살표 KeyboardEvent, 우측하단 패널에 손 위치 이모지 프리뷰
  - [x] JS/manifest 문법 검증 완료, safari-web-extension-converter 변환 절차 README 작성

- [x] Keynote '다음'을 핀치 3초 유지로 변경 + 아이폰에 차오르는 원 표시
  - [x] GestureRecognizer: 핀치 오른쪽 스와이프 제거 → 핀치 유지 시간(pinchHoldForNext=3s)로 발사
  - [x] pinchProgress(0~1) 매 프레임 계산 — 한 번의 연속 핀치당 1회(pinchFiredThisHold)
  - [x] GestureStatus.pinchProgress 추가 → Mac이 절대 진행률 송신(시계 오차 없음)
  - [x] PhoneContentView: 손 마커에 채워지는 링(trim) 표시, 다 차면 다음 슬라이드
  - [x] ContentView/HelpView 안내 문구 갱신, Safari 익스텐션도 동일 로직+진행 바 반영
  - [x] mac/iOS/watch 3타깃 빌드 성공, 익스텐션 JS 문법 검증

- [x] 스크롤 버벅임 / 키노트 오작동 수정 (아이폰 연결 시)
  - [x] 원인: 손 좌표가 매 프레임 바뀌며 broadcaster.send가 메인 스레드에서 매 프레임 JSON 인코딩+전송 → CGEvent 스크롤·핀치 타이밍 방해
  - [x] StatusBroadcaster: 전용 sendQueue(백그라운드 직렬)로 인코딩+전송 이관, last는 큐에서만 접근
  - [x] 핀치 유지 1.5초로 단축(이전 요청) 문구까지 반영

- [x] iOS 앱 전부 영어화 (Mac 메뉴바/Watch는 한국어 유지)
  - [x] PhoneContentView 로컬 영어 statusText 추가 (공유 StatusPresentation은 그대로)
  - [x] 모드/연결/손 없음 등 리터럴 영어화, Info.plist는 이미 영어
  - [x] iOS 타깃 한글 잔존 0 확인, mac/iOS 빌드 성공

- [x] 스크롤 쫀쫀하게 (터치처럼 페이지가 손을 따라오게)
  - [x] 핀치 드래그 양방향화: dy>0 게이트 제거 — 잡고 위·아래 어느 쪽이든 1:1 추적
  - [x] EMA 스무딩(α=0.55) + 데드존(0.0008)으로 포즈 추정 잔떨림 제거, gain 380→420
  - [x] Safari 익스텐션에도 동일 적용 (gesture.js/content.js), 안내 문구 갱신

- [x] Mouse(커서) 모드 추가
  - [x] ControlMode.cursor — 손 위치(프레임 안쪽 70%)→메인 화면 절대 매핑, EMA(α=0.45)
  - [x] 🤏 핀치 엣지 = mouseDown/Up, 잡은 채 이동 = leftMouseDragged (클릭+드래그)
  - [x] SystemControl: moveMouse/mouseDown/mouseUp/mainDisplaySize 추가
  - [x] 안전장치: 모드 전환·토글 오프·손 사라짐 시 잡힌 클릭 자동 해제(releaseCursor)
  - [x] ContentView 제스처 패널·HelpView 모드 카드 추가, mac/iOS 빌드 성공

- [x] Mouse 모드 클릭을 주먹 쥐었다 펴기로 변경
  - [x] ✊ 쥐면 mouseDown, 펴면 mouseUp — 쥐폈=클릭, 쥔 채 이동=드래그
  - [x] 주먹이 핀치로도 읽히는 경우 포함(count==0 || pinch = pressing)
  - [x] 0.12초 눌림 디바운스(pressCandidateSince)로 포즈 전환 중 오클릭 방지, 놓기는 즉시
  - [x] ContentView/HelpView 문구 갱신, macOS 빌드 성공

- [x] 경쟁사 앱 조사 완료 (웹캠 손동작 제어 앱 — macOS/Windows/발표특화/브라우저 익스텐션/시장 공백 5개 각도 웹 리서치, 결과는 대화 리포트 참조)

- [x] 상용화 기반 다지기 1차 (설정 저장·권한·자동 시작·아이콘·메뉴바)
  - [x] 설정 영속화: mode/내리기 민감도/올리기 속도/카메라 선택을 UserDefaults에 저장, 재시작 시 복원
  - [x] 카메라 권한 처리: On 시 권한 요청(notDetermined), 거부 시 빨간 배너 + "설정 열기" 버튼(개인정보 보호 › 카메라 바로가기) — 기존엔 검은 화면만 나옴
  - [x] 로그인 시 자동 시작: SMAppService.mainApp 토글 (메인 화면 + 메뉴바 드롭다운 양쪽)
  - [x] 앱 아이콘 생성: 인디고→틸 그라디언트 + 흰 손바닥, Assets.xcassets(AppIcon 10슬롯 + AccentColor) 신규 생성, pbxproj 등록, 번들에 AppIcon.icns 포함 확인
  - [x] 메뉴바 개선: "메인 창 열기" 버튼(WindowGroup id "main" + openWindow), 버전 표시(CFBundleShortVersionString)
  - [x] macOS 타깃 빌드 성공 확인

## 향후 아이디어 (상용화 로드맵)
- [ ] 영어/한국어 다국어(Localization) 지원
- [ ] 손동작 애니메이션/그림으로 시각적 안내 추가
- [ ] Safari 익스텐션 실기기 테스트 (Xcode 변환 후 Safari에서 로드/카메라 권한 확인)
- [ ] 배포 준비: Developer ID 서명 + notarization + DMG 패키징 (샌드박스 OFF라 App Store 불가 — 자체 배포)
- [ ] 자동 업데이트 (Sparkle) 도입
- [ ] 첫 실행 온보딩 플로우 (권한 2종 안내 → 카메라 선택 → 모드 체험)
- [ ] 크래시 리포트/사용 통계 (opt-in)
- [ ] 라이선스/결제 모델 결정 (무료 체험 + 라이선스 키 or 구독)
