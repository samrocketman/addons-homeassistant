#!/usr/bin/with-contenv bashio
# shellcheck disable=SC2191
# default_route_ip/default_nic are provided by the refresh-wg service at runtime
# shellcheck disable=SC2154
# ==============================================================================
# Home Assistant Community Add-on: Wireguard UI
# Bandwidth throttling for WireGuard networks using tc (traffic control)
#
# Sourced by the refresh-wg service; refresh_wireguard() calls
# refresh_throttling() so the shaping is (re)applied whenever wg0 is
# recreated.
#
# Throttling rules use the same format as the DMZ and Isolated allowance
# rules with a rate appended:
#
#   [src_net|][dst_net|][port/proto|]downrate[,uprate]
#
#   src_net  - WireGuard client IP or subnet.  This is the device being
#              throttled.
#   dst_net  - optional destination IP or subnet the cap applies to.
#   port     - optional service port(s), iptables multiport syntax.
#   proto    - tcp|udp|icmp|any
#   rate     - <n>kbit or <n>mbit, e.g. 10mbit
#
#   downrate - caps traffic TO the device.  Shaped on the wg0 egress path.
#   uprate   - caps traffic FROM the device.  Shaped by mirroring the wg0
#              ingress path to an ifb device and shaping it there.
#
# A rule without any network (e.g. `443/tcp|10mbit` or `10mbit`) throttles
# ALL WireGuard clients.
# ==============================================================================

THROTTLE_RATE_RE='^([1-9][0-9]*(kbit|mbit))(,([1-9][0-9]*(kbit|mbit)))?$'
THROTTLE_PORT_RE='^([0-9,:]+/(tcp|udp|icmp|any))$'
THROTTLE_NET_RE='^(default_route_ip|([0-9]{1,3}\.){3}[0-9]{1,3}(/[1-3]?[0-9])?)$'
TC_PARENT='1:'
TC_PASS_CLASS='1:2'
# pass-through class rate; effectively unlimited for any real traffic
TC_PASS_RATE='10gbit'
THROTTLE_IFB=ifb0
# next classid to allocate (1:10, 1:11, ...)
THROTTLE_CID=10
# a single rule may not expand to more tc filters than this
THROTTLE_MAX_PORT_EXPANSION=1024

# fields of the rule currently being processed
T_DEV=''
T_REMOTE=''
T_PORT=''
T_PROTO=''
T_DOWN=''
T_UP=''

# application state
THROTTLE_DOWN_READY=false
THROTTLE_IFB_READY=false
THROTTLE_IFB_FAILED=false

throttle_is_rate() { [[ "$1" =~ $THROTTLE_RATE_RE ]]; }
throttle_is_port() { [[ "$1" =~ $THROTTLE_PORT_RE ]]; }
throttle_is_net() { [[ "$1" =~ $THROTTLE_NET_RE ]]; }

throttle_parse_rule() {
  # 1 - throttling rule
  #
  # The rate is always the last field.  The fields before it are, in order,
  # an optional src net (the client being throttled), an optional dst net and
  # an optional port/proto.  A leading empty field (|net|rate) leaves the src
  # slot empty, so the net is a destination, exactly like in allowance rules.
  local rule="$1" f
  local -a fields
  IFS='|' read -r -a fields <<< "$rule"
  T_DEV='' T_REMOTE='' T_PORT='' T_PROTO='' T_DOWN='' T_UP=''
  local n="${#fields[@]}"
  if [ "$n" -lt 1 ]; then
    bashio::log.error "[throttle] invalid rule '$rule': missing rate"
    return 1
  fi
  local rate="${fields[$((n - 1))]}"
  if ! throttle_is_rate "$rate"; then
    bashio::log.error "[throttle] invalid rule '$rule': missing or invalid rate"
    return 1
  fi
  T_DOWN="${rate%%,*}"
  T_UP="${rate#*,}"
  [ "$T_UP" = "$T_DOWN" ] && T_UP=''
  local pre=$((n - 1))
  if [ "$pre" -gt 3 ]; then
    bashio::log.error "[throttle] invalid rule '$rule': too many fields"
    return 1
  fi
  local i
  for ((i = 0; i < pre; i++)); do
    f="${fields[i]}"
    [ -n "$f" ] || continue
    if throttle_is_port "$f"; then
      if [ "$i" -lt $((pre - 1)) ]; then
        bashio::log.error "[throttle] invalid rule '$rule': port field must come last"
        return 1
      fi
      T_PORT="${f%/*}"
      T_PROTO="${f##*/}"
    elif throttle_is_net "$f"; then
      case "$i" in
        0) T_DEV="$f" ;;
        1) T_REMOTE="$f" ;;
        *)
          bashio::log.error "[throttle] invalid rule '$rule': more than two networks"
          return 1
          ;;
      esac
    else
      bashio::log.error "[throttle] invalid rule '$rule': unrecognized field '$f'"
      return 1
    fi
  done
  return 0
}

throttle_resolve_net() {
  if [ "$1" = default_route_ip ]; then
    echo "${default_route_ip}"
  else
    echo "$1"
  fi
}

throttle_proto_num() {
  case "$1" in
    tcp) echo 6 ;;
    udp) echo 17 ;;
    icmp) echo 1 ;;
    *) return 1 ;;
  esac
}

throttle_expand_ports() {
  # 1 - port field (multiport syntax)
  # 2 - name of the array to fill
  local spec lo hi p
  local -n ports_out="$2"
  ports_out=()
  while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    lo="${spec%%:*}"
    hi="${spec#*:}"
    [ "$hi" = "$lo" ] && hi="$lo"
    if [ "$(( hi - lo + 1 ))" -gt "$THROTTLE_MAX_PORT_EXPANSION" ]; then
      bashio::log.error "[throttle] port range ${spec} expands to more than ${THROTTLE_MAX_PORT_EXPANSION} ports; refusing to apply rule"
      return 1
    fi
    for ((p = lo; p <= hi; p++)); do
      ports_out+=( "$p" )
    done
  done <<< "$(tr ',' '\n' <<< "$1")"
  return 0
}

throttle_clear() {
  command -v tc > /dev/null 2>&1 || return 0
  # drop the qdiscs (and the filters inside them) before deleting the ifb
  # device: a mirred filter holds a reference to its target device, so the
  # device must outlive the filter that points at it
  tc qdisc del dev wg0 ingress 2> /dev/null || true
  tc qdisc del dev wg0 root 2> /dev/null || true
  tc qdisc del dev "$THROTTLE_IFB" root 2> /dev/null || true
  ip link del "$THROTTLE_IFB" 2> /dev/null || true
  return 0
}

throttle_setup_htb_root() {
  # 1 - interface
  local dev="$1"
  tc qdisc add dev "$dev" root handle "$TC_PARENT" htb default "$TC_PASS_CLASS"
  tc class add dev "$dev" parent "$TC_PARENT" classid "$TC_PASS_CLASS" htb rate "$TC_PASS_RATE"
}

throttle_setup_ifb() {
  modprobe ifb 2> /dev/null || true
  ip link add dev "$THROTTLE_IFB" type ifb || return 1
  ip link set dev "$THROTTLE_IFB" up
  throttle_setup_htb_root "$THROTTLE_IFB"
  tc qdisc add dev wg0 ingress
  return 0
}

throttle_emit_rule() {
  # 1 - interface (wg0 or ifb)
  # 2 - classid
  # 3 - direction (down|up)
  #
  # down (egress, traffic to the device):  device is ip dst, remote is ip src,
  #                                        service port is the sport
  # up   (ingress via ifb, from the device): device is ip src, remote is ip dst,
  #                                        service port is the dport
  local iface="$1" cid="$2" dir="$3"
  local portkind
  if [ "$dir" = down ]; then portkind=sport; else portkind=dport; fi
  local dev remote
  if [ -n "$T_DEV" ]; then
    dev="$(throttle_resolve_net "$T_DEV")"
  fi
  if [ -n "$T_REMOTE" ]; then
    remote="$(throttle_resolve_net "$T_REMOTE")"
  fi
  local proto="${T_PROTO:-}"
  local ports=()
  if [ -n "$T_PORT" ] && [ "$proto" != icmp ]; then
    throttle_expand_ports "$T_PORT" ports || return 1
  fi
  local -a protos=()
  if [ -z "$proto" ] || [ "$proto" = any ]; then
    if [ "${#ports[@]}" -gt 0 ]; then
      # a port only makes sense for tcp/udp
      protos=( 6 17 )
    fi
  else
    protos=( "$(throttle_proto_num "$proto")" )
  fi
  local -a base=()
  if [ -n "$T_DEV" ]; then
    if [ "$dir" = down ]; then
      base+=( ip dst "$dev" )
    else
      base+=( ip src "$dev" )
    fi
  fi
  if [ -n "$T_REMOTE" ]; then
    if [ "$dir" = down ]; then
      base+=( ip src "$remote" )
    else
      base+=( ip dst "$remote" )
    fi
  fi
  local pn p
  if [ "${#protos[@]}" -eq 0 ]; then
    # any protocol, no port restriction
    if [ "${#base[@]}" -gt 0 ]; then
      tc filter add dev "$iface" parent "$TC_PARENT" protocol ip u32 match "${base[@]}" flowid "$cid"
    else
      tc filter add dev "$iface" parent "$TC_PARENT" protocol ip u32 flowid "$cid"
    fi
    return 0
  fi
  for pn in "${protos[@]}"; do
    local -a match=( "${base[@]}" ip proto "$pn" )
    if [ "${#ports[@]}" -gt 0 ]; then
      for p in "${ports[@]}"; do
        tc filter add dev "$iface" parent "$TC_PARENT" protocol ip u32 \
          match "${match[@]}" ip "$portkind" "$p" 0xffff flowid "$cid"
      done
    else
      tc filter add dev "$iface" parent "$TC_PARENT" protocol ip u32 \
        match "${match[@]}" flowid "$cid"
    fi
  done
  return 0
}

throttle_add_mirror() {
  # redirect the device's upload traffic from wg0 ingress to the ifb device
  local -a match=()
  if [ -n "$T_DEV" ]; then
    match+=( ip src "$(throttle_resolve_net "$T_DEV")" )
  fi
  if [ "${#match[@]}" -gt 0 ]; then
    tc filter add dev wg0 parent :0 protocol ip u32 \
      match "${match[@]}" mirred redir to "$THROTTLE_IFB"
  else
    tc filter add dev wg0 parent :0 protocol ip u32 \
      mirred redir to "$THROTTLE_IFB"
  fi
}

throttle_apply_down() {
  if [ -n "$T_PORT" ] && [ "${T_PROTO:-}" != icmp ]; then
    local _ports=()
    throttle_expand_ports "$T_PORT" _ports || return 1
  fi
  if [ "$THROTTLE_DOWN_READY" != true ]; then
    throttle_setup_htb_root wg0 || return 1
    THROTTLE_DOWN_READY=true
  fi
  local cid
  THROTTLE_CID=$((THROTTLE_CID + 1))
  cid="1:${THROTTLE_CID}"
  tc class add dev wg0 parent "$TC_PARENT" classid "$cid" htb rate "$T_DOWN" || return 1
  throttle_emit_rule wg0 "$cid" down
}

throttle_apply_up() {
  if [ -n "$T_PORT" ] && [ "${T_PROTO:-}" != icmp ]; then
    local _ports=()
    throttle_expand_ports "$T_PORT" _ports || return 1
  fi
  if [ "$THROTTLE_IFB_READY" != true ]; then
    # once ifb creation has failed it will keep failing, so stop retrying
    if [ "$THROTTLE_IFB_FAILED" = true ]; then
      return 1
    fi
    if ! throttle_setup_ifb; then
      bashio::log.warning "[throttle] could not create the ${THROTTLE_IFB} device (is the ifb kernel module available?); upload throttling skipped"
      THROTTLE_IFB_FAILED=true
      return 1
    fi
    THROTTLE_IFB_READY=true
  fi
  local cid
  THROTTLE_CID=$((THROTTLE_CID + 1))
  cid="1:${THROTTLE_CID}"
  tc class add dev "$THROTTLE_IFB" parent "$TC_PARENT" classid "$cid" htb rate "$T_UP" || return 1
  throttle_emit_rule "$THROTTLE_IFB" "$cid" up || return 1
  throttle_add_mirror
  return 0
}

refresh_throttling() {
  local rules rule applied=0 rejected=0
  rules="$(try_config_or_default 'throttling_rules | join(" ")?')"
  throttle_clear
  if [ -z "$rules" ]; then
    bashio::log.info '[throttle] no throttling rules configured.'
    return 0
  fi
  if ! command -v tc > /dev/null 2>&1; then
    bashio::log.error '[throttle] tc (iproute2) is required for bandwidth throttling but was not found.'
    return 1
  fi
  if ! ip link show wg0 > /dev/null 2>&1; then
    bashio::log.warning '[throttle] wg0 interface is not up yet; throttling not applied.'
    return 0
  fi
  THROTTLE_CID=10
  THROTTLE_DOWN_READY=false
  THROTTLE_IFB_READY=false
  THROTTLE_IFB_FAILED=false
  local -a RULES=()
  read -r -a RULES <<< "$rules"
  for rule in "${RULES[@]}"; do
    [ -n "$rule" ] || continue
    local down_ok=true up_ok=true
    if ! throttle_parse_rule "$rule"; then
      rejected=$((rejected + 1))
      continue
    fi
    if [ -n "$T_DOWN" ] && ! throttle_apply_down; then
      down_ok=false
    fi
    if [ -n "$T_UP" ] && ! throttle_apply_up; then
      up_ok=false
    fi
    local applied_dirs=0
    if [ -n "$T_DOWN" ] && [ "$down_ok" = true ]; then
      applied_dirs=$((applied_dirs + 1))
    fi
    if [ -n "$T_UP" ] && [ "$up_ok" = true ]; then
      applied_dirs=$((applied_dirs + 1))
    fi
    if [ "$applied_dirs" -eq 0 ]; then
      rejected=$((rejected + 1))
    else
      # a rule is applied as long as one of its caps took effect; the other
      # direction is reported as skipped rather than the whole rule rejected
      applied=$((applied + 1))
      bashio::log.info "[throttle] applied: ${rule} (down: ${T_DOWN:-none}, up: ${T_UP:-none})"
      if [ "$down_ok" = false ]; then
        bashio::log.warning "[throttle] ${rule}: download cap not applied"
      fi
      if [ "$up_ok" = false ]; then
        bashio::log.warning "[throttle] ${rule}: upload cap not applied"
      fi
    fi
  done
  if [ "$applied" -eq 0 ]; then
    bashio::log.error "[throttle] all ${rejected} throttling rule(s) were rejected."
    return 1
  fi
  bashio::log.info "[throttle] ${applied} rule(s) applied, ${rejected} rejected."
  tc qdisc show dev wg0
  if [ "$THROTTLE_IFB_READY" = true ]; then
    tc qdisc show dev "$THROTTLE_IFB"
  fi
  return 0
}
