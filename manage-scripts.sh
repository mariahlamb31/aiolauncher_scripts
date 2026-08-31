#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ADB_BIN=${ADB_BIN:-adb}
VALIDATOR="$REPO_ROOT/tools/validate-app-widget-wrapper.sh"
REPOS="main ru community dev"
SCRIPTS_DIR="/sdcard/Android/data/ru.execbit.aiolauncher/files/"
SERIAL=""

usage() {
    cat >&2 <<'EOF'
Usage:
  ./manage-scripts.sh [-s SERIAL] install [--target REMOTE_NAME] [--dedupe] SCRIPT
  ./manage-scripts.sh [-s SERIAL] remove [--target REMOTE_NAME] SCRIPT
  ./manage-scripts.sh validate SCRIPT
  ./manage-scripts.sh [-s SERIAL] install-all
  ./manage-scripts.sh [-s SERIAL] remove-all

Commands:
  install      Validate and install one script, preserving its existing remote name.
  remove       Remove one installed script, resolving plain or repository-prefixed names.
  validate     Validate one local script without connecting to a device.
  install-all  Validate, remove, and reinstall scripts from every configured repository.
  remove-all   Remove all installed .lua scripts managed through ADB.
EOF
}

adb_cmd() {
    if [ -n "$SERIAL" ]; then
        "$ADB_BIN" -s "$SERIAL" "$@"
    else
        "$ADB_BIN" "$@"
    fi
}

# adb shell joins arguments into a remote shell command. Quote each argument so
# repository-prefixed file names cannot be split or interpreted by that shell.
remote_shell() {
    remote_command=""
    for remote_arg in "$@"; do
        case "$remote_arg" in
            *"'"*)
                echo "Unsupported apostrophe in remote argument" >&2
                return 2
                ;;
        esac
        remote_command="${remote_command}${remote_command:+ }'$remote_arg'"
    done
    adb_cmd shell "$remote_command"
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
}

list_remote_scripts() {
    remote_shell ls -1 "$SCRIPTS_DIR" 2>/dev/null \
        | tr -d '\r' \
        | while IFS= read -r remote_name; do
            case "$remote_name" in
                *.lua) printf '%s\n' "$remote_name" ;;
            esac
        done
}

validate_script() {
    "$VALIDATOR" "$1"
}

validate_all_scripts() {
    validation_failed=false
    for repo_name in $REPOS; do
        for script_path in "$REPO_ROOT/$repo_name"/*.lua; do
            [ -f "$script_path" ] || continue
            if ! validation_output=$(validate_script "$script_path" 2>&1); then
                printf '%s\n' "$validation_output" >&2
                validation_failed=true
            fi
        done
    done
    [ "$validation_failed" = false ] || return 1
}

remove_all_scripts() {
    remote_names=$(list_remote_scripts) || {
        echo "Unable to list installed scripts in $SCRIPTS_DIR" >&2
        return 1
    }
    remote_count=$(printf '%s\n' "$remote_names" | sed '/^$/d' | wc -l | tr -d ' ')

    printf '%s\n' "$remote_names" | while IFS= read -r remote_name; do
        [ -n "$remote_name" ] || continue
        remote_shell rm -f "$SCRIPTS_DIR$remote_name" >/dev/null
    done
    echo "Removed $remote_count installed script(s)"
}

install_one() {
    target_name=""
    dedupe=false

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --target)
                [ "$#" -ge 2 ] || { usage; exit 2; }
                target_name=$2
                shift 2
                ;;
            --dedupe)
                dedupe=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --*)
                usage
                exit 2
                ;;
            *)
                [ "$#" -eq 1 ] || { usage; exit 2; }
                script_file=$1
                shift
                ;;
        esac
    done

    [ -n "${script_file:-}" ] || { usage; exit 2; }
    [ -f "$script_file" ] || { echo "Script not found: $script_file" >&2; exit 1; }

    base_name=$(basename "$script_file")
    case "$base_name" in
        *.lua) ;;
        *) echo "Expected a .lua script: $script_file" >&2; exit 1 ;;
    esac
    case "$target_name" in
        */*) echo "Remote target must be a file name, not a path: $target_name" >&2; exit 2 ;;
    esac

    validate_script "$script_file"
    require_device

    installed_scripts=$(list_remote_scripts) || {
        echo "Unable to list installed scripts in $SCRIPTS_DIR" >&2
        exit 1
    }
    remote_names=$(printf '%s\n' "$installed_scripts" | while IFS= read -r remote_name; do
        case "$remote_name" in
            "$base_name"|*:"$base_name") printf '%s\n' "$remote_name" ;;
        esac
    done)
    remote_count=$(printf '%s\n' "$remote_names" | sed '/^$/d' | wc -l | tr -d ' ')

    if [ -z "$target_name" ]; then
        if [ "$remote_count" -eq 0 ]; then
            target_name=$base_name
        elif [ "$remote_count" -eq 1 ]; then
            target_name=$remote_names
        elif [ "$dedupe" = true ] && printf '%s\n' "$remote_names" | grep -Fqx "$base_name"; then
            target_name=$base_name
        elif [ "$dedupe" = true ]; then
            target_name=$(printf '%s\n' "$remote_names" | sed -n '1p')
        else
            echo "Several installed copies match $base_name:" >&2
            printf '%s\n' "$remote_names" | sed 's/^/  /' >&2
            echo "Choose one with --target, or pass --dedupe to keep a single copy." >&2
            exit 1
        fi
    fi

    case "$target_name" in
        "$base_name"|*:"$base_name") ;;
        *)
            echo "Target '$target_name' does not match script '$base_name'" >&2
            exit 2
            ;;
    esac
    if [ "$remote_count" -gt 0 ] \
        && ! printf '%s\n' "$remote_names" | grep -Fqx "$target_name"; then
        echo "Target '$target_name' is not one of the installed copies:" >&2
        printf '%s\n' "$remote_names" | sed 's/^/  /' >&2
        exit 1
    fi

    adb_cmd push "$script_file" "$SCRIPTS_DIR$target_name"

    local_hash=$(sha256sum "$script_file" | sed 's/[[:space:]].*//')
    remote_hash=$(remote_shell sha256sum "$SCRIPTS_DIR$target_name" \
        | tr -d '\r' | sed 's/[[:space:]].*//')
    [ "$local_hash" = "$remote_hash" ] || {
        echo "Installed script checksum does not match $script_file" >&2
        exit 1
    }

    if [ "$dedupe" = true ]; then
        printf '%s\n' "$remote_names" | while IFS= read -r remote_name; do
            [ -n "$remote_name" ] || continue
            [ "$remote_name" = "$target_name" ] \
                || remote_shell rm -f "$SCRIPTS_DIR$remote_name" >/dev/null
        done
    fi

    required_version=$(sed -n 's/^-- aio_version = "\([^"]*\)".*/\1/p' "$script_file" | head -n 1)
    installed_version=$(remote_shell dumpsys package ru.execbit.aiolauncher \
        | sed -n 's/.*versionName=//p' | head -n 1 | tr -d '\r')

    echo "Installed as $target_name"
    echo "SHA-256: $local_hash"
    echo "AIO version: ${installed_version:-unknown}; script requires: ${required_version:-unspecified}"
}

remove_one() {
    target_name=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --target)
                [ "$#" -ge 2 ] || { usage; exit 2; }
                target_name=$2
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --*)
                usage
                exit 2
                ;;
            *)
                [ "$#" -eq 1 ] || { usage; exit 2; }
                script_name=$1
                shift
                ;;
        esac
    done

    [ -n "${script_name:-}" ] || { usage; exit 2; }
    base_name=$(basename "$script_name")
    case "$base_name" in
        *.lua) ;;
        *) echo "Expected a .lua script name: $script_name" >&2; exit 1 ;;
    esac
    case "$target_name" in
        */*) echo "Remote target must be a file name, not a path: $target_name" >&2; exit 2 ;;
    esac

    require_device
    installed_scripts=$(list_remote_scripts) || {
        echo "Unable to list installed scripts in $SCRIPTS_DIR" >&2
        exit 1
    }
    remote_names=$(printf '%s\n' "$installed_scripts" | while IFS= read -r remote_name; do
        case "$remote_name" in
            "$base_name"|*:"$base_name") printf '%s\n' "$remote_name" ;;
        esac
    done)
    remote_count=$(printf '%s\n' "$remote_names" | sed '/^$/d' | wc -l | tr -d ' ')

    if [ -z "$target_name" ]; then
        case "$remote_count" in
            0)
                echo "No installed copy of $base_name was found" >&2
                exit 1
                ;;
            1)
                target_name=$remote_names
                ;;
            *)
                echo "Several installed copies match $base_name:" >&2
                printf '%s\n' "$remote_names" | sed 's/^/  /' >&2
                echo "Choose one with remove --target REMOTE_NAME $base_name." >&2
                exit 1
                ;;
        esac
    elif ! printf '%s\n' "$remote_names" | grep -Fqx "$target_name"; then
        echo "Target '$target_name' is not an installed copy of $base_name:" >&2
        printf '%s\n' "$remote_names" | sed '/^$/d; s/^/  /' >&2
        exit 1
    fi

    remote_shell rm -f "$SCRIPTS_DIR$target_name" >/dev/null
    echo "Removed $target_name"
}

install_all() {
    validate_all_scripts || {
        echo "Validation failed; installed scripts were not changed" >&2
        exit 1
    }
    require_device
    remove_all_scripts

    for repo_name in $REPOS; do
        set -- "$REPO_ROOT/$repo_name"/*.lua
        [ -f "$1" ] || continue
        adb_cmd push "$@" "$SCRIPTS_DIR"
    done
    echo "Installed scripts from: $REPOS"
}

if [ "${1:-}" = "-s" ]; then
    [ "$#" -ge 3 ] || { usage; exit 2; }
    SERIAL=$2
    shift 2
fi

[ "$#" -ge 1 ] || { usage; exit 2; }
command_name=$1
shift

case "$command_name" in
    install)
        install_one "$@"
        ;;
    remove)
        remove_one "$@"
        ;;
    validate)
        [ "$#" -eq 1 ] || { usage; exit 2; }
        validate_script "$1"
        ;;
    install-all)
        [ "$#" -eq 0 ] || { usage; exit 2; }
        install_all
        ;;
    remove-all)
        [ "$#" -eq 0 ] || { usage; exit 2; }
        require_device
        remove_all_scripts
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        exit 2
        ;;
esac
