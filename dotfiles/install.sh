#!/usr/bin/env bash
# install.sh — Ghostty dotfiles 설치 + 검증 (재현 가능)
# registry가 약속한 기능이 실제로 작동하도록 스크립트 PATH 설치 + config 배치 + 검증.
# 멱등(idempotent): 여러 번 실행해도 안전.

set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
CFG_DIR="${HOME}/.config/ghostty"
GHOSTTY="/Volumes/Ghostty/Ghostty.app/Contents/MacOS/ghostty"
[ -x "$GHOSTTY" ] || GHOSTTY="$(command -v ghostty || echo ghostty)"

echo "═══ Ghostty dotfiles 설치 ═══"
mkdir -p "$BIN_DIR" "$CFG_DIR"

# 1) 스크립트 PATH 설치 (registry가 명령으로 약속한 것들)
echo "[1] 스크립트 → $BIN_DIR"
for s in ghostty-broadcast ssht ghostty-help ghostty-tip img-paste; do
  cp "$DOTFILES/scripts/$s" "$BIN_DIR/$s" && chmod +x "$BIN_DIR/$s" && echo "    ✅ $s"
done

# 2) config / zsh 통합 / registry / triggers 배치
echo "[2] config 파일 → $CFG_DIR"
for f in config/ghostty zsh-integration.zsh features-registry.conf triggers; do
  dest="$CFG_DIR/$(basename "$f")"
  [ "$f" = "config/ghostty" ] && dest="$CFG_DIR/config"
  cp "$DOTFILES/$f" "$dest" && echo "    ✅ $(basename "$dest")"
done

# 3) PATH 보장 안내
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "    ⚠️  $BIN_DIR 가 PATH에 없음 — .zshrc 에 추가 필요:"
     echo "        export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# 4) zsh 통합 소싱 안내
if ! grep -q 'zsh-integration.zsh' "${HOME}/.zshrc" 2>/dev/null; then
  echo "    ⚠️  .zshrc 에 다음 줄 필요:"
  echo '        [[ -n "$GHOSTTY_RESOURCES_DIR" ]] && source ~/.config/ghostty/zsh-integration.zsh'
fi

# 5) 검증
echo "[3] 검증"
ok=1
for s in ghostty-broadcast ssht ghostty-help ghostty-tip img-paste; do
  command -v "$s" >/dev/null && echo "    ✅ $s 설치됨" || { echo "    ❌ $s 안됨"; ok=0; }
done
command -v fzf >/dev/null && echo "    ✅ fzf (ghostty-help/tip 의존)" \
  || echo "    ⚠️  fzf 없음 → ghostty-help/tip 작동 불가 (brew install fzf)"
out="$("$GHOSTTY" +validate-config --config-file="$CFG_DIR/config" 2>&1)"
[ -z "$out" ] && echo "    ✅ config 검증 통과" || { echo "    ❌ config: $out"; ok=0; }

echo ""
[ "$ok" = 1 ] && echo "✅ 설치 완료. Ghostty 재시작/리로드(super+shift+,) + 새 셸." \
              || echo "⚠️  일부 항목 실패 — 위 ❌ 확인."
