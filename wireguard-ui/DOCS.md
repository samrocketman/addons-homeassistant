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

## Subnet Ranges

> Subnet ranges configuration is not available from within the web UI and
> requires a server restart in order to apply.

All subnet ranges must fall within _Server Interface Addresses_ found on
_Wireguard Server_ page.  A subnet range is a CIDR.

This feature is intended for subdivision of large wireguard servers, such as
`/16` subnets.  Allocate smaller blocks of the server address space for specific
purposes and easier firewalling.

The format is very specific:

```
<some name>:CIDR,CIDR,CIDR
```

For example, the following is defining multiple subnet ranges.

```
Home:10.252.1.0/24; Office Space:10.38.14.0/16,10.39.1.0/24
```

Note:

* After `:` there's no spaces.
* Multiple CIDRs are comma separated.  Such as those in `Office Space`.
