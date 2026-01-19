#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Community Add-on: wireguard-ui
# Configures NGINX
# ==============================================================================

ingress_interface=$(bashio::addon.ip_address) || true
sed -i "s/%%interface%%/${ingress_interface:-0.0.0.0}/g" /etc/nginx/servers/ingress.conf
