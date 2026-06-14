#!/usr/bin/env zsh
# test/run.sh — zsh-integration.zsh 단위 테스트
# 실행: zsh test/run.sh
# 실패 시 비-0 exit

# NO_UNSET은 소스 로드 실패를 유발하므로 사용 안 함
SSH_CONNECTION="${SSH_CONNECTION:-}"
GHOSTTY_RESOURCES_DIR="${GHOSTTY_RESOURCES_DIR:-}"

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${DOTFILES}/zsh-integration.zsh"

# ── 테스트 헬퍼 ─────────────────────────────
_pass=0
_fail=0

_ok() {
    _pass=$(( _pass + 1 ))
    print -P "%F{green}PASS%f  $1"
}

_fail_test() {
    _fail=$(( _fail + 1 ))
    print -P "%F{red}FAIL%f  $1"
    [[ -n "${2:-}" ]] && print "       got:      $2"
    [[ -n "${3:-}" ]] && print "       expected: $3"
}

_assert_eq() {
    local label="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
        _ok "$label"
    else
        _fail_test "$label" "$got" "$want"
    fi
}

_assert_not_empty() {
    local label="$1" got="$2"
    if [[ -n "$got" ]]; then
        _ok "$label"
    else
        _fail_test "$label" "(empty)" "(non-empty value)"
    fi
}

_assert_numeric() {
    local label="$1" got="$2"
    if [[ "$got" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        _ok "$label"
    else
        _fail_test "$label" "$got" "(numeric)"
    fi
}

# ── 소스 로드 ─────────────────────────────────
# zle 의존 부분이 비인터랙티브 셸에서 오류 낼 수 있으므로 zle 모의
zle() { : }
add-zsh-hook() { : }
autoload() { : }
# 실제 소스
source "$SRC" || {
    print "ERROR: source $SRC 실패"
    exit 1
}

# ═══════════════════════════════════════════════
# 작업 1 — 트리거 파서 테스트
# ═══════════════════════════════════════════════
print "\n── 작업 1: 트리거 파서 ──────────────────────"

# _ghostty_parse_trigger_line 존재 확인
if ! type _ghostty_parse_trigger_line &>/dev/null; then
    _fail_test "_ghostty_parse_trigger_line 함수 존재" "(없음)" "(함수)"
else
    _ok "_ghostty_parse_trigger_line 함수 존재"
fi

# 테스트 1-1: 기본 cmd, 공백 여러 개
unset _pt_type _pt_pattern _pt_action _pt_arg 2>/dev/null || true
_ghostty_parse_trigger_line "cmd:npm*   notify npm"
_assert_eq "1-1 type"    "${_pt_type:-}"    "cmd"
_assert_eq "1-1 pattern" "${_pt_pattern:-}" "npm*"
_assert_eq "1-1 action"  "${_pt_action:-}"  "notify"
_assert_eq "1-1 arg"     "${_pt_arg:-}"     "npm"

# 테스트 1-2: 패턴에 공백 포함 (go build*)
unset _pt_type _pt_pattern _pt_action _pt_arg 2>/dev/null || true
_ghostty_parse_trigger_line "cmd:go build*   notify Go"
_assert_eq "1-2 type"    "${_pt_type:-}"    "cmd"
_assert_eq "1-2 pattern" "${_pt_pattern:-}" "go build*"
_assert_eq "1-2 action"  "${_pt_action:-}"  "notify"
_assert_eq "1-2 arg"     "${_pt_arg:-}"     "Go"

# 테스트 1-3: exit:!0 bell (arg 없음)
unset _pt_type _pt_pattern _pt_action _pt_arg 2>/dev/null || true
_ghostty_parse_trigger_line "exit:!0   bell"
_assert_eq "1-3 type"    "${_pt_type:-}"    "exit"
_assert_eq "1-3 pattern" "${_pt_pattern:-}" "!0"
_assert_eq "1-3 action"  "${_pt_action:-}"  "bell"
_assert_eq "1-3 arg"     "${_pt_arg:-}"     ""

# 테스트 1-4: 주석 라인 → type=""
unset _pt_type _pt_pattern _pt_action _pt_arg 2>/dev/null || true
_ghostty_parse_trigger_line "# 이건 주석"
_assert_eq "1-4 주석 → type 빈값" "${_pt_type:-}" ""

# 테스트 1-5: 빈 라인 → type=""
unset _pt_type _pt_pattern _pt_action _pt_arg 2>/dev/null || true
_ghostty_parse_trigger_line ""
_assert_eq "1-5 빈줄 → type 빈값" "${_pt_type:-}" ""

# 테스트 1-6: yarn 패턴 (공백 없는 일반 케이스)
unset _pt_type _pt_pattern _pt_action _pt_arg 2>/dev/null || true
_ghostty_parse_trigger_line "cmd:yarn*  notify yarn"
_assert_eq "1-6 type"    "${_pt_type:-}"    "cmd"
_assert_eq "1-6 pattern" "${_pt_pattern:-}" "yarn*"
_assert_eq "1-6 action"  "${_pt_action:-}"  "notify"
_assert_eq "1-6 arg"     "${_pt_arg:-}"     "yarn"

# ═══════════════════════════════════════════════
# 작업 2 — EPOCHREALTIME + 소요시간 포맷 테스트
# ═══════════════════════════════════════════════
print "\n── 작업 2: EPOCHREALTIME + 소요시간 포맷 ──"

# 2-1: zsh/datetime 로드 후 EPOCHREALTIME 이 숫자인지
zmodload zsh/datetime 2>/dev/null
_assert_numeric "2-1 EPOCHREALTIME 숫자" "${EPOCHREALTIME:-}"

# 2-2: _ghostty_format_duration 함수 존재 확인
if ! type _ghostty_format_duration &>/dev/null; then
    _fail_test "_ghostty_format_duration 함수 존재" "(없음)" "(함수)"
else
    _ok "_ghostty_format_duration 함수 존재"
fi

# 2-3: 46.2초 포맷 확인 (start=100.0, end=146.2)
result="$(_ghostty_format_duration 100.0 146.2)"
_assert_eq "2-3 46.2s 포맷" "$result" "46.2s"

# 2-4: 1분 이상 (start=0, end=125.0 → 2m5s)
result="$(_ghostty_format_duration 0 125.0)"
_assert_eq "2-4 2m5s 포맷" "$result" "2m5s"

# 2-5: 1초 미만 ms 포맷 (start=0, end=0.345)
result="$(_ghostty_format_duration 0 0.345)"
_assert_eq "2-5 345ms 포맷" "$result" "345ms"

# ═══════════════════════════════════════════════
# 작업 3 — _ghostty_repo_name 테스트
# ═══════════════════════════════════════════════
print "\n── 작업 3: _ghostty_repo_name ──────────────"

# 3-1: 함수 존재 확인
if ! type _ghostty_repo_name &>/dev/null; then
    _fail_test "_ghostty_repo_name 함수 존재" "(없음)" "(함수)"
else
    _ok "_ghostty_repo_name 함수 존재"
fi

# 3-2: git 레포 내에서 → 레포명 반환
_git_tmp="$(mktemp -d /tmp/test-ghostty-gitrepo-XXXX)"
git -C "$_git_tmp" init -q
old_pwd="$PWD"
cd "$_git_tmp"
result="$(_ghostty_repo_name)"
cd "$old_pwd"
_assert_eq "3-2 git 레포 → 레포명" "$result" "$(basename "$_git_tmp")"
rm -rf "$_git_tmp"

# 3-3: 비git 경로 → 디렉토리명 반환
_plain_tmp="$(mktemp -d /tmp/test-ghostty-plain-XXXX)"
cd "$_plain_tmp"
result="$(_ghostty_repo_name)"
cd "$old_pwd"
_assert_eq "3-3 비git 경로 → 디렉토리명" "$result" "$(basename "$_plain_tmp")"
rm -rf "$_plain_tmp"

# 3-4: HOME 디렉토리 → "~" 반환
cd "$HOME"
result="$(_ghostty_repo_name)"
cd "$old_pwd"
_assert_eq "3-4 HOME → ~" "$result" "~"

# ═══════════════════════════════════════════════
# 결과 요약
# ═══════════════════════════════════════════════
print "\n══════════════════════════════════════════════"
total=$(( _pass + _fail ))
print "결과: ${_pass}/${total} 통과"
if (( _fail > 0 )); then
    print -P "%F{red}실패: ${_fail}개%f"
    exit 1
else
    print -P "%F{green}모두 통과%f"
    exit 0
fi
