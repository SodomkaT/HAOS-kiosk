#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../haoskiosk/touch_mapping.sh
source "$SCRIPT_DIR/../haoskiosk/touch_mapping.sh"

failures=0

assert_equal() {
    local expected="$1"
    local actual="$2"
    local description="$3"

    if [[ "$actual" != "$expected" ]]; then
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' \
            "$description" "$expected" "$actual" >&2
        failures=$((failures + 1))
    fi
}

assert_success() {
    local description="$1"
    shift
    if ! "$@" >/dev/null; then
        printf 'FAIL: %s\n' "$description" >&2
        failures=$((failures + 1))
    fi
}

assert_failure() {
    local description="$1"
    shift
    if "$@" >/dev/null; then
        printf 'FAIL: %s\n' "$description" >&2
        failures=$((failures + 1))
    fi
}

assert_equal "1 0 0 0 1 0 0 0 1" "$(touch_rotation_matrix normal)" "normal matrix"
assert_equal "0 -1 1 1 0 0 0 0 1" "$(touch_rotation_matrix left)" "left matrix"
assert_equal "0 1 0 -1 0 1 0 0 1" "$(touch_rotation_matrix right)" "right matrix"
assert_equal "-1 0 1 0 -1 1 0 0 1" "$(touch_rotation_matrix inverted)" "inverted matrix"

mapped="0.5 0 0.5 0 0.5 0 0 0 1"
rotated="$(touch_multiply_matrices "$mapped" "$(touch_rotation_matrix left)")"
assert_equal "0 -0.5 1 0.5 0 0 0 0 1" "$rotated" "output mapping composed with left rotation"

properties='Coordinate Transformation Matrix (142): 1.000000, 0.000000, 0.000000, 0.000000, 1.000000, 0.000000, 0.000000, 0.000000, 1.000000'
assert_equal "1.000000 0.000000 0.000000 0.000000 1.000000 0.000000 0.000000 0.000000 1.000000" \
    "$(touch_extract_ctm "$properties")" "CTM parsing"

node_properties='libinput Device Node (300): "/dev/input/event7"'
assert_equal "/dev/input/event7" "$(touch_device_node "generic device" "$node_properties")" "libinput node property"
assert_equal "/dev/input/event4" "$(touch_device_node "evdev-event4" "")" "evdev name fallback"
assert_equal "libinput" "$(touch_driver_name 'libinput Calibration Matrix (1): 1, 0, 0')" "libinput driver"
assert_equal "evdev" "$(touch_driver_name 'Evdev Axis Calibration (1): <no items>')" "evdev driver"

assert_success "touch name detection" touch_device_reason "Raspberry Pi Touchscreen" "" "" "/missing"
assert_success "XI2 touch-class detection" touch_device_reason "generic device" "" "Class: XITouchClass" "/missing"

test_sysfs="$(mktemp -d)"
trap 'rm -rf "$test_sysfs"' EXIT
mkdir -p "$test_sysfs/event4/device" "$test_sysfs/event5/device"
printf '2\n' > "$test_sysfs/event4/device/properties"
printf '1\n' > "$test_sysfs/event5/device/properties"
assert_success "generic evdev direct-input detection" touch_device_reason "evdev-event4" "" "" "$test_sysfs"
assert_failure "pointer is not treated as touch" touch_device_reason "evdev-event5" "" "" "$test_sysfs"

if (( failures > 0 )); then
    printf '%d touch-mapping test(s) failed\n' "$failures" >&2
    exit 1
fi

echo "All touch-mapping tests passed"
