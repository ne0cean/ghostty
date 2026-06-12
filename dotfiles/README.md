# Ghostty dotfiles — ne0cean

## 문제
`paste_from_clipboard` keybind action은 텍스트 전용.
이미지만 있는 클립보드(스크린샷 등)에서 Cmd+V → 아무것도 안 붙음.

**간헐적 동작 원인**: 앱마다 복사 시 클립보드에 담는 타입이 다름
- Finder 파일 복사 → PNG + file-url(텍스트) 동시 → 됨
- macOS 스크린샷 캡처 → PNG만 → 안됨

## 수정 내용

### `config/ghostty`
- `clipboard-paste-bracketed-safe = false` 추가
- `keybind = super+v=paste_from_clipboard` 제거 (macOS Service가 처리)

### `scripts/img-paste`
Cmd+V 대체 스크립트. macOS Automator Service로 등록.

- 클립보드 = 이미지만 → `/tmp/clipboard_img_out.png` 저장 후 경로 입력
- 클립보드 = 텍스트 → 기존과 동일하게 paste

## 설치

```bash
# 스크립트 설치
cp scripts/img-paste ~/bin/img-paste
chmod +x ~/bin/img-paste

# ghostty config 적용
cp config/ghostty ~/.config/ghostty/config

# macOS App Shortcut 등록 (Ghostty에서 Cmd+V → img-paste)
defaults write com.mitchellh.ghostty NSUserKeyEquivalents -dict-add "Paste Image Path" '@v'

# Automator Service 설치 후 서비스 캐시 갱신
/System/Library/CoreServices/pbs -update
```

Automator Service (`Paste Image Path.workflow`)는 `~/Library/Services/`에 설치 필요.
