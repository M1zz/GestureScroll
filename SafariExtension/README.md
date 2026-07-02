# GestureScroll — Safari Web Extension

macOS 네이티브 앱의 **웹 전용 버전**입니다. 카메라로 손을 인식해서 **현재 보고 있는
웹페이지**를 스크롤하거나(스크롤 모드) 슬라이드를 넘깁니다(Slides/PDF 모드).

네이티브 앱과의 차이는 프로젝트 최상단에서 이미 정리했듯이:

- 손 인식: Vision framework → **MediaPipe Hands (JS, WASM)** 로 대체 (완전 온디바이스, 네트워크 X)
- 제어 대상: "최전면 앱 아무거나" → **이 웹페이지 안**으로 한정 (Keynote·Preview PDF 등 다른 앱 제어 불가)
- 접근성 권한 불필요 (페이지를 직접 `scrollBy` / 키 이벤트로 제어)
- 손가락 판정·제스처 상태머신 로직은 네이티브(`GestureRecognizer.swift`)를 **그대로 포팅**

## 폴더 구성

```
SafariExtension/extension/
  manifest.json     MV3 매니페스트
  gesture.js        손가락 판정 + 5프레임 투표 + GestureRecognizer 포팅 (순수 로직)
  engine.mjs        MediaPipe HandLandmarker 로더 (유일한 ES 모듈)
  content.js        패널 UI + 카메라 루프 + 페이지 액션(스크롤/화살표)
  panel.css         우측 하단 플로팅 패널 스타일
  popup.html/js     툴바 버튼 팝업(켜기/끄기·모드)
  lib/              vision_bundle.mjs (MediaPipe)
  wasm/             vision_wasm_internal.js / .wasm
  model/            hand_landmarker.task (손 랜드마크 모델)
```

## Xcode 프로젝트로 변환 (한 번만)

Safari 익스텐션은 반드시 macOS 앱으로 감싸야 설치됩니다. 애플 공식 변환 도구를 씁니다:

```bash
cd /Users/leeo/Documents/workspace/code/GestureScroll
xcrun safari-web-extension-converter SafariExtension/extension \
  --project-location SafariExtension/xcode \
  --app-name "GestureScroll Web" \
  --bundle-identifier com.gesturescroll.web \
  --macos-only
```

생성된 `SafariExtension/xcode/GestureScroll Web/GestureScroll Web.xcodeproj` 를 열고:

1. 두 타깃(앱 + Extension)의 **Signing & Capabilities → Team** 을 본인 팀(`QGAQ3AY3R3`)으로
2. **Run (⌘R)** — 컨테이너 앱이 실행됩니다

## Safari에서 켜기

1. Safari ▸ 설정 ▸ **개발자** 탭 ▸ "확인되지 않은 확장 프로그램 허용" 체크
   (메뉴에 개발자 탭이 없으면: Safari ▸ 설정 ▸ 고급 ▸ "메뉴 막대에 개발자용 메뉴 표시")
2. Safari ▸ 설정 ▸ **확장 프로그램** ▸ **GestureScroll** 체크
3. 아무 웹페이지에서 우측 하단 **GestureScroll 패널**의 **시작** 버튼 클릭
4. 해당 사이트에서 **카메라 허용** (권한은 사이트 단위)
5. **손바닥 ✋** 을 들어 Listening 을 켠 뒤 동작:
   - **Scroll**: 🤏 핀치 후 위로 끌기 → 아래 스크롤 · ☝️ 한 손가락 → 위로 스크롤
   - **Slides**: 🤏 핀치를 1.5초 유지 → 다음(→, 패널 바가 다 차면) · ✊ 쥐폈쥐폈 → 이전(←)
   - **PDF**: ✊=↓ · ☝️=↑ · ✌️=→ · 🤟=←

패널의 작은 프리뷰에는 인식 중인 **손 위치에 손 모양 이모지**가 실시간으로 따라다녀서
어디를 어떻게 잡고 있는지 바로 확인할 수 있습니다.

## 한계 / 주의

- **화살표 키 동작**(Slides/PDF)은 합성 `KeyboardEvent` 라서, 키를 직접 듣는 웹 슬라이드
  프레임워크(Google Slides, reveal.js 등)에서는 동작하지만 브라우저 기본 스크롤은 트리거하지
  않을 수 있습니다. 일반 웹페이지는 **Scroll 모드**가 가장 확실합니다.
- WASM 실행이 막히는 아주 엄격한 CSP 사이트에서는 손 인식이 안 될 수 있습니다.
  매니페스트에 `wasm-unsafe-eval` 을 넣어 확장 컨텍스트는 허용해 두었습니다.
- 카메라 권한은 **사이트 단위**입니다. 발표용으로 쓸 사이트에서 한 번 허용해 두세요.
- MediaPipe 모델/런타임(약 17MB)은 확장에 **로컬 번들**되어 실행 중 네트워크를 쓰지 않습니다.
```
