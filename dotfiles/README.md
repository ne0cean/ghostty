# Ghostty dotfiles — ne0cean

## 터미널 이미지 붙여넣기 정리

### 핵심: 터미널은 이미지를 직접 받을 수 없다
TTY는 텍스트/바이트만 받는다. 이미지를 쓰려면 (a) 앱이 클립보드를 직접 읽거나,
(b) 파일로 저장해 *경로*를 넘기는 두 가지뿐이다.

### Claude Code / AI CLI → `Ctrl+V`
Claude Code는 클립보드 이미지를 **자체적으로** 읽는다.
공식 문서: *"ctrl+v 로 붙여넣기 (cmd+v 쓰지 말 것)"*.
- `Cmd+V`(super+v)는 Ghostty 기본값이 `paste_from_clipboard`(텍스트 전용) → 이미지 유실
- `Ctrl+V`는 Ghostty가 raw `0x16`으로 그대로 TTY에 전달 → Claude Code가 이미지 처리
- **추가 설정 불필요.** 그냥 Ctrl+V.

> 이전 가설(`paste_from_clipboard`를 스크립트로 대체)은 틀렸음 —
> Ghostty keybind에는 외부 스크립트 실행 액션이 없고, 대상(Claude Code)이
> 클립보드를 직접 읽으므로 가로챌 필요가 없다.

### 그 외(vim/cp/스크립트 인자) → `Cmd+Shift+V` (img-paste 백업)
이미지의 *파일 경로*가 필요할 때 쓰는 백업.
`Cmd+Shift+V` → Ghostty가 `C-x C-v`(`\x18\x16`) 전송 → zsh 위젯이
클립보드 이미지를 `/tmp/clipboard_img_out.png`에 저장(항상 덮어쓰기, 누적 없음) 후
경로를 커맨드라인에 삽입.

## 파일
- `config/ghostty` — `keybind = cmd+shift+v=text:\x18\x16`
- `scripts/img-paste` — 클립보드 이미지 저장 + 경로 출력 (`--save`/`--auto`/`--check`)
- `zsh-integration.zsh` — `_img_paste_widget` ZLE 위젯 + `bindkey '^X^V'`

## 설치
```bash
# 스크립트 (PATH 안의 ~/.local/bin)
cp scripts/img-paste ~/.local/bin/img-paste && chmod +x ~/.local/bin/img-paste

# ghostty config + zsh 통합
cp config/ghostty ~/.config/ghostty/config
cp zsh-integration.zsh ~/.config/ghostty/zsh-integration.zsh

# 적용: Ghostty 설정 리로드(cmd+shift+,) + 새 셸(또는 source ~/.zshrc)
```
