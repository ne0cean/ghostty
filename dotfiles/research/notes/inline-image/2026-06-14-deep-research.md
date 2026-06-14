# 터미널 인라인 이미지 / 그래픽 프로토콜 — Ghostty 판단용 리포트

생성: 2026-06-14 (20:00 재실행본 — 적대검증 정상 작동)
방법: deep-research 워크플로(12 소스→50 주장→25 검증→**9 confirmed**) + 로컬 Ghostty 1.3.1 바이너리 실측

> ✅ 이 버전은 이전 두 번(rate-limit으로 검증 0-0 전멸)과 달리 **적대검증이 실제 작동**(vote 2-0/3-0).
> 핵심 주장은 1차 출처(ghostty.org/docs, GH discussions, 릴리스 노트) + 로컬 바이너리로 교차확정.

---

## 핵심 발견 (지원 여부 명확 구분)

### ✅ 확인됨 (high confidence)
- **kitty graphics protocol = Ghostty의 유일/주력 인라인 이미지 솔루션.** vote 2-0/3-0.
  - 1차: ghostty.org/docs/features("Ghostty supports the Kitty graphics protocol...render images directly").
  - 로컬 실측: 바이너리에 `Kitty Graphics`, `_Gi=1,a=q`, `(Kitty graphics are disabled)` 문자열.
  - `kitten icat path/to/file.png` 가 Ghostty에서 인라인 렌더 (GH #8948, #5774, #7350).
  - 전송 지원: PNG/JPG/GIF/BMP/TIFF/WEBP.
  - **경계**: kitty와 완전 동등은 아님 — 애니메이션 프레임 미지원, 일부 CSI/OSC 미구현 로깅.

- **Sixel 미지원 — 설계상 거부(MISSING by design).** vote 2-0/3-0.
  - mitchellh 명시(GH #2496, 2024-11-22): "Ghostty will not support sixels." 이유: libsixel 품질 문제, 엣지케이스 다수, kitty가 미래 프로토콜.
  - 1.3.0(2026-03) 릴리스 노트에도 Sixel 추가 없음 — 18개월+ 입장 유지.

### ⚠️ 불확실하나 유력 (medium) — 미지원 쪽
- **iTerm2 OSC 1337 이미지 렌더 미지원.** OSC 1337은 *파싱*은 되나 이미지 *렌더* 미구현(1.3.0 릴리스 노트 + GH #3054). 검증 vote는 0-0(불충분)이라 medium.

### 🐞 툴킷에 직결되는 실제 버그 (high, 확정)
- **파일전송 모드 임시파일 이름 강제 버그.** Ghostty가 경로에 `tty-graphics-protocol` 문자열이 없으면 `EINVAL: temporary file not named correctly`로 거부(GH #5536, pixcat가 1.1에서 깨짐). kitty 스펙은 그 문자열을 *삭제 전 안전가드*로만 요구하는데 Ghostty(PR #4451)가 *읽기 게이트*로 잘못 강제한 게 근본원인.
  - **실무 결론**: 파일모드(t=f) 말고 **스트림/직접 전송(a=T,t=d)** 쓰는 도구를 택하라.

### 도구별 (tools work ONLY when emitting kitty protocol)
- **chafa** — `chafa -f kitty`로 명시 지정 시 Ghostty 렌더 (GH #3054, low vote=plausible). brew `chafa 1.18.2`.
- **timg / viu / wezterm imgcat** — kitty 프로토콜로 출력하게 설정될 때만 동작. Sixel/iTerm2 출력은 Ghostty에서 안 됨.
- **kitten icat** — kitty 전용, 동작 확정.
- (주의: 각 도구가 Ghostty를 *자동감지*하는지 vs `-f kitty` 강제 필요한지는 미확정 — 적용 시 확인.)

### tmux 경유 (참고)
- kitty 이미지가 tmux 안에서도 되나 **유니코드 플레이스홀더 + tmux passthrough 래핑** 필요(`allow-passthrough on`). 중첩 tmux는 깨짐.

---

## 클립보드 이미지 3접근 (이번 세션 실측 우선)
> ⚠️ deep-research에서 이 항목 주장들은 검증 미통과(0-0). 아래는 **이번 세션 로컬 실측**이 근거.
- **(a) 파일 저장 후 경로** — `img-paste`가 클립보드 PNG를 /tmp 저장 + 경로 pbcopy. Claude Code엔 절대경로 텍스트=100% 동작(실측). ✅
- **(b) 앱이 클립보드 직접 read** — Claude Code는 **Ctrl+V**(Cmd+V 아님). ⚠️ **한글 IME가 Ctrl+V 가로채면 'ㅍ/v' 입력돼 실패**(이번 세션 실제 발생). 영문 상태 필수. → [[lesson_claude_code_image_paste_ctrl_v]]
- **(c) 인라인 그래픽 렌더** — kitty로 icat/chafa가 *표시*만. 첨부/처리는 불가(보기 전용).

---

## 권고: 인라인 이미지 표시 기능 추가?

**조건부 YES — kitty-protocol-first, 스트림 모드, "표시 전용".**

- **할 것**: `scripts/ghostty-icat` 얇은 래퍼 — `chafa`(또는 timg) 존재 시 `-f kitty`로 이미지/PDF 썸네일 표시, 없으면 안내. kitty graphics 실재 확인됨 → 실제 렌더됨.
- **반드시 지킬 것**:
  1. **kitty 프로토콜만** 가정(Sixel/iTerm2 금지 — 미지원 확정).
  2. **스트림/직접 전송** 선호(파일모드 EINVAL 버그 회피).
  3. tmux 안에서 쓸 거면 passthrough 설정 필요.
- **하지 말 것**: 애니메이션/동영상 의존, 파일전송 모드 의존. "클립보드→Claude Code 첨부"는 인라인 표시와 **별개 문제**(img-paste/Ctrl+V로 이미 해결).
- **선결(적용 전 1회)**: `brew install chafa` → 실제 Ghostty에서 `chafa -f kitty some.png` 렌더 확인(GUI는 사용자 눈 검증).

## 미검증 / 다음
- 파일이름 EINVAL 버그가 현재 1.3.x에도 남아있는지(스트림 강제 필요 여부 결정).
- timg/viu/wezterm imgcat의 Ghostty 자동감지 vs `-f kitty` 강제 필요 여부.
- 프로토콜 성능/인코딩 비교 수치(질문 #1) — 블로그 출처라 전부 검증 탈락, 미확정.
- macOS 폰트/셀크기/자동감지 주의점(질문 #5) — 생존 주장 없음, 미커버.
