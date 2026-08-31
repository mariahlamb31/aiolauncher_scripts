#!/bin/sh

set -eu

usage() {
    echo "Usage: tools/validate-app-widget-wrapper.sh SCRIPT" >&2
}

[ "$#" -eq 1 ] || { usage; exit 2; }
script_file=$1
[ -f "$script_file" ] || { echo "Script not found: $script_file" >&2; exit 1; }

errors=0

fail() {
    echo "$script_file: $1" >&2
    errors=$((errors + 1))
}

require_metadata() {
    key=$1
    value_pattern=$2
    if ! grep -Eq "^-- ${key} = \"${value_pattern}\"[[:space:]]*$" "$script_file"; then
        fail "missing or malformed metadata: -- ${key} = \"...\""
    fi
}

# Metadata is parsed by exact keys. A visually similar colon or misspelled key
# otherwise makes a wrapper silently disappear from the expected catalog/filter.
if grep -Eq '^--[[:space:]]+(name|type|aio[_ -]?version|uses[_ -]?app)[[:space:]]*:' "$script_file"; then
    fail "metadata must use 'key = \"value\"', not a colon"
fi

structured_api=false
grep -Eq 'bridge[[:space:]]*:[[:space:]]*(snapshot|snapshot_json|click_handle)' "$script_file" \
    && structured_api=true
named_wrapper=false
case "$(basename "$script_file")" in
    *-app-widget.lua) named_wrapper=true ;;
esac

if [ "$structured_api" = true ] || [ "$named_wrapper" = true ]; then
    require_metadata name '[^\"]+'
    require_metadata type 'widget'
fi
if [ "$named_wrapper" = true ]; then
    require_metadata uses_app '[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+'
fi
if [ "$structured_api" = true ]; then
    require_metadata aio_version '[^\"]+'

    # Render handles are never stable string constants, even when a literal is
    # first assigned to a variable and only later passed to click_handle().
    if grep -Eq '[\"'\'']node_[0-9]+[\"'\'']' "$script_file"; then
        fail "hardcoded node_N handles are render-local; save click_target from the current snapshot"
    fi
fi

uses_app=$(sed -n 's/^-- uses_app = "\([^"]*\)"[[:space:]]*$/\1/p' "$script_file" | head -n 1)
provider_package=$(sed -n \
    's/^[[:space:]]*local[[:space:]][[:space:]]*provider[[:space:]]*=[[:space:]]*"\([^/\"]*\)\/[^\"]*".*/\1/p' \
    "$script_file" | head -n 1)
if [ -n "$uses_app" ] && [ -n "$provider_package" ] && [ "$uses_app" != "$provider_package" ]; then
    fail "uses_app '$uses_app' does not match provider package '$provider_package'"
fi

[ "$errors" -eq 0 ] || exit 1
echo "Script checks passed: $script_file"
