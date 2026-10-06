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
  echo "Stopping wpa_supplicant-wlp2s0.service"
  sudo systemctl stop wpa_supplicant-wlp2s0.service

  echo "Stopping VPN"
  sudo tailscale down
}

configure_network() {
  local mode="$1"

  local wpa_src="/persist/etc/wpa_supplicant/${mode}-wpa_supplicant.conf"
  local wpa_dst="/persist/etc/wpa_supplicant.conf"

  echo "Setting wpa_supplicant config to $wpa_src"
  sudo ln -sf "$wpa_src" "$wpa_dst"
}

start_services() {
  echo "Restarting wpa_supplicant-wlp2s0.service"
  sudo systemctl start wpa_supplicant-wlp2s0.service
  sudo tailscale up

  echo "Network configured for $mode mode."

  echo "waiting for the network to come back online..."
}

show_VPN_conf() {
  sudo tailscale get
  sudo tailscale status
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
  start_services
  show_VPN_conf
}

main "$@"
