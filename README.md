# Home Assistant Add-ons

- wireguard-ui

## Upgrading Wireguard UI

Install [download-utilites.sh v3.2 or higher from
yml-install-files][yml-install-files].  You must check for updates and then
recalculate checksums.  The checksums are necessary to ensure all users download
the expected version of wireguard-ui utility.

    cd wireguard-ui/
    download-utilities.sh --update
    download-utilities.sh --checksum --invert-os-arch -I Linux:aarch64 -I Linux:armv7 -I Linux:x86_64

[yml-install-files]: https://github.com/samrocketman/yml-install-files
