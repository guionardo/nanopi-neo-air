#!/usr/bin/env bash
#
# diag-wifi-card.sh — por que o wlan0 não subiu (somente leitura).
#
# Lê do cartão: mensagens do brcmfmac/cfg80211 no último boot, estado do
# wpa_supplicant, configuração de rede e os arquivos de firmware.
# A senha do Wi-Fi nunca é impressa.
#
# Uso:
#   sudo ./scripts/diag-wifi-card.sh [device]

set -uo pipefail

die() { printf 'erro: %s\n' "$*" >&2; exit 1; }
sec() { printf '\n===== %s =====\n' "$*"; }
try() { "$@" 2>&1 || printf '  (falhou)\n'; }

[[ $EUID -eq 0 ]] || die "execute como root (sudo)."

part_of() {
  local d=$1 n=$2
  case $d in *mmcblk*|*nvme*) echo "${d}p${n}" ;; *) echo "${d}${n}" ;; esac
}

DEV=${1:-/dev/sdc}
P3=$(part_of "$DEV" 3)
[[ -b $P3 ]] || die "sem p3 em $DEV"

R=$(mktemp -d)
trap 'umount "$R" 2>/dev/null; rmdir "$R" 2>/dev/null' EXIT
mount -t ext4 -o ro "$P3" "$R" || die "falha ao montar $P3"

PAT='brcmfmac|brcm|cfg80211|wlan0|wpa_supplicant|rfkill|dhclient|networking\.service|ifup'

sec "firmware instalado no cartão"
try ls -l "$R/lib/firmware/brcm/" | grep -iE '43430|AP6212|total'
try head -3 "$R/lib/firmware/brcm/brcmfmac43430-sdio.txt"

sec "configuração de rede"
try grep -vE '^\s*#|^\s*$' "$R/etc/network/interfaces"
try cat "$R/etc/network/interfaces.d/"* 2>/dev/null
printf '\n--- wpa_supplicant.conf (senha oculta) ---\n'
try sed -E 's/(psk=).*/\1***OCULTA***/' "$R/etc/wpa_supplicant/wpa_supplicant.conf"

sec "módulo brcmfmac no boot"
try cat "$R/etc/modules" 2>/dev/null | grep -i brcm
try ls "$R/etc/modprobe.d/" 2>/dev/null

sec "getty/serial e masks relevantes"
try ls -l "$R/etc/systemd/system/wpa_supplicant.service" 2>/dev/null

sec "syslog — mensagens de rede do último boot"
if [[ -f $R/var/log/syslog ]]; then
  try grep -iE "$PAT" "$R/var/log/syslog" | tail -n 60
else
  printf '  (sem /var/log/syslog)\n'
fi

sec "journal — último boot"
if [[ -d $R/var/log/journal ]] && command -v journalctl >/dev/null; then
  try journalctl --directory="$R/var/log/journal" -b -1 --no-pager \
        | grep -iE "$PAT" | tail -n 60
  sec "journal — boots gravados"
  try journalctl --directory="$R/var/log/journal" --list-boots --no-pager | tail -5
fi

sec "últimas tarefas do ifupdown"
try ls -l "$R/run/network/" 2>/dev/null
try cat "$R/run/network/ifstate" 2>/dev/null
