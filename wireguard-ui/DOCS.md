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
- Home: 10.252.1.0/24
- Office Space: 10.38.14.0/16,10.39.1.0/24
```

## DMZ Subnets

A default DMZ network is defined.  It is optional and can be removed.

DMZ or Demilitarized Zone in networking strictly grants only internet access
through the VPN.  Useful to allow friends or family to route through your VPN
without granting them local access.

To configure a Wireguard DMZ Subnet:

- Add a new network under your WireGuard server configuration.  For example,
  `10.252.2.0/24`.
- Configure both _Subnet Ranges_ and _DMZ Subnet_.

Example _Subnet Ranges_ configuration:

```
- Home: 10.252.1.0/24
- DMZ Network: 10.252.2.0/24
```

Example _DMZ Subnet_ configuration:

```
10.252.2.0/24
```

## DMZ allowances

**Be aware that by adding DMZ allowances** you impact the restrictions of the
DMZ and in some configurations can make your DMZ inert.  Meaning it **no longer
effectively functions as a DMZ**.  The original intent of this feature is for a
DMZ network capable of connecting to Home Assistant services without being able
to reach other RFC1918 private IP addresses.

Allowances translate into a set of firewall rules. Rules which allow DMZ
connected VPN hosts to connect to RFC1918 private IP space.  For example, allowing
DMZ connected hosts to use Home Assistant DNS (includes AdGuard integration).

The default rules allow Home Assistant DNS.

```yaml
- default_route_ip|53/udp
```

`default_route_ip` automatically translates into an Home Assistant internal
add-on IP address for its default gateway.  Other than `default_route_ip` there
are no special key words.

### DMZ allowance rule format

Generic format: There's at least five ways you can format an allowance rule.

```yaml
- dst_net
- port/proto
- dst_net|port/proto
- src_net||port/proto
- src_net|dst_net|port/proto
```

Definitions:

- `dst_net` - destination network CIDR or an IP address.
- `src_net` - source network CIDR or an IP address.  **Note:** If `src_net` is
  not declared, then the rule applies to all DMZ subnets.
- `port` - the destination port of the connection.
- `proto` - The protocol of the connection.  Only `tcp`, `udp`, or `icmp` is
  allowed.  If value is `any`, then the iptables rule will not include a
  protocol.

The following are examples of how rules translate into iptables commands.  This
is more for advanced users to understand how these rules work.  None of these
examples are recommended.  They are just showcasing the DMZ Allowance Rule
format.

`dst_net` only example (IP as a CIDR).

```yaml
Rule: 172.30.32.1/32
Command: iptables -A WG_DMZ_allow -d 172.30.32.1/32 -j ACCEPT
```

`port/proto` only example.

```yaml
Rule: 53/udp
Command: iptables -A WG_DMZ_allow -p udp -m udp --dport 53 -j ACCEPT
```

`dst_net|port/proto` example.

```yaml
Rule: 172.30.32.1/31|53/udp
Command: iptables -A WG_DMZ_allow -d 172.30.32.1/31 -p udp -m udp --dport 53 -j ACCEPT
```

`src_net|dst_net|port/proto` which allows a specific WireGuard IP to connect to
a TLS host in RFC1918 private IP space.

```yaml
Rule: 10.252.2.1|192.168.0.2|443/tcp
Command: iptables -A WG_DMZ_allow -s 10.252.2.0/24 -d 192.168.0.2 -p tcp -m tcp --dport 443 -j ACCEPT
```

`port` can also be a multiport value.  It should follow the multiport iptables
module syntax of `--dports port[,port|,port:port]...`.

```yaml
Rule: 53,30000:32000/udp
Command: iptables -A WG_DMZ_allow -p udp -m multiport --dports 53,30000:32000 -j ACCEPT
```
