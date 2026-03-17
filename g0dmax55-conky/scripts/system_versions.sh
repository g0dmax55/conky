#!/bin/bash

C6="\${color6}"  # Red - Tree/Brackets
C2="\${color2}"  # Cyan - Values
C1="\${color1}"  # Grey - Text
CR="\${color}"   # Reset

trim() {
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

first_line() {
    awk 'NF { print; exit }'
}

first_semver_like() {
    awk '/^[0-9]+([.][0-9]+)+$/ { print; exit }'
}

first_cuda_like() {
    awk '/^[0-9]+([.][0-9]+)*$/ { print; exit }'
}

linux_version() {
    awk -F= '
        /^PRETTY_NAME=/ {
            gsub(/"/, "", $2)
            print $2
            exit
        }
    ' /etc/os-release 2>/dev/null | trim
}

kernel_version() {
    uname -r 2>/dev/null | trim
}

systemd_version() {
    systemctl --version 2>/dev/null | sed -n '1s/^systemd[[:space:]]\+\([0-9][0-9]*\).*/\1/p' | trim
}

nvidia_driver_version() {
    local value

    value="$(
        timeout 5s nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | first_semver_like | trim
    )"
    if [ -n "$value" ]; then
        printf '%s\n' "$value"
        return
    fi

    value="$(
        sed -n 's/.*Kernel Module[[:space:]]\+\([^[:space:]]\+\).*/\1/p' /proc/driver/nvidia/version 2>/dev/null | first_line | trim
    )"
    if [ -n "$value" ]; then
        printf '%s\n' "$value"
        return
    fi

    printf '%s\n' "not-installed"
}

cuda_runtime_version() {
    local value

    value="$(
        timeout 5s nvidia-smi --query-gpu=cuda_version --format=csv,noheader 2>/dev/null | first_cuda_like | trim
    )"
    if [ -n "$value" ]; then
        printf '%s\n' "$value"
        return
    fi

    value="$(
        nvcc --version 2>/dev/null | sed -n 's/.*release \([^,]*\),.*/\1/p' | first_line | trim
    )"
    if [ -n "$value" ]; then
        printf '%s\n' "$value"
        return
    fi

    printf '%s\n' "not-installed"
}

cuda_toolkit_version() {
    local value

    value="$(
        nvcc --version 2>/dev/null | sed -n 's/.*release \([^,]*\),.*/\1/p' | first_line | trim
    )"
    if [ -n "$value" ]; then
        printf '%s\n' "$value"
        return
    fi

    printf '%s\n' "not-installed"
}

conky_version() {
    conky --version 2>/dev/null | sed -n '1s/^conky[[:space:]]\+\([0-9][^[:space:]]*\).*/\1/p' | trim
}

print_version_line() {
    local label=$1
    local value=$2
    [ -n "$value" ] || value="unknown"

    printf "%s│  ├─%s %s[%s%s%s]%s %s%s%s\n" \
        "$C6" "$CR" "$C6" "$C2" "$value" "$C6" "$CR" "$C1" "$label" "$CR"
}

echo "${C6}├─${CR} ${C6}[${C2}VERSIONS${C6}]${CR}"
print_version_line "linux" "$(linux_version)"
print_version_line "kernel" "$(kernel_version)"
print_version_line "systemd" "$(systemd_version)"
print_version_line "nvidia-driver" "$(nvidia_driver_version)"
print_version_line "cuda-toolkit" "$(cuda_toolkit_version)"
print_version_line "conky" "$(conky_version)"
echo "${C6}└─${CR}"
