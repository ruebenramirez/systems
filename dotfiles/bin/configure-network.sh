#!/usr/bin/env bash

set -euo pipefail

configure_network() {
  local mode="$1"

  if [[ "$mode" != "home" && "$mode" != "remote" ]]; then
    echo "Invalid mode. Use 'home' or 'remote'."
    exit 1
  fi

  local wpa_src="/persist/etc/wpa_supplicant/${mode}-wpa_supplicant.conf"
  local wpa_dst="/persist/etc/wpa_supplicant.conf"

  echo "Setting wpa_supplicant config to $wpa_src"
  sudo ln -sf "$wpa_src" "$wpa_dst"

  echo "Restarting wpa_supplicant.service"
  sudo systemctl restart wpa_supplicant.service

  echo "Restarting wireguard interfaces"
  sudo systemctl restart wg-quick-wg0.service
  sudo systemctl restart wg-quick-wg1.service

  echo "Network configured for $mode mode."
}

show_wireguard_connections() {
  sudo watch wg show
}

main() {
  if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <home|remote>"
    exit 1
  fi

  local mode="$1"
  configure_network "$mode"
  show_wireguard_connections
}

main "$@"
