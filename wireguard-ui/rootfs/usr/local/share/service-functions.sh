#!/usr/bin/with-contenv bashio
# shellcheck disable=SC2191
# ==============================================================================
# Home Assistant Community Add-on: Wireguard UI
# Functions intended for /etc/services.d/*/run files
# ==============================================================================
check_config_value() {
  ! {
    [ "$1" = null ] || \
    [ -z "$1" ]
  }
}
try_config_or_default() {
  # $1 - bashio config expr
  # $2 - default fallback value
  local exp="$1 // "'""'
  if {
      bashio::config "$exp" &> /dev/null && \
      check_config_value "$(bashio::config "$exp" 2> /dev/null)"
    }; then
    bashio::config "$exp"
  elif {
      [ -f /data/options.json ] &&
      check_config_value "$(jq -r ."$exp" < /data/options.json)"
    }; then
    jq -r ."$exp" < /data/options.json
  else
    echo "${2:-}"
  fi
}

try_port_or_default() {
  # $1 - bashio config expr
  # $2 - default fallback value
  local exp="$1 // "'""'
  if {
      bashio::addon.port "$exp" &> /dev/null && \
      check_config_value "$(bashio::addon.port "$exp" 2> /dev/null)"
    }; then
    bashio::addon.port "$exp"
  else
    echo "${2:-}"
  fi
}
