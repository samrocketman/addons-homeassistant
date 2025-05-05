# Getting started

1. Set a static IP address for Home Assistant (from your router or from
   Home Assistant settings).
2. Optionally set some configuration before starting.
3. Port forward from your router `51820/udp` to Home Assistant.  If you change
   the default configuration, then port forward accordingly.
3. Start the service.

## First time configuration

1. Visit WireGuard UI frontend.
2. Under _Settings > Global Settings_ click _Suggest_ next to `Endpoint
   Address`.  Add the UDP port which you forwarded from your router.  If you
   left everything default, then you'll set `<IP address>:51820`.
3. DNS Servers - You can leave this default.  If you have AdGuard installed your
   VPN clients will already be using it.
4. Persistent Keepalive - Disabled by default.  This is suggested because your
   VPN will be undetected if it's not sending traffic.  Another sane value if
   you want to have a persistent keepalive is `15` seconds.

## Single User Mode

All Home Assistant users can access WireGuard UI as a no-login administrator.
Single user mode is protected by Home Assistant ingress so it is not anonymously
available on your network.

> Note: Toggling `Single User Mode` in configuration page on or off will always
> preserve your VPN settings and WireGuard UI configuration.  It is a safe
> toggle.

## Multi-User Mode

If you disable `Single User Mode` in addon configuration, then you will be
presented with a login page when visiting WireGuard UI web UI.

* Default username: `admin`
* Default password: `admin`

You are advised to change the password after log in and set up more users as you
see fit.
