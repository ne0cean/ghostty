# 터미널 인라인 이미지 / 그래픽 프로토콜 — Ghostty 판단용 리포트

생성: 2026-06-14 16:1x KST
방법: deep-research 워크플로(17 소스/69 주장 추출) + **로컬 Ghostty 1.3.1 바이너리 실측**

> ⚠️ **검증 주의**: deep-research의 적대적 검증 단계가 rate-limit으로 전부 실패(vote 0-0)해
> 워크플로 자체는 "25개 주장 모두 killed"로 보고함. **이는 실제 반증이 아니라 검증 미수행**이다.
> 대신 아래 핵심 주장은 **로컬 Ghostty 바이너리 strings/terminfo로 직접 검증**했고,
> 1차 출처(GitHub discussions, ghostty.org/docs, mitchellh)가 서로 일관된다.

---

## 핵심 발견 (지원 여부 명확 구분)

### ✅ 확인됨 (로컬 실측 + 1차 출처 일치)
- **Ghostty는 kitty graphics protocol을 구현한다.**
  - 로컬 실측: `/Volumes/Ghostty/Ghostty.app/.../ghostty` 바이너리에 문자열
    `Kitty Graphics`, `_Gi=1,a=q`(kitty graphics 쿼리 APC 시퀀스), `(Kitty graphics are disabled)` 토글 존재.
  - 출처: ghostty.org/docs/features, mitchellh 트윗(libghostty + GUI 지원), GH discussions #2496/#3054/#5218/#7350, HN #45801643.
- **kitten icat 가 Ghostty에서 동작한다.** (GH discussion #7350 — Ghostty 1.1.4 macOS에서 icat로 PNG 렌더 버그 재현, 즉 렌더 자체는 됨.)

### ✅ 확인됨 — 미지원 (1차 출처 일관, 강함)
- **Sixel 미지원.** mitchellh가 명시적으로 구현 안 하기로 결정(GH #2496, HN #45801643). kitty graphics를 선호.
- **iTerm2 inline image protocol(OSC 1337) 미지원.** (GH discussion #3054 — WezTerm은 둘 다 지원하나 Ghostty는 kitty만.)

### ⚠️ 불확실 / 부분 (1차 출처 있으나 로컬 미검증)
- **kitty graphics 중 애니메이션 프레임(a=f, 다중 프레임)은 미구현.** 메타 추적 이슈 #8272(2025-08-18 open)에 pause/load frame/composite frame이 미해결 서브이슈로 남음. (정적 이미지엔 영향 없음.)
- **문서 불완전**: 메인테이너가 kitty graphics 지원 범위 문서가 불완전하다고 인정(#5218).

### 도구별 프로토콜 의존성 (출처: chafa releases, timg 블로그, rasterm)
- **chafa** — kitty/sixel/iTerm2 모두 지원, 최근 릴리스에서 **Ghostty 명시 지원 추가(기본 kitty)**. brew `chafa 1.18.2` 설치 가능.
- **timg** — kitty/sixel/iTerm2 자동 감지, 없으면 24-bit 유니코드 블록 폴백.
- **kitten icat** — kitty 전용(kitty 패키지 동봉).
- **viu** — (조사됨, Ghostty 동작은 미확정).

### 로컬 도구 설치 현황
- kitten/icat/timg/chafa/viu/wezterm **전부 미설치**. (`brew install chafa` 또는 `timg` 즉시 가능.)

---

## 클립보드 이미지를 터미널에 넣는 3접근 (이번 세션 실측 포함)
- **(a) 파일 저장 후 경로** — TTY는 이미지 바이트 직접 수신 불가. `img-paste`가 클립보드 PNG를 /tmp 저장 후 경로를 pbcopy. Claude Code엔 절대경로 텍스트=100% 공식 지원. ✅ 이번 세션 실측 동작.
- **(b) 앱이 클립보드 직접 read** — Claude Code는 **Ctrl+V**(Cmd+V 아님)로 클립보드 이미지 직접 첨부. ⚠️ 단, **한글 IME가 Ctrl+V를 가로채면 'ㅍ/v'로 입력돼 실패** (이번 세션 실제 발생). 영문 상태에서 Ctrl+V 필요.
- **(c) 인라인 그래픽 프로토콜 렌더** — kitty graphics로 icat/timg/chafa가 터미널에 *표시*만. 받아서 처리는 불가(보기 전용).

---

## 권고: 인라인 이미지 표시 기능을 툴킷에 추가할까?

**조건부 YES — 단, "표시(view)" 목적에 한해, 얇은 래퍼로.**

- **할 것**: `scripts/ghostty-icat` 같은 얇은 래퍼 — `chafa`(또는 timg) 존재 시 그걸로 이미지/PDF 썸네일을 터미널에 표시, 없으면 안내. kitty graphics가 Ghostty에 **실재 확인**되므로 표시는 실제로 된다. 비용 낮음(brew 1개 + 스크립트 1개), 기존 img-paste(저장/경로)와 역할 분리됨(표시 vs 첨부).
- **하지 말 것**: 애니메이션/동영상 의존 기능(미구현 #8272), Sixel/iTerm2 프로토콜 가정(미지원). "클립보드 이미지를 Claude Code에 넣기"는 인라인 표시와 **별개 문제** — 그건 img-paste 경로방식/Ctrl+V로 이미 해결, 인라인 렌더로 풀리지 않음.
- **선결 검증(적용 전)**: `brew install chafa` 후 실제 Ghostty에서 `chafa some.png`로 렌더 확인 1회. (GUI 표시는 사용자 눈 검증 필요 — 코드/strings로는 거기까지 보장 못 함.)

## 미해결 / 다음
- 적대적 검증을 rate-limit 없이 재실행하면 위 ⚠️ 항목(애니/문서) 확정 가능.
- chafa 실제 렌더 스모크 테스트(brew 설치 후).
