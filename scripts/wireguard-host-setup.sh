#!/usr/bin/env bash
# УСТАРЕЛО для прод-хоста shevbo-cloud: WireGuard снят, исходящий трафик — через прокси по необходимости.
# Однократная подготовка WireGuard: /etc/wireguard/wg0.conf с полным туннелем (AllowedIPs 0.0.0.0/0).
# Запуск: sudo ./wireguard-host-setup.sh
# После подстановки PublicKey и Endpoint от провайдера: sudo wg-quick up wg0 && sudo systemctl enable wg-quick@wg0
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Нужен sudo"; exit 1; }
umask 077
PRIV="$(wg genkey)"
PUB="$(echo "$PRIV" | wg pubkey)"
CONF="/etc/wireguard/wg0.conf"
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

cat >"$CONF" <<EOF
# WireGuard — полный туннель (весь IPv4/IPv6 через VPN).
# 1) Замените PASTE_* в [Peer] на данные сервера/провайдера.
# 2) Подстройте Address/DNS под выдачу сервера (часто даётся готовый .conf).
# 3) Публичный ключ ЭТОГО клиента (добавьте в peer на сервере):
#    $PUB
#
[Interface]
PrivateKey = $PRIV
Address = 10.200.200.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = PASTE_SERVER_PUBLIC_KEY
Endpoint = PASTE_HOST:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
chmod 600 "$CONF"
echo "Записано: $CONF"
echo "Публичный ключ клиента (добавьте на WG-сервере): $PUB"
echo "Дальше: отредактируйте Peer, затем: sudo wg-quick up wg0 && sudo systemctl enable wg-quick@wg0"
