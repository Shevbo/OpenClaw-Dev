# Запуск с ПК, где "ssh shevbo-cloud" уже работает (тот же ~/.ssh/config).
# Из корня репозитория:  powershell -ExecutionPolicy Bypass -File scripts/wireguard/deploy-wg-autostart-to-cloud.ps1
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
$wg = Join-Path $root "scripts\wireguard"
$remote = "shevbo-cloud"
$dest = "~/wireguard-deploy"

$files = @(
  "shevbo-wg-enable-autostart.sh",
  "shevbo-wg-healthcheck.sh",
  "shevbo-wg-peer-ensure-keepalive.sh",
  "shevbo-wg-health.service",
  "shevbo-wg-health.timer"
)
$paths = $files | ForEach-Object { Join-Path $wg $_ }

Write-Host "scp -> $remote`:$dest"
& scp @paths "${remote}:${dest}/"

Write-Host "remote: strip CRLF, health default, install"
$remoteCmd = @'
set -e
mkdir -p ~/wireguard-deploy
sed -i 's/\r$//' ~/wireguard-deploy/*.sh 2>/dev/null || true
chmod +x ~/wireguard-deploy/*.sh
printf '%s\n' 'WG_IF=wg0' 'WG_HEALTH_TARGET=10.66.0.2' | sudo tee /etc/default/shevbo-wg-health >/dev/null
sudo chmod 644 /etc/default/shevbo-wg-health
cd ~/wireguard-deploy && sudo bash shevbo-wg-enable-autostart.sh
systemctl is-active wg-quick@wg0
systemctl is-active shevbo-wg-health.timer || true
systemctl list-timers shevbo-wg-health.timer --no-pager 2>/dev/null || true
'@
ssh $remote $remoteCmd

Write-Host "Done."
