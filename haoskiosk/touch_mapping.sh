#!/usr/bin/env bash
# Helpers for detecting X11 touch devices and inspecting their coordinate matrix.

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
