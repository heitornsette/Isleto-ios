#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator, preferring an "iPhone NN Pro"
# (it has a Dynamic Island) on the newest iOS runtime installed on the runner.
set -euo pipefail

json="$(xcrun simctl list devices available -j)"

pick() {
  jq -r --arg pattern "$1" '
    [ .devices
      | to_entries[]
      | select(.key | test("SimRuntime\\.iOS-"))
      | (.key | capture("iOS-(?<v>[0-9-]+)$").v | split("-") | map(tonumber)) as $version
      | .value[]
      | select(.name | test($pattern))
      | { udid, name, version: $version }
    ]
    | sort_by(.version)
    | last
    | if . == null then empty else "\(.udid) \(.name) iOS \(.version | map(tostring) | join("."))" end
  ' <<<"$json"
}

choice="$(pick '^iPhone [0-9]+ Pro$')"
if [ -z "$choice" ]; then
  choice="$(pick '^iPhone')"
fi
if [ -z "$choice" ]; then
  echo "Nenhum simulador de iPhone disponível no runner." >&2
  exit 1
fi

echo "Simulador escolhido: ${choice#* }" >&2
echo "${choice%% *}"
