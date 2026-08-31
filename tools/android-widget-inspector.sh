#!/bin/sh

set -eu

ADB_BIN=${ADB_BIN:-adb}
AIO_PACKAGE=ru.execbit.aiolauncher
INSPECTOR_ACTIVITY="$AIO_PACKAGE/.scripts.appwidgets.AndroidWidgetInspectorEntry"
INTENT_ACTION="$AIO_PACKAGE.INSPECT_ANDROID_WIDGET"
REMOTE_DIR="/sdcard/Android/data/$AIO_PACKAGE/files/android_widget_inspector"
REMOTE_SCRIPTS_DIR="/sdcard/Android/data/$AIO_PACKAGE/files/"
DEFAULT_OUTPUT_DIR="./android-widget-dump"
SERIAL=""
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WRAPPER_VALIDATOR="$SCRIPT_DIR/validate-app-widget-wrapper.sh"

usage() {
    cat <<'EOF'
Usage:
  tools/android-widget-inspector.sh [-s SERIAL] doctor PACKAGE [OUTPUT_DIR]
  tools/android-widget-inspector.sh [-s SERIAL] list PACKAGE [OUTPUT_DIR]
  tools/android-widget-inspector.sh [-s SERIAL] start PROVIDER [SIZE|-] [USER_ID|-] [OUTPUT_DIR]
  tools/android-widget-inspector.sh [-s SERIAL] capture [OUTPUT_DIR]
  tools/android-widget-inspector.sh [-s SERIAL] save STATE [SUITE_DIR] [CONTEXT_JSON]
  tools/android-widget-inspector.sh [-s SERIAL] click HANDLE [OUTPUT_DIR]
  tools/android-widget-inspector.sh [-s SERIAL] verify-click HANDLE PACKAGE ACTIVITY_SUBSTRING|- [OUTPUT_DIR]
  tools/android-widget-inspector.sh [-s SERIAL] verify-state-change HANDLE [OUTPUT_DIR]
  tools/android-widget-inspector.sh [-s SERIAL] scroll HANDLE DIRECTION [OUTPUT_DIR]
  tools/android-widget-inspector.sh [-s SERIAL] replay SCRIPT [OUTPUT_DIR]
  tools/android-widget-inspector.sh [-s SERIAL] replay-snapshot [--allow-synthetic] SCRIPT SNAPSHOT [OUTPUT_DIR]
  tools/android-widget-inspector.sh [-s SERIAL] replay-suite [--allow-synthetic] SCRIPT STATES_DIR [OUTPUT_DIR]
  tools/android-widget-inspector.sh [-s SERIAL] smoke-installed SCRIPT SNAPSHOT [OUTPUT_DIR]
  tools/android-widget-inspector.sh validate-snapshot SCRIPT SNAPSHOT
  tools/android-widget-inspector.sh [-s SERIAL] status [OUTPUT_DIR]
  tools/android-widget-inspector.sh [-s SERIAL] wait [OUTPUT_DIR] [TIMEOUT_SECONDS]
  tools/android-widget-inspector.sh [-s SERIAL] cleanup [OUTPUT_DIR]

The endpoint is exposed through an explicit activity alias protected by Android's
privileged system DUMP permission. ADB's shell user can call it; ordinary apps
cannot. `start` can open the system binding confirmation and the provider's
configuration activity; complete them on the device while this command waits.
Omit SIZE (or pass `-`) for a scrollable widget unless the wrapper intentionally
depends on a fixed size.
EOF
}

if [ "${1:-}" = "-s" ]; then
    [ "$#" -ge 3 ] || { usage >&2; exit 2; }
    SERIAL=$2
    shift 2
fi

adb_cmd() {
    if [ -n "$SERIAL" ]; then
        "$ADB_BIN" -s "$SERIAL" "$@"
    else
        "$ADB_BIN" "$@"
    fi
}

require_device() {
    command -v "$ADB_BIN" >/dev/null 2>&1 || {
        echo "adb is not available (set ADB_BIN if it is not on PATH)" >&2
        exit 1
    }
    state=$(adb_cmd get-state 2>/dev/null || true)
    [ "$state" = "device" ] || {
        echo "No usable ADB device${SERIAL:+ with serial $SERIAL}" >&2
        exit 1
    }
    aio_path=$(adb_cmd shell pm path "$AIO_PACKAGE" 2>/dev/null | head -n 1 | tr -d '\r')
    if [ -z "$aio_path" ]; then
        echo "AIO Launcher is not installed on the selected device" >&2
        exit 1
    fi
}

prepare_output() {
    output_dir=$1
    mkdir -p "$output_dir"
    rm -f \
        "$output_dir/status.json" \
        "$output_dir/providers.json" \
        "$output_dir/snapshot.json" \
        "$output_dir/preview.png" \
        "$output_dir/replay.txt" \
        "$output_dir/device-screen.png" \
        "$output_dir/foreground.txt"
}

remove_remote_file() {
    adb_cmd shell rm -f "$REMOTE_DIR/$1" >/dev/null
}

send_command() {
    command_name=$1
    shift

    # adb shell joins its arguments into a remote shell command. Quote each
    # value so provider names for nested Java classes keep their literal `$`.
    remote_command="am start -W"
    for remote_arg in \
        -n "$INSPECTOR_ACTIVITY" \
        -a "$INTENT_ACTION" \
        --es app_widget_command "$command_name" \
        "$@"; do
        case "$remote_arg" in
            *"'"*)
                echo "Unsupported apostrophe in inspector argument" >&2
                exit 2
                ;;
        esac
        remote_command="$remote_command '$remote_arg'"
    done

    adb_cmd shell "$remote_command" >/dev/null
}

pull_file() {
    file_name=$1
    output_dir=$2
    if adb_cmd pull "$REMOTE_DIR/$file_name" "$output_dir/$file_name" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

pull_artifacts() {
    output_dir=$1
    mkdir -p "$output_dir"
    for file_name in status.json providers.json snapshot.json preview.png replay.txt; do
        pull_file "$file_name" "$output_dir" || true
    done
}

capture_foreground() {
    output_dir=$1
    adb_cmd exec-out screencap -p > "$output_dir/device-screen.png" || true
    adb_cmd shell dumpsys activity activities > "$output_dir/foreground.txt" || true
}

read_foreground_component() {
    foreground_file=$1
    sed -n \
        's/.*topResumedActivity=ActivityRecord{[^ ]* u[0-9][0-9]* \([^ }]*\).*/\1/p' \
        "$foreground_file" | head -n 1
}

validate_wrapper() {
    "$WRAPPER_VALIDATOR" "$1"
}

validate_live_snapshot() {
    snapshot_file=$1
    script_file=$2

    [ -f "$snapshot_file" ] || {
        echo "Snapshot not found: $snapshot_file" >&2
        exit 1
    }
    command -v jq >/dev/null 2>&1 || {
        echo "jq is required to validate snapshot provenance" >&2
        exit 1
    }
    if ! jq -e '
        . as $snapshot |
        type == "object" and
        (.schema_version | type == "number" and . >= 2) and
        ($snapshot.provider | type == "string" and contains("/")) and
        ($snapshot.package_name | type == "string" and length > 0) and
        ($snapshot.provider | startswith($snapshot.package_name + "/")) and
        ($snapshot.app_widget_id | type == "number" and . > 0) and
        ($snapshot.package_version_code | type == "number" and . >= 0) and
        ($snapshot.locale | type == "string" and length > 0) and
        ($snapshot.density_dpi | type == "number" and . > 0) and
        ($snapshot.font_scale | type == "number" and . > 0) and
        ($snapshot.sdk_int | type == "number" and . >= 21) and
        ($snapshot.width | type == "number" and . > 0) and
        ($snapshot.height | type == "number" and . > 0) and
        ($snapshot.generated_at_ms | type == "number" and . >= 1577836800000) and
        ($snapshot.collections | type == "array") and
        ($snapshot.nodes | type == "array")
    ' "$snapshot_file" >/dev/null; then
        echo "Snapshot lacks the live capture metadata emitted by the ADB inspector: $snapshot_file" >&2
        echo "Capture it with start/save, or use --allow-synthetic only for fixture development." >&2
        exit 1
    fi

    expected_package=$(sed -n 's/^-- uses_app = "\([^"]*\)"[[:space:]]*$/\1/p' "$script_file" | head -n 1)
    captured_package=$(jq -r '.package_name' "$snapshot_file")
    if [ -n "$expected_package" ] && [ "$expected_package" != "$captured_package" ]; then
        echo "Wrapper uses_app '$expected_package' does not match captured package '$captured_package'" >&2
        exit 1
    fi
}

perform_click() {
    handle=$1
    output_dir=$2
    mkdir -p "$output_dir"
    rm -f "$output_dir/status.json" "$output_dir/replay.txt"
    remove_remote_file status.json
    send_command click --es app_widget_handle "$handle"
    if wait_for_terminal_state "$output_dir" 30; then
        capture_foreground "$output_dir"
    else
        result=$?
        capture_foreground "$output_dir"
        return "$result"
    fi
}

validate_state_name() {
    state_name=$1
    case "$state_name" in
        ""|*[!A-Za-z0-9._-]*)
            echo "Invalid state name '$state_name'; use letters, digits, dot, dash or underscore" >&2
            exit 2
            ;;
    esac
}

read_state() {
    status_file=$1
    if [ ! -f "$status_file" ]; then
        return
    fi
    sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$status_file" | head -n 1
}

wait_for_terminal_state() {
    output_dir=$1
    timeout_seconds=$2
    elapsed=0
    last_state=""

    while [ "$elapsed" -lt "$timeout_seconds" ]; do
        pull_file status.json "$output_dir" || true
        state=$(read_state "$output_dir/status.json")
        if [ -n "$state" ] && [ "$state" != "$last_state" ]; then
            echo "Inspector state: $state" >&2
            last_state=$state
        fi
        case "$state" in
            ready|error|canceled|cleaned|replay_failed)
                pull_artifacts "$output_dir"
                cat "$output_dir/status.json"
                case "$state" in
                    ready|cleaned) return 0 ;;
                    *) return 1 ;;
                esac
                ;;
        esac
        sleep 1
        elapsed=$((elapsed + 1))
    done

    pull_artifacts "$output_dir"
    echo "Timed out after ${timeout_seconds}s; the inspector operation may still be active" >&2
    [ ! -f "$output_dir/status.json" ] || cat "$output_dir/status.json" >&2
    return 124
}

[ "$#" -ge 1 ] || { usage >&2; exit 2; }
case "$1" in
    -h|--help|help)
        usage
        exit 0
        ;;
esac
command_name=$1
shift

if [ "$command_name" = "validate-snapshot" ]; then
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    validate_wrapper "$1"
    validate_live_snapshot "$2" "$1"
    echo "Live snapshot provenance matches the wrapper: $2"
    exit 0
fi

require_device

case "$command_name" in
    doctor)
        [ "$#" -ge 1 ] && [ "$#" -le 2 ] || { usage >&2; exit 2; }
        package_name=$1
        output_dir=${2:-$DEFAULT_OUTPUT_DIR}
        mkdir -p "$output_dir"
        rm -f "$output_dir/status.json"
        remove_remote_file status.json
        send_command doctor
        wait_for_terminal_state "$output_dir" 30 >/dev/null
        snapshot_schema=$(sed -n \
            's/.*"snapshot_schema_version"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
            "$output_dir/status.json" | head -n 1)
        aio_version=$(adb_cmd shell dumpsys package "$AIO_PACKAGE" \
            | sed -n 's/.*versionName=//p' | head -n 1 | tr -d '\r')
        target_version=$(adb_cmd shell dumpsys package "$package_name" \
            | sed -n 's/.*versionName=//p' | head -n 1 | tr -d '\r')
        target_path=$(adb_cmd shell pm path "$package_name" 2>/dev/null | head -n 1 | tr -d '\r')
        {
            echo "device=$(adb_cmd get-serialno)"
            echo "aio_package=$AIO_PACKAGE"
            echo "aio_version=${aio_version:-unknown}"
            echo "snapshot_schema=${snapshot_schema:-unknown}"
            echo "target_package=$package_name"
            echo "target_version=${target_version:-unknown}"
            echo "target_installed=$([ -n "$target_path" ] && echo true || echo false)"
        } > "$output_dir/doctor.txt"
        cat "$output_dir/doctor.txt"
        [ -n "$target_path" ] || exit 1
        ;;
    list)
        [ "$#" -ge 1 ] && [ "$#" -le 2 ] || { usage >&2; exit 2; }
        package_name=$1
        output_dir=${2:-$DEFAULT_OUTPUT_DIR}
        prepare_output "$output_dir"
        remove_remote_file status.json
        remove_remote_file providers.json
        send_command list --es app_widget_package "$package_name"
        wait_for_terminal_state "$output_dir" 30
        ;;
    start)
        [ "$#" -ge 1 ] && [ "$#" -le 4 ] || { usage >&2; exit 2; }
        provider=$1
        size=${2:--}
        user_id=${3:--}
        output_dir=${4:-$DEFAULT_OUTPUT_DIR}
        prepare_output "$output_dir"
        remove_remote_file status.json
        remove_remote_file snapshot.json
        remove_remote_file preview.png
        if [ "$size" = "-" ] && [ "$user_id" = "-" ]; then
            send_command start --es app_widget_provider "$provider"
        elif [ "$size" = "-" ]; then
            send_command start \
                --es app_widget_provider "$provider" \
                --es app_widget_user_id "$user_id"
        elif [ "$user_id" = "-" ]; then
            send_command start \
                --es app_widget_provider "$provider" \
                --es app_widget_size "$size"
        else
            send_command start \
                --es app_widget_provider "$provider" \
                --es app_widget_size "$size" \
                --es app_widget_user_id "$user_id"
        fi
        wait_for_terminal_state "$output_dir" "${AIO_INSPECT_TIMEOUT:-180}"
        ;;
    capture)
        [ "$#" -le 1 ] || { usage >&2; exit 2; }
        output_dir=${1:-$DEFAULT_OUTPUT_DIR}
        prepare_output "$output_dir"
        remove_remote_file status.json
        remove_remote_file snapshot.json
        remove_remote_file preview.png
        send_command capture
        wait_for_terminal_state "$output_dir" 30
        ;;
    save)
        [ "$#" -ge 1 ] && [ "$#" -le 3 ] || { usage >&2; exit 2; }
        state_name=$1
        validate_state_name "$state_name"
        suite_dir=${2:-$DEFAULT_OUTPUT_DIR}
        context_file=${3:-}
        if [ -n "$context_file" ]; then
            [ -f "$context_file" ] || { echo "Context not found: $context_file" >&2; exit 1; }
            jq -e '
                type == "object" and
                ((has("folded") | not) or (.folded | type == "boolean")) and
                ((has("prefs") | not) or (.prefs | type == "object"))
            ' "$context_file" >/dev/null || {
                echo "Context must be an object with optional boolean folded and object prefs" >&2
                exit 1
            }
        fi
        output_dir="$suite_dir/states/$state_name"
        prepare_output "$output_dir"
        rm -f "$output_dir/context.json"
        remove_remote_file status.json
        remove_remote_file snapshot.json
        remove_remote_file preview.png
        send_command capture
        wait_for_terminal_state "$output_dir" 30
        [ -z "$context_file" ] || cp "$context_file" "$output_dir/context.json"
        ;;
    click)
        [ "$#" -ge 1 ] && [ "$#" -le 2 ] || { usage >&2; exit 2; }
        handle=$1
        output_dir=${2:-$DEFAULT_OUTPUT_DIR}
        perform_click "$handle" "$output_dir"
        component=$(read_foreground_component "$output_dir/foreground.txt")
        echo "Foreground after click: ${component:-unknown}"
        ;;
    verify-click)
        [ "$#" -ge 3 ] && [ "$#" -le 4 ] || { usage >&2; exit 2; }
        handle=$1
        expected_package=$2
        expected_activity=$3
        output_dir=${4:-$DEFAULT_OUTPUT_DIR}
        perform_click "$handle" "$output_dir"
        component=$(read_foreground_component "$output_dir/foreground.txt")
        [ -n "$component" ] || {
            echo "Unable to determine foreground activity after clicking $handle" >&2
            exit 1
        }
        actual_package=${component%%/*}
        [ "$actual_package" = "$expected_package" ] || {
            echo "Click opened '$component'; expected package '$expected_package'" >&2
            exit 1
        }
        if [ "$expected_activity" != "-" ]; then
            case "$component" in
                *"$expected_activity"*) ;;
                *)
                    echo "Click opened '$component'; expected activity containing '$expected_activity'" >&2
                    exit 1
                    ;;
            esac
        fi
        echo "Verified click $handle -> $component"
        ;;
    verify-state-change)
        [ "$#" -ge 1 ] && [ "$#" -le 2 ] || { usage >&2; exit 2; }
        handle=$1
        output_dir=${2:-$DEFAULT_OUTPUT_DIR}
        mkdir -p "$output_dir"
        pull_file snapshot.json "$output_dir" || {
            echo "No active live snapshot; run start or capture first" >&2
            exit 1
        }
        cp "$output_dir/snapshot.json" "$output_dir/before-snapshot.json"
        before_hash=$(jq -S 'del(.generated_at_ms)' "$output_dir/before-snapshot.json" | sha256sum | sed 's/[[:space:]].*//')
        perform_click "$handle" "$output_dir"
        recaptured=$(sed -n 's/.*"recaptured"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$output_dir/status.json" | head -n 1)
        [ "$recaptured" = true ] && [ -f "$output_dir/snapshot.json" ] || {
            echo "Click left the widget instead of producing an in-widget state change" >&2
            exit 1
        }
        after_hash=$(jq -S 'del(.generated_at_ms)' "$output_dir/snapshot.json" | sha256sum | sed 's/[[:space:]].*//')
        [ "$before_hash" != "$after_hash" ] || {
            echo "Click succeeded but the captured widget state did not change" >&2
            exit 1
        }
        echo "Verified in-widget state change after clicking $handle"
        ;;
    scroll)
        [ "$#" -ge 2 ] && [ "$#" -le 3 ] || { usage >&2; exit 2; }
        handle=$1
        direction=$2
        output_dir=${3:-$DEFAULT_OUTPUT_DIR}
        prepare_output "$output_dir"
        remove_remote_file status.json
        remove_remote_file snapshot.json
        remove_remote_file preview.png
        send_command scroll \
            --es app_widget_handle "$handle" \
            --es app_widget_direction "$direction"
        wait_for_terminal_state "$output_dir" 30
        ;;
    replay)
        [ "$#" -ge 1 ] && [ "$#" -le 2 ] || { usage >&2; exit 2; }
        script_file=$1
        output_dir=${2:-$DEFAULT_OUTPUT_DIR}
        [ -f "$script_file" ] || { echo "Script not found: $script_file" >&2; exit 1; }
        validate_wrapper "$script_file"
        mkdir -p "$output_dir"
        rm -f "$output_dir/status.json" "$output_dir/replay.txt"
        adb_cmd shell mkdir -p "$REMOTE_DIR" >/dev/null
        remove_remote_file status.json
        remove_remote_file replay.txt
        remove_remote_file replay_snapshot.json
        adb_cmd shell rm -rf "$REMOTE_DIR/replay_snapshots" >/dev/null
        adb_cmd push "$script_file" "$REMOTE_DIR/candidate.lua" >/dev/null
        send_command replay
        wait_for_terminal_state "$output_dir" 60
        ;;
    replay-snapshot)
        allow_synthetic=false
        if [ "${1:-}" = "--allow-synthetic" ]; then
            allow_synthetic=true
            shift
        fi
        [ "$#" -ge 2 ] && [ "$#" -le 3 ] || { usage >&2; exit 2; }
        script_file=$1
        snapshot_file=$2
        output_dir=${3:-$DEFAULT_OUTPUT_DIR}
        [ -f "$script_file" ] || { echo "Script not found: $script_file" >&2; exit 1; }
        [ -f "$snapshot_file" ] || { echo "Snapshot not found: $snapshot_file" >&2; exit 1; }
        validate_wrapper "$script_file"
        [ "$allow_synthetic" = true ] || validate_live_snapshot "$snapshot_file" "$script_file"
        prepare_output "$output_dir"
        adb_cmd shell mkdir -p "$REMOTE_DIR" >/dev/null
        remove_remote_file status.json
        remove_remote_file replay.txt
        adb_cmd shell rm -rf "$REMOTE_DIR/replay_snapshots" >/dev/null
        adb_cmd push "$script_file" "$REMOTE_DIR/candidate.lua" >/dev/null
        adb_cmd push "$snapshot_file" "$REMOTE_DIR/replay_snapshot.json" >/dev/null
        send_command replay
        wait_for_terminal_state "$output_dir" 60
        ;;
    replay-suite)
        allow_synthetic=false
        if [ "${1:-}" = "--allow-synthetic" ]; then
            allow_synthetic=true
            shift
        fi
        [ "$#" -ge 2 ] && [ "$#" -le 3 ] || { usage >&2; exit 2; }
        script_file=$1
        states_dir=$2
        output_dir=${3:-$DEFAULT_OUTPUT_DIR}
        [ -f "$script_file" ] || { echo "Script not found: $script_file" >&2; exit 1; }
        [ -d "$states_dir" ] || { echo "States directory not found: $states_dir" >&2; exit 1; }
        validate_wrapper "$script_file"
        prepare_output "$output_dir"
        adb_cmd shell mkdir -p "$REMOTE_DIR" >/dev/null
        adb_cmd shell rm -rf "$REMOTE_DIR/replay_snapshots" >/dev/null
        adb_cmd shell mkdir -p "$REMOTE_DIR/replay_snapshots" >/dev/null
        remove_remote_file status.json
        remove_remote_file replay.txt
        remove_remote_file replay_snapshot.json
        adb_cmd push "$script_file" "$REMOTE_DIR/candidate.lua" >/dev/null

        state_count=0
        context_count=0
        replay_sizes=""
        for snapshot_file in "$states_dir"/*/snapshot.json; do
            [ -f "$snapshot_file" ] || continue
            [ "$allow_synthetic" = true ] || validate_live_snapshot "$snapshot_file" "$script_file"
            state_name=$(basename "$(dirname "$snapshot_file")")
            validate_state_name "$state_name"
            state_count=$((state_count + 1))
            captured_size=$(jq -r '(.width | tostring) + "x" + (.height | tostring)' "$snapshot_file")
            case ",$replay_sizes," in
                *",$captured_size,"*) ;;
                *) replay_sizes="${replay_sizes}${replay_sizes:+,}$captured_size" ;;
            esac
            remote_name=$(printf '%03d__%s.json' "$state_count" "$state_name")
            adb_cmd push "$snapshot_file" "$REMOTE_DIR/replay_snapshots/$remote_name" >/dev/null
            context_file=$(dirname "$snapshot_file")/context.json
            if [ -f "$context_file" ]; then
                context_count=$((context_count + 1))
                remote_context_name=$(printf '%03d__%s.context.json' "$state_count" "$state_name")
                adb_cmd push "$context_file" "$REMOTE_DIR/replay_snapshots/$remote_context_name" >/dev/null
            fi
        done
        [ "$state_count" -gt 0 ] || {
            echo "No state snapshots found under $states_dir/*/snapshot.json" >&2
            exit 1
        }
        echo "Replay matrix: states=$state_count contexts=$context_count captured_sizes=$replay_sizes"
        send_command replay_suite
        wait_for_terminal_state "$output_dir" 120
        ;;
    smoke-installed)
        [ "$#" -ge 2 ] && [ "$#" -le 3 ] || { usage >&2; exit 2; }
        script_file=$1
        snapshot_file=$2
        output_dir=${3:-$DEFAULT_OUTPUT_DIR}
        [ -f "$script_file" ] || { echo "Script not found: $script_file" >&2; exit 1; }
        [ -f "$snapshot_file" ] || { echo "Snapshot not found: $snapshot_file" >&2; exit 1; }
        validate_wrapper "$script_file"
        validate_live_snapshot "$snapshot_file" "$script_file"

        base_name=$(basename "$script_file")
        remote_names=$(adb_cmd shell ls -1 "$REMOTE_SCRIPTS_DIR" 2>/dev/null \
            | tr -d '\r' \
            | while IFS= read -r remote_name; do
                case "$remote_name" in
                    "$base_name"|*:"$base_name") echo "$remote_name" ;;
                esac
            done)
        remote_count=$(printf '%s\n' "$remote_names" | sed '/^$/d' | wc -l | tr -d ' ')
        [ "$remote_count" -eq 1 ] || {
            echo "Expected exactly one installed copy of $base_name, found $remote_count" >&2
            printf '%s\n' "$remote_names" | sed '/^$/d; s/^/  /' >&2
            echo "Install with manage-scripts.sh install and resolve duplicates before smoke testing." >&2
            exit 1
        }
        remote_name=$(printf '%s\n' "$remote_names" | sed -n '1p')

        prepare_output "$output_dir"
        installed_file="$output_dir/installed-script.lua"
        adb_cmd pull "$REMOTE_SCRIPTS_DIR$remote_name" "$installed_file" >/dev/null
        local_hash=$(sha256sum "$script_file" | sed 's/[[:space:]].*//')
        installed_hash=$(sha256sum "$installed_file" | sed 's/[[:space:]].*//')
        [ "$local_hash" = "$installed_hash" ] || {
            echo "Installed $remote_name is stale: checksum differs from $script_file" >&2
            exit 1
        }

        adb_cmd shell mkdir -p "$REMOTE_DIR" >/dev/null
        remove_remote_file status.json
        send_command verify_script --es app_widget_script_name "$remote_name"
        wait_for_terminal_state "$output_dir" 30
        cp "$output_dir/status.json" "$output_dir/installed-discovery-status.json"

        rm -f "$output_dir/status.json"
        remove_remote_file status.json
        remove_remote_file replay.txt
        adb_cmd shell rm -rf "$REMOTE_DIR/replay_snapshots" >/dev/null
        adb_cmd push "$installed_file" "$REMOTE_DIR/candidate.lua" >/dev/null
        adb_cmd push "$snapshot_file" "$REMOTE_DIR/replay_snapshot.json" >/dev/null
        send_command replay
        wait_for_terminal_state "$output_dir" 60
        echo "Installed-script smoke passed for $remote_name ($installed_hash)"
        ;;
    status)
        [ "$#" -le 1 ] || { usage >&2; exit 2; }
        output_dir=${1:-$DEFAULT_OUTPUT_DIR}
        mkdir -p "$output_dir"
        if pull_file status.json "$output_dir"; then
            cat "$output_dir/status.json"
        else
            echo "Inspector status is not available" >&2
            exit 1
        fi
        ;;
    wait)
        [ "$#" -le 2 ] || { usage >&2; exit 2; }
        output_dir=${1:-$DEFAULT_OUTPUT_DIR}
        timeout_seconds=${2:-${AIO_INSPECT_TIMEOUT:-180}}
        mkdir -p "$output_dir"
        wait_for_terminal_state "$output_dir" "$timeout_seconds"
        ;;
    cleanup)
        [ "$#" -le 1 ] || { usage >&2; exit 2; }
        output_dir=${1:-$DEFAULT_OUTPUT_DIR}
        mkdir -p "$output_dir"
        rm -f "$output_dir/status.json"
        remove_remote_file status.json
        send_command cleanup
        wait_for_terminal_state "$output_dir" 15
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
