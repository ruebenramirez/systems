#!/usr/bin/env python

import os
import sys
import subprocess
import time

def run_command(command):
    try:
        subprocess.run(command, shell=True, check=True)
        print(f"Ran command: {command}")
    except subprocess.CalledProcessError as e:
        print(f"Failed to run command '{command}': {e}")
        sys.exit(1)

def configure_network(mode):
    if mode not in ["home", "remote"]:
        print("Invalid mode. Use 'home' or 'remote'.")
        sys.exit(1)

    # wpa_supplicant config symlink
    wpa_src = f"/persist/etc/wpa_supplicant/{mode}-wpa_supplicant.conf"
    wpa_dst = "/persist/etc/wpa_supplicant.conf"

    # wireguard config symlink
    wg_src = f"/persist/etc/wireguard/wg0-wgnet/{mode}-wgnet.conf"
    wg_dst = "/persist/etc/wireguard/wg0-wgnet.conf"

    print(f"Setting wpa_supplicant config to {wpa_src}")
    run_command(f"sudo ln -sf {wpa_src} {wpa_dst}")

    print("Restarting wpa_supplicant.service")
    run_command("sudo systemctl restart wpa_supplicant.service")

    print(f"Setting wireguard config to {wg_src}")
    run_command(f"sudo ln -sf {wg_src} {wg_dst}")

    print("Restarting wireguard interfaces")
    run_command("sudo systemctl restart wg-quick-wg0.service")
    run_command("sudo systemctl restart wg-quick-wg1.service")

    print(f"Network configured for {mode} mode.")

def show_wireguard_connections():
    time.sleep(4)
    run_command("sudo wg show")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python mynet.py <home|remote>")
        sys.exit(1)
    configure_network(sys.argv[1])
    show_wireguard_connections()

