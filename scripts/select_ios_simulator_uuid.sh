#!/usr/bin/env bash
set -euo pipefail

select_uuid_from_json() {
  ruby -rjson -e '
    data = JSON.parse(STDIN.read)
    family = ARGV.fetch(0)
    candidates = data.fetch("devices", {}).flat_map do |runtime, devices|
      match = runtime.match(/iOS-(\d+)-(\d+)(?:-(\d+))?$/)
      next [] unless match
      version = match.captures.compact.map(&:to_i)
      devices.each_with_object([]) do |device, matches|
        next unless device["isAvailable"] != false
        next unless device["name"].start_with?(family)
        name = device["name"]
        generation = name[/\biPhone (\d+)\b/, 1].to_i
        pro_max = name.include?("Pro Max") ? 1 : 0
        pro = name.include?("Pro") ? 1 : 0
        matches << [version, generation, pro_max, pro, name, device.fetch("udid")]
      end
    end
    selected = candidates.max_by { |version, generation, pro_max, pro, name, _| [version, generation, pro_max, pro, name] }
    abort("No available #{family} simulator was found.") unless selected
    puts selected.last
  ' -- "${1}"
}

probe() {
  local fixture
  fixture='{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-5":[{"name":"iPhone 16 Pro","udid":"11111111-1111-4111-8111-111111111111","isAvailable":true},{"name":"iPhone 16 Pro Max","udid":"22222222-2222-4222-8222-222222222222","isAvailable":true}],"com.apple.CoreSimulator.SimRuntime.iOS-18-6":[{"name":"iPhone 15 Pro Max","udid":"55555555-5555-4555-8555-555555555555","isAvailable":true},{"name":"iPhone 16 Pro","udid":"66666666-6666-4666-8666-666666666666","isAvailable":true},{"name":"iPhone 16 Pro Max","udid":"33333333-3333-4333-8333-333333333333","isAvailable":true}],"com.apple.CoreSimulator.SimRuntime.iOS-18-7":[{"name":"iPhone 16 Pro Max","udid":"44444444-4444-4444-8444-444444444444","isAvailable":false}]}}'
  local selected
  selected="$(printf '%s' "${fixture}" | select_uuid_from_json iPhone)"
  [[ "${selected}" == "33333333-3333-4333-8333-333333333333" ]]
  echo "iPhone simulator UUID selector probe passed."
}

if [[ "${1:-}" == "--probe" ]]; then
  probe
  exit 0
fi

device_family="${1:-iPhone}"
listing_json="$(xcrun simctl list devices available -j)"
if ! simulator_id="$(printf '%s' "${listing_json}" | select_uuid_from_json "${device_family}")"; then
  echo "No available ${device_family} simulator with a UUID was found." >&2
  xcrun simctl list devices available >&2
  exit 1
fi

printf '%s\n' "${simulator_id}"
