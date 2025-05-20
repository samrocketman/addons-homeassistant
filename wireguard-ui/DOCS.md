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
> requires a server restart in order to apply.  Review startup logs to verify
> WireGuard UI accepted the provided subnet ranges.

All subnet ranges **must fall within** _Server Interface Addresses_ found on
_Wireguard Server_ page.  A subnet range is a CIDR.

This feature is intended for subdivision of large wireguard servers, such as
`/16` subnets.  Allocate smaller blocks of the server address space for specific
purposes and easier firewalling.

The format is very specific:

```yaml
some name: CIDR[,CIDR][,...]
```

By default, the following _Subnet Ranges_ are available.

```yaml
- "Home: 10.252.1.0/24"
- "DMZ Network: 10.252.2.0/24"
```

Multiple networks (CIDR) can be associated with a single Subnet Range.

```yaml
- "Home: 10.252.1.0/24"
- "Office Space: 10.38.14.0/16,10.39.1.0/24"
```

## DMZ Subnets

A default DMZ network is defined.  It is optional and can be removed.

DMZ or Demilitarized Zone in networking strictly grants only internet access
through the VPN.  Useful to allow friends or family to route through your VPN
without granting them local access.

By default, the following _DMZ Subnet_ is available.

```yaml
- 10.252.2.0/24
```


## DMZ Allowances

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

`default_route_ip` automatically translates into the internal add-on default
gateway.  Other than `default_route_ip` there are no special key words.  Home
Assistant is accessible via the default gateway IP.

### DMZ allowance rule format

Generic format: There's seven ways you can format an allowance rule.

```yaml
- dst_net
- port/proto
- dst_net|port/proto
- src_net|
- src_net|dst_net
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

`dst_net` only example (IP as a CIDR).  Because `src_net` is not defined it will
always default to one or more rules to cover all DMZ subnets.

```yaml
Rule: 172.30.32.1/32
Command: iptables -A WG_DMZ_allow -s 10.252.2.0/24 -d 172.30.32.1/32 -j ACCEPT
```

`port/proto` only example.

```yaml
Rule: 53/udp
Command: iptables -A WG_DMZ_allow -s 10.252.2.0/24 -p udp -m udp --dport 53 -j ACCEPT
```

`dst_net|port/proto` example.

```yaml
Rule: 172.30.32.1/31|53/udp
Command: iptables -A WG_DMZ_allow -s 10.252.2.0/24 -d 172.30.32.1/31 -p udp -m udp --dport 53 -j ACCEPT
```

`src_net|dst_net|port/proto` which allows a specific WireGuard IP to connect to
a TLS host in RFC1918 private IP space.

```yaml
Rule: 10.252.2.1|192.168.0.2|443/tcp
Command: iptables -A WG_DMZ_allow -s 10.252.2.1 -d 192.168.0.2 -p tcp -m tcp --dport 443 -j ACCEPT
```

`port` can also be a multiport value.  It should follow the multiport iptables
module syntax of `--dports port[,port|,port:port]...`.

```yaml
Rule: 53,30000:32000/udp
Command: iptables -A WG_DMZ_allow -s 10.252.2.0/24 -p udp -m multiport --dports 53,30000:32000 -j ACCEPT
```

`icmp` example.  In general, all ICMP traffic is allowed because the DMZ
networks allow RELATED traffic (of which all ICMPv4 traffic falls under RELATED
with exception for `ping`).  However, you can use an `icmp` rule to also grant
ping.  The port number is ignored so always using `0` is fine.  The following
example allows ping for home assistant IP.

```yaml
Rule: default_route_ip|0/icmp
Command: iptables -A WG_DMZ_allow -s 10.252.2.0/24 -d 172.30.32.1 -p icmp --icmp-type echo-request -j ACCEPT
```

### Example: DMZ with HA access

This example uses a mix of DMZ configuration with DMZ allowances in order to
grant only Home Assistant access (IP and port) via the DMZ network. Any other
LAN IP or port is still blocked for the DMZ Subnet.

First, add a new network via WireGuard UI web UI.

1. Visit web UI.
2. Click _Wireguard Server_ menu.
3. Under _Server Interface Addresses_ add a new network `10.252.3.0/24`.

Next, visit Home Assistant _Settings_, _Add-ons_, _WireGuard UI_, and select
_Configuration_ pane.  You'll need to add configurations to:

- _Subnet Ranges_
- _DMZ Subnets_
- _DMZ Allowances_

Example _Subnet Ranges_ configuration (adding on to default):

```yaml
- "Home: 10.252.1.0/24"
- "DMZ Network: 10.252.2.0/24"
- "DMZ with HA access: 10.252.3.0/24"
```

Example _DMZ Subnet_ configuration (adding on to default):

```yaml
- 10.252.2.0/24
- 10.252.3.0/24
```

Example _DMZ Allowances_ configuration (adding on to default):

```yaml
- default_route_ip|53/udp
- 10.252.3.0/24|default_route_ip|8123/tcp
```

- If you're connected via VPN, then save settings without restart.  Restart the
  Add-on from the _Info_ pane.
- Otherwise if you're connected directly on your LAN you can save and restart.

Add a new client within `DMZ with HA access` subnet and configure WireGuard on a
device with the new client.  By default, Home Assistant should be accessible via
the following address.

```
http://172.30.32.1:8123
```

> **Note**: your WireGuard client should be using the Home Assistant internal IP
> address as the DNS server.  If this differs from the provided example, then
> use that IP instead.  e.g. `http://<wireguard_dns_ip>:8123`.

## Isolated Subnets

By default, no Isolated Subnets are defined.

If defined, all hosts on the isolated subnet cannot connect to any other network
and cannot connect to other hosts on the same network.  You'll need to specify
connectivity through _Isolated Allowances_.

## Isolated Allowances

Similar to _DMZ Allowances_ except it applies to _Isolated Subnets_.  Refer to
_DMZ Allowances_ section for more information about the format.

### Example: Isolated with intranet

In this example, we'll configure an isolated network where hosts connected to
the isolated network can talk to each other but not allowed to connect to other
networks (i.e. no internet or other LAN access).

First, add a new network via WireGuard UI web UI.

1. Visit web UI.
2. Click _Wireguard Server_ menu.
3. Under _Server Interface Addresses_ add a new network `10.252.4.0/24`.

Next, visit Home Assistant _Settings_, _Add-ons_, _WireGuard UI_, and select
_Configuration_ pane.  You'll need to add configurations to:

- _Subnet Ranges_
- _Isolated Subnets_
- _Isolated Allowances_

Example _Subnet Ranges_ configuration (adding on to default):

```yaml
- "Home: 10.252.1.0/24"
- "DMZ Network: 10.252.2.0/24"
- "Isolated with intranet: 10.252.4.0/24"
```

Example _Isolated Subnet_ configuration:

```yaml
- 10.252.4.0/24
```

Example _Isolated Allowances_ configuration:

```yaml
- 10.252.4.0/24|10.252.4.0/24
```

### Example: Isolated with HA access

In this example, an isolated network will be granted access to connect to Home
Assistant.  Hosts on this network cannot talk with each other or other networks.

The use case would be IoT devices connected to a wireless network.  All traffic
from the wireless network is encrypted and NAT through WireGuard.

First, add a new network via WireGuard UI web UI.

1. Visit web UI.
2. Click _Wireguard Server_ menu.
3. Under _Server Interface Addresses_ add a new network `10.252.5.0/24`.

Next, visit Home Assistant _Settings_, _Add-ons_, _WireGuard UI_, and select
_Configuration_ pane.  You'll need to add configurations to:

- _Subnet Ranges_
- _Isolated Subnets_
- _Isolated Allowances_

Example _Subnet Ranges_ configuration (adding on to default):

```yaml
- "Home: 10.252.1.0/24"
- "DMZ Network: 10.252.2.0/24"
- "Isolated with HA access: 10.252.5.0/24"
```

Example _Isolated Subnet_ configuration:

```yaml
- 10.252.5.0/24
```

Example _Isolated Allowances_ configuration:

```yaml
- 10.252.5.0/24|default_route_ip|8123/tcp
```
