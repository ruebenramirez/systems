#!/usr/bin/env bash

set -euo pipefail


validate_input() {
  local mode="$1"

  if [[ "$mode" != "home" && "$mode" != "remote" ]]; then
    echo "Invalid mode. Use 'home' or 'remote'."
    exit 1
  fi

}

stop_services() {
  echo "Stopping wpa_supplicant.service"
  sudo systemctl stop wpa_supplicant.service

  echo "Stopping wireguard interfaces"
  sudo systemctl stop wg-quick-wg0.service
  sudo systemctl stop wg-quick-wg1.service
}

configure_network() {
  local mode="$1"

  local wpa_src="/persist/etc/wpa_supplicant/${mode}-wpa_supplicant.conf"
  local wpa_dst="/persist/etc/wpa_supplicant.conf"

  echo "Setting wpa_supplicant config to $wpa_src"
  sudo ln -sf "$wpa_src" "$wpa_dst"

  local wg0_src="/persist/etc/wireguard/wgnet/jellinet-${mode}.conf"
  local wg0_dst="/persist/etc/wireguard/wgnet-home.conf"

  echo "Setting wg0 config to $wpa_src"
  sudo ln -sf "$wg0_src" "$wg0_dst"
}

restart_services() {
  echo "Restarting wpa_supplicant.service"
  sudo systemctl restart wpa_supplicant.service

  echo "waiting for the network to come back online..."
  sleep 7

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
  validate_input "$mode"
  stop_services
  configure_network "$mode"
  restart_services
  show_wireguard_connections
}

main "$@"
