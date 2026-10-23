# 1.4.0

- Bandwidth throttling: limit the download and/or upload bandwidth of WireGuard clients using firewall-style rules (`throttling_rules`), e.g. `10.252.2.0/24|10mbit,5mbit`.

# 1.3.0

- Add Spoke Networks (hub & fork): route all traffic from a spoke subnet through its hub IP (default `*.1`).

# 1.2.1

- nftables support
- Tentative HAOS 18 support (requires user testing)

# 1.1.142

First changelog entry for 142 releases of development on my wireguard UI where
it's mostly stable with iptables.
