#!/usr/bin/env zsh
# Ghostty ZSH Integration
# source this in ~/.zshrc:
#   [[ -n "$GHOSTTY_RESOURCES_DIR" ]] && source ~/.config/ghostty/zsh-integration.zsh

# ──────────────────────────────────────────
# 1. LINE TIMESTAMPS  (iTerm2 equivalent)
#    커맨드 실행 시각 + 소요 시간 표시
# ──────────────────────────────────────────
_ghostty_cmd_start=0
_ghostty_last_cmd=""

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

        # 소요 시간 포맷 (1분 이상이면 m:ss)
        local duration
        if (( elapsed >= 60 )); then
            local m=$(( int(elapsed / 60) ))
            local s=$(( int(elapsed % 60) ))
            duration="${m}m${s}s"
        elif (( elapsed >= 1 )); then
            duration="${elapsed:.1f}s"
        else
            local ms=$(( int(elapsed * 1000) ))
            duration="${ms}ms"
        fi

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

_ghostty_run_triggers() {
    local cmd="$1"
    local exit_code="$2"
    [[ ! -f "$GHOSTTY_TRIGGERS_FILE" ]] && return

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 주석/빈줄 스킵
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        local type pattern action arg
        type="${line%%:*}"
        rest="${line#*:}"
        pattern="${rest%% *}"
        action_full="${rest#* }"
        action="${action_full%% *}"
        arg="${action_full#* }"
        [[ "$arg" == "$action" ]] && arg=""

        local matched=0
        case "$type" in
            cmd)
                [[ "$cmd" == ${~pattern} ]] && matched=1
                ;;
            exit)
                if [[ "$pattern" == "!0" ]]; then
                    (( exit_code != 0 )) && matched=1
                elif [[ "$pattern" == "$exit_code" ]]; then
                    matched=1
                fi
                ;;
        esac

        if (( matched )); then
            case "$action" in
                notify)
                    local title="${arg:-Ghostty}"
                    osascript -e "display notification \"${cmd}\" with title \"${title}\"" 2>/dev/null &
                    ;;
                bell)
                    print -n "\a"
                    ;;
                run)
                    [[ -n "$arg" ]] && eval "$arg" &
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
    # SSH 세션이면 배경색 변경 (OSC 11)
    if [[ -n "$SSH_CONNECTION" ]]; then
        # 원격: 약간 붉은 배경으로 구분
        printf '\e]11;#1a0d0d\a'
    fi
}
_ghostty_profile_switch
