#!/usr/bin/env bash
set -euo pipefail

readonly UUID_PATTERN='[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}'

extract_uuid() {
  local line="$1"
  if [[ "${line}" =~ \((${UUID_PATTERN})\) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

select_uuid_from_listing() {
  local listing="$1"
  local device_family="$2"
  local line
  local simulator_id

  while IFS= read -r line; do
    [[ "${line}" == *"${device_family}"* ]] || continue
    if simulator_id="$(extract_uuid "${line}")"; then
      if [[ "${simulator_id}" =~ ^${UUID_PATTERN}$ ]]; then
        printf '%s\n' "${simulator_id}"
        return 0
      fi
    fi
  done <<< "${listing}"

  return 1
}

probe() {
  local fixture=$'    iPad Pro 11-inch (M4) (A8AF3C2A-A56D-4F78-8E4D-B8564385E859) (Shutdown)\n    iPad (A16) (CBDF48F8-8926-4CCE-8F3B-ABEB23938EF7) (Shutdown)'
  local selected
  selected="$(select_uuid_from_listing "${fixture}" "iPad")"
  [[ "${selected}" == "A8AF3C2A-A56D-4F78-8E4D-B8564385E859" ]]

  if select_uuid_from_listing $'    iPad Pro 11-inch (M4) (Shutdown)' "iPad" >/dev/null; then
    echo "Selector probe unexpectedly accepted a no-device listing." >&2
    return 1
  fi

  echo "iPad simulator UUID selector probe passed."
}

if [[ "${1:-}" == "--probe" ]]; then
  probe
  exit 0
fi

device_family="${1:-}"
if [[ -z "${device_family}" ]]; then
  echo "Usage: $0 <device-family>" >&2
  exit 2
fi

listing="$(xcrun simctl list devices available)"
if ! simulator_id="$(select_uuid_from_listing "${listing}" "${device_family}")"; then
  echo "No available ${device_family} simulator with a UUID was found." >&2
  printf '%s\n' "${listing}" >&2
  exit 1
fi

printf '%s\n' "${simulator_id}"
