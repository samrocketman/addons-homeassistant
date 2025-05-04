# Home Assistant Add-on: Wireguard UI

A basic, self-contained management service for WireGuard with a self-serve web
UI.

## Server Backend

* Backend: [ngoduykhanh/wireguard-ui][ngoduykhanh/wireguard-ui]
* wireguard-ui: 0.6.2

[ngoduykhanh/wireguard-ui]: https://github.com/ngoduykhanh/wireguard-ui

## Features

- Self-serve and web based
- QR-Code for convenient mobile client configuration
- Optional multi-user support behind an authenticating proxy
- Zero external dependencies - just a single binary using the wireguard kernel
  module.
- Binary and container deployment

![Wireguard UI screenshot][wgui-screen]

[wgui-screen]: images/wireguard-ui-home-assistant-screenshot.png

## Upgrading Wireguard UI

Install [download-utilites.sh v3.2 or higher from
yml-install-files][yml-install-files].  You must check for updates and then
recalculate checksums.  The checksums are necessary to ensure all users download
the expected version of wireguard-ui utility.

    download-utilities.sh --update
    download-utilities.sh --checksum --invert-os-arch -I Linux:aarch64 -I Linux:armv7 -I Linux:x86_64

[yml-install-files]: https://github.com/samrocketman/yml-install-files
