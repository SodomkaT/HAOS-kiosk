#!/usr/bin/env bash
# Helpers for detecting X11 touch devices and composing their coordinate matrix.

touch_rotation_matrix() {
    case "$1" in
        normal) echo "1 0 0 0 1 0 0 0 1" ;;
        left) echo "0 -1 1 1 0 0 0 0 1" ;;
        right) echo "0 1 0 -1 0 1 0 0 1" ;;
        inverted) echo "-1 0 1 0 -1 1 0 0 1" ;;
        *) return 1 ;;
    esac
}

# Multiply two row-major 3x3 matrices. XInput applies the result to column
# vectors, so output mapping must be the left-hand matrix and rotation the
# right-hand matrix.
touch_multiply_matrices() {
    awk -v left="$1" -v right="$2" '
        function clean(value) {
            return (value < 0.000000000001 && value > -0.000000000001) ? 0 : value
        }
        BEGIN {
            if (split(left, a, /[[:space:]]+/) != 9 ||
                split(right, b, /[[:space:]]+/) != 9)
                exit 1

            for (row = 0; row < 3; row++) {
                for (column = 0; column < 3; column++) {
                    value = 0
                    for (item = 0; item < 3; item++)
                        value += a[row * 3 + item + 1] * b[item * 3 + column + 1]
                    printf "%s%.10g", (row || column ? " " : ""), clean(value)
                }
            }
            print ""
        }
    '
}

touch_extract_ctm() {
    awk -F: '
        /^[[:space:]]*Coordinate Transformation Matrix \([0-9]+\):/ {
            matrix = $2
            gsub(/,/, "", matrix)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", matrix)
            if (split(matrix, values, /[[:space:]]+/) != 9)
                exit 1
            for (item = 1; item <= 9; item++)
                printf "%s%s", (item == 1 ? "" : " "), values[item]
            print ""
            found = 1
            exit
        }
        END { if (!found) exit 1 }
    ' <<< "$1"
}

touch_device_node() {
    local name="$1"
    local properties="$2"
    local line

    while IFS= read -r line; do
        if [[ "$line" == *"Device Node"* && "$line" =~ (/dev/input/event[0-9]+) ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    done <<< "$properties"

    # Explicit evdev fallback configurations often use names such as
    # "evdev-event4" without publishing a Device Node property.
    if [[ "$name" =~ (event[0-9]+) ]]; then
        echo "/dev/input/${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

touch_device_reason() {
    local name="$1"
    local properties="$2"
    local details="$3"
    local sysfs_root="${4:-/sys/class/input}"
    local node event_name property_bits property_word udev_properties

    if [[ "${name,,}" =~ (^|[^[:alnum:]_])(touch|touchscreen|stylus)([^[:alnum:]_]|$) ]]; then
        echo "name"
        return 0
    fi

    if [[ "$details" == *"XITouchClass"* || "$details" == *"Touch mode:"* ]]; then
        echo "XI2 touch class"
        return 0
    fi

    node="$(touch_device_node "$name" "$properties" 2>/dev/null || true)"
    if [[ -n "$node" ]]; then
        event_name="${node##*/}"
        if [[ -r "$sysfs_root/$event_name/device/properties" ]]; then
            read -r property_bits < "$sysfs_root/$event_name/device/properties"
            property_word="${property_bits##* }"
            property_word="${property_word#0x}"
            if [[ "$property_word" =~ ^[[:xdigit:]]+$ ]] &&
               (( (16#$property_word & 2) != 0 )); then
                echo "kernel direct-input property"
                return 0
            fi
        fi

        if command -v udevadm >/dev/null 2>&1; then
            udev_properties="$(udevadm info --query=property --name="$node" 2>/dev/null || true)"
            if [[ "$udev_properties" == *"ID_INPUT_TOUCHSCREEN=1"* ||
                  "$udev_properties" == *"ID_INPUT_TABLET=1"* ]]; then
                echo "udev input tag"
                return 0
            fi
        fi
    fi

    return 1
}

touch_driver_name() {
    if [[ "${1,,}" == *"libinput "* ]]; then
        echo "libinput"
    elif [[ "${1,,}" == *"evdev "* ]]; then
        echo "evdev"
    else
        echo "XInput"
    fi
}
