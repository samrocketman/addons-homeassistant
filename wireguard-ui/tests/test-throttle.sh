#!/usr/bin/env bash
# ==============================================================================
# Unit tests for usr/local/share/throttle.sh
#
# Runs the throttling engine with stubbed tc/ip/modprobe binaries and asserts
# the traffic control commands that would be programmed.  No privileges or
# WireGuard setup required.
#
#   make throttle   (or: bash tests/test-throttle.sh)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOTFS="$(cd "$SCRIPT_DIR/.." && pwd)/rootfs"
THROTTLE_SH="$ROOTFS/usr/local/share/throttle.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"
LOG="$WORK/cmd.log"
mkdir -p "$BIN"
touch "$LOG"
export LOG

# ------------------------------------------------------------------- stubs ---
cat > "$BIN/tc" <<EOF
#!/usr/bin/env bash
echo "tc \$*" >> "$LOG"
exit 0
EOF
cat > "$BIN/modprobe" <<EOF
#!/usr/bin/env bash
echo "modprobe \$*" >> "$LOG"
exit 0
EOF
chmod +x "$BIN/tc" "$BIN/modprobe"

# default ip stub: everything succeeds
default_ip_stub() {
  cat > "$BIN/ip" <<EOF
#!/usr/bin/env bash
echo "ip \$*" >> "$LOG"
exit 0
EOF
  chmod +x "$BIN/ip"
}
default_ip_stub

ENGINE_OUT="$WORK/engine.out"

# runs refresh_throttling with the current TEST_RULES and logs the result;
# the engine's own log lines are kept in $ENGINE_OUT for assertions
assert_engine() {
  export TEST_RULES
  env PATH="$BIN:$PATH" bash -c '
    set -uo pipefail
    bashio::log.info()    { echo "INFO: $*"; }
    bashio::log.warning() { echo "WARN: $*"; }
    bashio::log.error()   { echo "ERROR: $*"; }
    try_config_or_default() { echo "${TEST_RULES:-}"; }
    default_nic=eth0
    default_route_ip=172.30.32.1
    source "$1"
    refresh_throttling || echo "ENGINE-RC=$?"
  ' _ "$THROTTLE_SH" 2>&1 | tee "$ENGINE_OUT" | sed 's/^/    /'
}

# runs throttle_parse_rule and echoes the resulting globals
parse_rule() {
  env bash -c '
    set -uo pipefail
    bashio::log.error() { :; }
    source "$1"
    throttle_parse_rule "$2" || exit 1
    echo "DEV=$T_DEV REMOTE=$T_REMOTE PORT=$T_PORT PROTO=$T_PROTO DOWN=$T_DOWN UP=$T_UP"
  ' _ "$THROTTLE_SH" "$1"
}

# --------------------------------------------------------------- assertions --
FAILURES=0
expect_log() {
  if grep -qF -- "$2" "$LOG"; then
    echo "  ok: $1"
  else
    echo "  FAIL: $1"
    echo "    missing: $2"
    FAILURES=$((FAILURES + 1))
  fi
}
expect_no_log() {
  if grep -qF -- "$2" "$LOG"; then
    echo "  FAIL: $1"
    echo "    unexpectedly present: $2"
    FAILURES=$((FAILURES + 1))
  else
    echo "  ok: $1"
  fi
}
expect_engine() {
  if grep -qF -- "$2" "$ENGINE_OUT"; then
    echo "  ok: $1"
  else
    echo "  FAIL: $1"
    echo "    missing: $2"
    FAILURES=$((FAILURES + 1))
  fi
}
expect_parse() {
  # $1 - description, $2 - rule, $3 - expected "DEV=.. REMOTE=.. ..." line
  local out
  out="$(parse_rule "$2")"
  if [ "$out" = "$3" ]; then
    echo "  ok: $1"
  else
    echo "  FAIL: $1"
    echo "    rule:      $2"
    echo "    expected:  $3"
    echo "    got:       $out"
    FAILURES=$((FAILURES + 1))
  fi
}
reject_parse() {
  # $1 - description, $2 - rule that must be rejected
  if parse_rule "$2" > /dev/null 2>&1; then
    echo "  FAIL: $1 (rule was accepted)"
    FAILURES=$((FAILURES + 1))
  else
    echo "  ok: $1"
  fi
}

# -------------------------------------------------------------------- tests --
echo "== parse: device only"
expect_parse "down only" "10.252.2.0/24|10mbit" \
  "DEV=10.252.2.0/24 REMOTE= PORT= PROTO= DOWN=10mbit UP="
expect_parse "down+up" "10.252.2.1|10mbit,5mbit" \
  "DEV=10.252.2.1 REMOTE= PORT= PROTO= DOWN=10mbit UP=5mbit"

echo
echo "== parse: full rule"
expect_parse "dev|remote|port|down,up" "10.252.2.1|192.168.1.50|443/tcp|10mbit,5mbit" \
  "DEV=10.252.2.1 REMOTE=192.168.1.50 PORT=443 PROTO=tcp DOWN=10mbit UP=5mbit"
expect_parse "dev|remote|down,up" "10.252.2.1|192.168.1.50|10mbit,5mbit" \
  "DEV=10.252.2.1 REMOTE=192.168.1.50 PORT= PROTO= DOWN=10mbit UP=5mbit"
expect_parse "empty remote" "10.252.2.1||443/udp|1mbit" \
  "DEV=10.252.2.1 REMOTE= PORT=443 PROTO=udp DOWN=1mbit UP="
expect_parse "port only" "443/tcp|10mbit" \
  "DEV= REMOTE= PORT=443 PROTO=tcp DOWN=10mbit UP="
expect_parse "global" "10mbit,5mbit" \
  "DEV= REMOTE= PORT= PROTO= DOWN=10mbit UP=5mbit"
expect_parse "icmp port ignored later" "10.252.2.1|0/icmp|50kbit" \
  "DEV=10.252.2.1 REMOTE= PORT=0 PROTO=icmp DOWN=50kbit UP="
expect_parse "dst only (leading empty src)" "|192.168.1.50|10mbit" \
  "DEV= REMOTE=192.168.1.50 PORT= PROTO= DOWN=10mbit UP="
expect_parse "dst only with port" "|192.168.1.50|443/tcp|1mbit" \
  "DEV= REMOTE=192.168.1.50 PORT=443 PROTO=tcp DOWN=1mbit UP="
expect_parse "dst only up+down" "|default_route_ip|10mbit,5mbit" \
  "DEV= REMOTE=default_route_ip PORT= PROTO= DOWN=10mbit UP=5mbit"

echo
echo "== parse: invalid rules are rejected"
reject_parse "missing rate" "10.252.2.1"
reject_parse "missing rate (port)" "443/tcp"
reject_parse "two rates" "10.252.2.1|10mbit|5mbit"
reject_parse "three networks" "10.252.2.1|192.168.1.50|172.16.0.1|1mbit"
reject_parse "port not last" "443/tcp|192.168.1.50|1mbit"
reject_parse "three nets + port" "10.252.2.1|192.168.1.50|172.16.0.1|443/tcp|1mbit"
reject_parse "bad field" "10.252.2.1|junk|10mbit"
reject_parse "bad proto" "10.252.2.1|80/http|1mbit"
reject_parse "empty rule" ""

echo
echo "== apply: device download cap on wg0 egress"
TEST_RULES="10.252.2.0/24|10mbit"
: > "$LOG"
assert_engine
expect_log "htb root on wg0"  'tc qdisc add dev wg0 root handle 1: htb default 1:2'
expect_log "pass-through cl"  'tc class add dev wg0 parent 1: classid 1:2 htb rate 10gbit'
expect_log "throttle class"   'tc class add dev wg0 parent 1: classid 1:11 htb rate 10mbit'
expect_log "dst filter"       'tc filter add dev wg0 parent 1: protocol ip u32 match ip dst 10.252.2.0/24 flowid 1:11'
expect_no_log "no ifb"        'ip link add dev ifb0'

echo
echo "== apply: dst-only rule shapes all clients toward the destination"
TEST_RULES="|192.168.1.50|10mbit"
: > "$LOG"
assert_engine
# down traffic flows server -> client, so the destination net is ip src on
# the wg0 egress path
expect_log "dst down filter" 'match ip src 192.168.1.50 flowid 1:11'
expect_no_log "no dev match" 'ip dst 192.168.1.50'

echo
echo "== apply: dev+remote+port with down and up"
TEST_RULES="10.252.2.1|192.168.1.50|443/tcp|10mbit,5mbit"
: > "$LOG"
assert_engine
expect_log "down class"     'tc class add dev wg0 parent 1: classid 1:11 htb rate 10mbit'
expect_log "down filter"    'match ip dst 10.252.2.1 ip src 192.168.1.50 ip proto 6 ip sport 443 0xffff flowid 1:11'
expect_log "ifb created"    'ip link add dev ifb0 type ifb'
expect_log "ifb htb root"   'tc qdisc add dev ifb0 root handle 1: htb default 1:2'
expect_log "wg0 ingress"    'tc qdisc add dev wg0 ingress'
expect_log "up class"       'tc class add dev ifb0 parent 1: classid 1:12 htb rate 5mbit'
expect_log "up filter"      'match ip src 10.252.2.1 ip dst 192.168.1.50 ip proto 6 ip dport 443 0xffff flowid 1:12'
expect_log "mirror filter"  'tc filter add dev wg0 parent :0 protocol ip u32 match ip src 10.252.2.1 mirred redir to ifb0'

echo
echo "== apply: global rule shapes all WireGuard traffic"
TEST_RULES="10mbit,5mbit"
: > "$LOG"
assert_engine
expect_log "catch-all down"  'tc filter add dev wg0 parent 1: protocol ip u32 flowid 1:11'
expect_log "catch-all up"    'tc filter add dev ifb0 parent 1: protocol ip u32 flowid 1:12'
expect_log "catch-all mirr"  'tc filter add dev wg0 parent :0 protocol ip u32 mirred redir to ifb0'

echo
echo "== apply: udp multiport with range expansion"
TEST_RULES="10.252.2.1|53,8080:8082/udp|1mbit"
: > "$LOG"
assert_engine
expect_log "port 53"    'ip sport 53 0xffff flowid 1:11'
expect_log "port 8080"  'ip sport 8080 0xffff flowid 1:11'
expect_log "port 8082"  'ip sport 8082 0xffff flowid 1:11'
expect_log "udp proto"  'ip proto 17'

echo
echo "== apply: icmp rule matches protocol only"
TEST_RULES="10.252.2.1|192.168.1.50|0/icmp|50kbit"
: > "$LOG"
assert_engine
expect_log "icmp filter"  'match ip dst 10.252.2.1 ip src 192.168.1.50 ip proto 1 flowid 1:11'
expect_no_log "no ports"  'ip sport'

echo
echo "== apply: any proto with port emits tcp and udp filters"
TEST_RULES="10.252.2.1|443/any|1mbit"
: > "$LOG"
assert_engine
expect_log "tcp filter" 'match ip dst 10.252.2.1 ip proto 6 ip sport 443 0xffff flowid 1:11'
expect_log "udp filter" 'match ip dst 10.252.2.1 ip proto 17 ip sport 443 0xffff flowid 1:11'

echo
echo "== apply: default_route_ip resolves to the gateway"
TEST_RULES="10.252.2.1|default_route_ip|10mbit"
: > "$LOG"
assert_engine
expect_log "resolved" 'ip src 172.30.32.1'

echo
echo "== apply: multiple rules get sequential classes"
TEST_RULES="10.252.2.1|10mbit 10.252.3.0/24|1mbit 10.252.4.0/24|500kbit,250kbit"
: > "$LOG"
assert_engine
expect_log "class 11" 'tc class add dev wg0 parent 1: classid 1:11 htb rate 10mbit'
expect_log "class 12" 'tc class add dev wg0 parent 1: classid 1:12 htb rate 1mbit'
expect_log "class 13" 'tc class add dev wg0 parent 1: classid 1:13 htb rate 500kbit'
expect_log "ifb 14"   'tc class add dev ifb0 parent 1: classid 1:14 htb rate 250kbit'

echo
echo "== apply: ifb unavailable degrades to download throttling only"
TEST_RULES="10.252.2.1|10mbit,5mbit"
cat > "$BIN/ip" <<EOF
#!/usr/bin/env bash
echo "ip \$*" >> "$LOG"
case "\$*" in
  "link add dev ifb0 type ifb") exit 1 ;;
esac
exit 0
EOF
chmod +x "$BIN/ip"
: > "$LOG"
assert_engine
expect_log "down applied"  'tc class add dev wg0 parent 1: classid 1:11 htb rate 10mbit'
expect_no_log "no up"      'tc class add dev ifb0 parent 1: classid 1:12 htb rate 5mbit'
expect_engine "counted applied" '1 rule(s) applied, 0 rejected.'
expect_engine "up skip warning" 'upload cap not applied'
default_ip_stub

echo
echo "== apply: no rules clears state"
TEST_RULES=""
: > "$LOG"
assert_engine
expect_log "clear root"  'tc qdisc del dev wg0 root'
expect_log "del ingress" 'tc qdisc del dev wg0 ingress'
expect_log "del ifb"     'ip link del ifb0'
expect_no_log "no class" 'tc class add'
# the ingress qdisc (holding the mirred filter) must be dropped before the
# ifb device is deleted, or the device deletion can block on the reference
line_ingress="$(grep -nF 'tc qdisc del dev wg0 ingress' "$LOG" | cut -d: -f1)"
line_ifb="$(grep -nF 'ip link del ifb0' "$LOG" | cut -d: -f1)"
if [ -n "$line_ingress" ] && [ -n "$line_ifb" ] && [ "$line_ingress" -lt "$line_ifb" ]; then
  echo "  ok: ingress qdisc removed before ifb device"
else
  echo "  FAIL: ingress qdisc removed before ifb device (ingress=$line_ingress ifb=$line_ifb)"
  FAILURES=$((FAILURES + 1))
fi

echo
echo "== apply: oversized port range is refused"
TEST_RULES="10.252.2.1|1:65535/udp|1mbit"
: > "$LOG"
assert_engine
expect_no_log "refused" 'tc class add dev wg0'
expect_engine "counted rejected" 'all 1 throttling rule(s) were rejected.'

echo
echo "========================================"
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL THROTTLE TESTS PASSED"
  exit 0
fi
echo "$FAILURES THROTTLE TEST(S) FAILED"
exit 1
