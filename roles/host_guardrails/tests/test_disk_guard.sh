#!/usr/bin/env bash
set -Eeuo pipefail

readonly TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_PATH="${TESTS_DIR}/../templates/mibeko-check-disk.sh.j2"

run_case() {
    local usage_percent="$1"
    local expected_exit="$2"
    local expected_endpoint="$3"
    local actual_exit

    set +e
    (
        local_config="$(mktemp)"
        trap 'rm -f "${local_config}"' EXIT
        printf '%s\n' \
            'DISK_WARNING_PERCENT=80' \
            'DISK_CRITICAL_PERCENT=90' \
            'DISK_HEALTHCHECK_URL=https://hc-ping.com/test' \
            >"${local_config}"

        df() {
            printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
            printf '/dev/test 100 50 50 %s%% /\n' "${usage_percent}"
        }
        logger() { return 0; }
        curl() {
            local endpoint="${!#}"
            [[ "${endpoint}" == "${expected_endpoint}" ]]
        }
        hostname() { printf 'test-host\n'; }
        date() { printf '2026-08-31T00:00:00Z\n'; }

        MIBEKO_HOST_GUARDRAILS_CONFIG="${local_config}" source "${SCRIPT_PATH}"
    )
    actual_exit="$?"
    set -e

    if [[ "${actual_exit}" -ne "${expected_exit}" ]]; then
        printf 'usage=%s attendu=%s obtenu=%s\n' \
            "${usage_percent}" "${expected_exit}" "${actual_exit}" >&2
        return 1
    fi
}

run_case 48 0 https://hc-ping.com/test
run_case 80 1 https://hc-ping.com/test/fail
run_case 90 1 https://hc-ping.com/test/fail

printf 'disk guard cases: ok\n'
