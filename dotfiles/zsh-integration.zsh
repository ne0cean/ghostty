#!/usr/bin/env zsh
# Ghostty ZSH Integration
# source this in ~/.zshrc:
#   [[ -n "$GHOSTTY_RESOURCES_DIR" ]] && source ~/.config/ghostty/zsh-integration.zsh

# EPOCHREALTIME 사용을 위해 zsh/datetime 모듈 보장 (이미 로드돼 있으면 무해)
zmodload zsh/datetime 2>/dev/null || true

# ──────────────────────────────────────────
# 1. LINE TIMESTAMPS  (iTerm2 equivalent)
#    커맨드 실행 시각 + 소요 시간 표시
# ──────────────────────────────────────────
_ghostty_cmd_start=0
_ghostty_last_cmd=""

# 소요 시간 포맷 함수 (start, end 부동소수점 → "46.2s" / "2m5s" / "345ms")
_ghostty_format_duration() {
    local start="$1" end="$2"
    local elapsed
    elapsed=$(( end - start ))
    if (( elapsed >= 60 )); then
        local m=$(printf '%.0f' "$(( elapsed / 60 ))")
        local s=$(printf '%.0f' "$(( elapsed - m * 60 ))")
        print "${m}m${s}s"
    elif (( elapsed >= 1 )); then
        printf "%.1fs\n" "$elapsed"
    else
        local ms=$(printf '%.0f' "$(( elapsed * 1000 ))")
        print "${ms}ms"
    fi
}

_ghostty_preexec() {
    _ghostty_cmd_start=$EPOCHREALTIME
    _ghostty_last_cmd="$1"

    # Broadcast 모드 활성 시 커맨드를 다른 터미널에 복제
    local flag="/tmp/ghostty-broadcast-$(id -u).active"
    local sender_file="/tmp/ghostty-broadcast-$(id -u).sender"
    if [[ -f "$flag" && -f "$sender_file" ]]; then
        local sender_tty
        sender_tty=$(cat "$sender_file" 2>/dev/null)
        if [[ "$(tty)" == "$sender_tty" ]]; then
            # 현재 터미널이 sender → 다른 TTY에 전송
            local me="$(whoami)"
            for tty_path in /dev/ttys*; do
                [[ ! -c "$tty_path" || ! -w "$tty_path" ]] && continue
                [[ "$tty_path" == "$(tty)" ]] && continue
                owner=$(stat -f '%Su' "$tty_path" 2>/dev/null)
                [[ "$owner" != "$me" ]] && continue
                printf '%s\r' "$1" > "$tty_path" 2>/dev/null || true
            done
        fi
    fi
}

_ghostty_precmd() {
    local exit_code=$?

    # 실행된 커맨드가 있을 때만 타임스탬프 출력
    if (( _ghostty_cmd_start > 0 )); then
        local end=$EPOCHREALTIME
        local elapsed=$(( end - _ghostty_cmd_start ))
        local timestamp=$(date '+%H:%M:%S')

        # 소요 시간 포맷 (공통 함수 사용)
        local duration
        duration="$(_ghostty_format_duration "$_ghostty_cmd_start" "$end")"

        # 종료코드에 따라 색상 결정
        local status_color
        if (( exit_code == 0 )); then
            status_color="%F{green}✓%f"
        else
            status_color="%F{red}✗ ${exit_code}%f"
        fi

        # 타임스탬프 라인 출력 (프롬프트 위에)
        print -P "%F{240}─── ${timestamp} ${status_color} %F{240}${duration}%f"

        # Triggers 실행
        _ghostty_run_triggers "$_ghostty_last_cmd" "$exit_code"

        # 상황맞춤형 힌트 (30초 이상 걸린 커맨드 또는 특정 패턴)
        _ghostty_maybe_hint "$_ghostty_last_cmd" "$exit_code" "$elapsed"
    fi

    _ghostty_cmd_start=0
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _ghostty_preexec
add-zsh-hook precmd  _ghostty_precmd

# ──────────────────────────────────────────
# 2. TRIGGERS  (iTerm2 equivalent)
#    커맨드 패턴/종료코드 → 자동 액션
#    설정: ~/.config/ghostty/triggers
#
#    포맷:
#      cmd:<pattern>  <action> [arg]
#      exit:<code>    <action> [arg]
#      exit:!0        <action> [arg]   # 0 아닌 모든 코드
#
#    액션:
#      notify [title]   macOS 알림
#      bell             터미널 벨
#      run <script>     스크립트 실행
# ──────────────────────────────────────────
GHOSTTY_TRIGGERS_FILE="${HOME}/.config/ghostty/triggers"

# 트리거 라인 파서
# 형식: TYPE:PATTERN  ACTION [ARG]
# ACTION은 notify|bell|run 중 하나 — 이 키워드를 기준으로 PATTERN과 ARG 분리
# 결과: _pt_type, _pt_pattern, _pt_action, _pt_arg (caller 스코프에 저장)
_ghostty_parse_trigger_line() {
    local line="$1"
    _pt_type="" _pt_pattern="" _pt_action="" _pt_arg=""

    # 주석/빈줄
    [[ "$line" =~ ^[[:space:]]*# ]] && return
    [[ -z "${line// }" ]] && return

    # TYPE 추출 (첫 번째 ':' 앞)
    _pt_type="${line%%:*}"
    local rest="${line#*:}"

    # ACTION 키워드(notify|bell|run) 위치를 기준으로 파싱
    # rest = "PATTERN   ACTION [ARG]"
    # notify/bell/run 중 하나를 기준으로 앞=PATTERN, 뒤=ARG
    local action_kw
    local before_kw
    if [[ "$rest" =~ (.*)[[:space:]]+(notify|bell|run)([[:space:]].*)?$ ]]; then
        before_kw="${match[1]}"
        action_kw="${match[2]}"
        local after_kw="${match[3]}"

        # PATTERN: before_kw에서 선행/후행 공백 제거 (## = 1개 이상 공백 제거)
        _pt_pattern="${before_kw#"${before_kw%%[! ]*}"}"
        _pt_pattern="${_pt_pattern%"${_pt_pattern##*[! ]}"}"
        _pt_action="$action_kw"
        # ARG: after_kw의 선행/후행 공백 제거
        _pt_arg="${after_kw#"${after_kw%%[! ]*}"}"
        _pt_arg="${_pt_arg%"${_pt_arg##*[! ]}"}"
    else
        # 매칭 실패 — 파싱 불가
        _pt_type=""
    fi
}

_ghostty_run_triggers() {
    local cmd="$1"
    local exit_code="$2"
    [[ ! -f "$GHOSTTY_TRIGGERS_FILE" ]] && return

    while IFS= read -r line || [[ -n "$line" ]]; do
        local _pt_type _pt_pattern _pt_action _pt_arg
        _ghostty_parse_trigger_line "$line"
        [[ -z "$_pt_type" ]] && continue

        local matched=0
        case "$_pt_type" in
            cmd)
                [[ "$cmd" == ${~_pt_pattern} ]] && matched=1
                ;;
            exit)
                if [[ "$_pt_pattern" == "!0" ]]; then
                    (( exit_code != 0 )) && matched=1
                elif [[ "$_pt_pattern" == "$exit_code" ]]; then
                    matched=1
                fi
                ;;
        esac

        if (( matched )); then
            case "$_pt_action" in
                notify)
                    local title="${_pt_arg:-Ghostty}"
                    osascript -e "display notification \"${cmd}\" with title \"${title}\"" 2>/dev/null &
                    ;;
                bell)
                    print -n "\a"
                    ;;
                run)
                    [[ -n "$_pt_arg" ]] && eval "$_pt_arg" &
                    ;;
            esac
        fi
    done < "$GHOSTTY_TRIGGERS_FILE"
}

# ──────────────────────────────────────────
# 3. PROFILE AUTO-SWITCH (간소화)
#    SSH 세션 감지 시 터미널 배경색 변경
# ──────────────────────────────────────────
_ghostty_profile_switch() {
    if [[ -n "$SSH_CONNECTION" ]]; then
        printf '\e]11;#1a0d0d\a'
    fi
}
_ghostty_profile_switch

# ──────────────────────────────────────────
# 4. TERMINAL TITLE STATE  (OSC 2 — 모든 터미널 호환)
#    현재 상태를 타이틀에 표시
#    정상: 레포명 — dirname
#    broadcast ON: [📡] 레포명 — dirname
#    SSH: [ssh] 레포명 — dirname
# ──────────────────────────────────────────

# 레포/프로젝트명 추출: git 레포 → 레포명, 비git → 디렉토리명 ($HOME이면 "~")
# cmd+d split pane 상단 타이틀에서 프로젝트 식별에 사용
_ghostty_repo_name() {
    if git rev-parse --show-toplevel &>/dev/null 2>&1; then
        basename "$(git rev-parse --show-toplevel)"
    elif [[ "$PWD" == "$HOME" ]]; then
        print "~"
    else
        basename "$PWD"
    fi
}

_ghostty_update_title() {
    local dir
    dir="${PWD/#$HOME/~}"

    local prefix=""
    # broadcast 모드 활성 여부
    local bcast_flag="/tmp/ghostty-broadcast-$(id -u).active"
    local bcast_sender="/tmp/ghostty-broadcast-$(id -u).sender"
    if [[ -f "$bcast_flag" && -f "$bcast_sender" ]]; then
        local sender_tty
        sender_tty=$(cat "$bcast_sender" 2>/dev/null)
        if [[ "$(tty)" == "$sender_tty" ]]; then
            prefix="[📡] "
        else
            prefix="[recv] "
        fi
    elif [[ -n "${SSH_CONNECTION:-}" ]]; then
        prefix="[ssh] "
    fi

    # 레포/프로젝트명 추출
    local repo_name
    repo_name="$(_ghostty_repo_name)"

    # OSC 2: 탭/윈도우 타이틀 설정 (각 split pane별 식별)
    printf '\e]2;%s\a' "${prefix}${repo_name} — ${dir}"
}

# precmd에 타이틀 업데이트 추가
add-zsh-hook precmd _ghostty_update_title

# ──────────────────────────────────────────
# 5. CONTEXTUAL HINTS  (thefuck 패턴)
#    상황에 맞는 기능 힌트를 적절한 시점에 1회 제공
#    쿨다운: 같은 힌트는 하루 1회만
# ──────────────────────────────────────────
GHOSTTY_REGISTRY="${HOME}/.config/ghostty/features-registry.conf"
GHOSTTY_HINT_DIR="/tmp/ghostty-hints-$(id -u)"

_ghostty_maybe_hint() {
    local cmd="$1"
    local exit_code="$2"
    local elapsed="$3"

    [[ ! -f "$GHOSTTY_REGISTRY" ]] && return
    mkdir -p "$GHOSTTY_HINT_DIR" 2>/dev/null || return

    # 레지스트리에서 hint_trigger가 있는 항목만 순회
    while IFS='|' read -r name category when how example hint_trigger; do
        [[ "$name" =~ ^# ]] && continue
        [[ -z "$hint_trigger" ]] && continue

        # 트리거 매칭 확인
        local trigger_type="${hint_trigger%%:*}"
        local trigger_pattern="${hint_trigger#*:}"
        local matched=0

        case "$trigger_type" in
            cmd)
                [[ "$cmd" == ${~trigger_pattern} ]] && matched=1
                ;;
            exit)
                if [[ "$trigger_pattern" == "!0" ]]; then
                    (( exit_code != 0 )) && matched=1
                fi
                ;;
        esac

        (( matched == 0 )) && continue

        # 쿨다운: 오늘 이미 이 힌트를 보여줬으면 스킵
        local hint_stamp="${GHOSTTY_HINT_DIR}/$(echo "$name" | tr ' ()/' '----')-$(date +%Y%m%d)"
        [[ -f "$hint_stamp" ]] && continue

        # 힌트 출력
        touch "$hint_stamp"
        printf '\n\e[2m  💡 관련 기능: \e[0m\e[1m%s\e[0m\e[2m  →  %s\e[0m\n' "$name" "$how"
        printf '\e[2m     ghostty-help 로 전체 기능 보기\e[0m\n\n'

        # 힌트는 1개만 보여주고 중단
        break
    done < "$GHOSTTY_REGISTRY"
}

# precmd 훅에 힌트 추가 (타임스탬프 다음에 실행되도록 _ghostty_precmd 수정)
# → _ghostty_run_triggers 호출 직후에 hints 호출 추가됨 (아래 precmd override)

# ─────────────────────────────────────────────────────────────────────────────
# img-paste 백업 위젯 — 클립보드 이미지의 *파일 경로*를 커맨드라인에 삽입
# 연결: Ghostty `cmd+shift+v=text:\x18\x16` → C-x C-v → 이 위젯
# (Claude Code 등 AI CLI의 이미지 paste는 위젯이 아니라 Ctrl+V 를 쓸 것)
# ─────────────────────────────────────────────────────────────────────────────
_img_paste_widget() {
    local p
    p=$(command img-paste --save 2>/dev/null) || { zle -M "[img-paste] 클립보드에 이미지 없음"; return 0; }
    if [[ -n "$p" ]]; then
        LBUFFER+="$p"
        zle -M "[img-paste] $p"
    fi
    zle redisplay
}
zle -N _img_paste_widget
bindkey '^X^V' _img_paste_widget   # C-x C-v (Ghostty cmd+shift+v 가 전송)
