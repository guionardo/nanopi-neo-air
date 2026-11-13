#!/usr/bin/env bash
#
# diag-usb-gadget.sh — o que o cartão oferece por USB e por rede (somente leitura).
#
# O journal da sessão 4 mostra "Reached target Hardware activated USB gadget" e
# sshd escutando em 0.0.0.0:22. Este script descobre QUAL gadget a imagem monta
# (rede RNDIS/ECM, console ACM ou armazenamento) e como a rede é configurada.
#
# Se for rede: um cabo micro-USB no PC dá SSH na placa.
# Se for ACM:   equivale a ter console serial, sem adaptador PL2303.
#
# Uso:
#   sudo ./scripts/diag-usb-gadget.sh [device]

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
[[ -b $P3 ]] || die "sem p3 em $DEV (informe: $0 /dev/sdX)"

R=$(mktemp -d)
trap 'umount "$R" 2>/dev/null; rmdir "$R" 2>/dev/null' EXIT
mount -t ext4 -o ro "$P3" "$R" || die "falha ao montar $P3"

sec "alvo do gadget ativado no boot"
try ls -l "$R/etc/systemd/system/"*gadget* 2>/dev/null
try grep -rl 'usb-gadget\|g_ether\|g_serial\|rndis\|configfs' \
      "$R/etc/systemd" "$R/lib/systemd/system" "$R/usr/local" "$R/opt" 2>/dev/null

sec "scripts de gadget na imagem"
for f in "$R/usr/bin/"*gadget* "$R/usr/sbin/"*gadget* "$R/usr/local/bin/"*gadget* \
         "$R/usr/local/sbin/"*gadget*; do
  [[ -f $f ]] || continue
  printf '\n--- %s ---\n' "${f#$R}"
  try sed -n '1,80p' "$f"
done

sec "módulos de gadget disponíveis no kernel 4.14"
try ls "$R/lib/modules/"*/kernel/drivers/usb/gadget/legacy/ 2>/dev/null
try ls "$R/lib/modules/"*/kernel/drivers/usb/gadget/function/ 2>/dev/null

sec "módulos carregados no boot"
try cat "$R/etc/modules"
try ls "$R/etc/modules-load.d/" 2>/dev/null
try grep -r . "$R/etc/modules-load.d/" 2>/dev/null

sec "configuração de rede"
try cat "$R/etc/network/interfaces"
try ls "$R/etc/network/interfaces.d/" 2>/dev/null
try cat "$R/etc/network/interfaces.d/"* 2>/dev/null
try ls -l "$R/etc/wpa_supplicant/" 2>/dev/null
try grep -vE '^\s*#' "$R/etc/wpa_supplicant/wpa_supplicant.conf" 2>/dev/null

sec "getty em porta USB (console por ACM)"
try ls -l "$R/etc/systemd/system/getty.target.wants/"
try grep -rn 'ttyGS\|ttyACM' "$R/etc/systemd/system" 2>/dev/null

sec "firmware de Wi-Fi (brcmfmac 43430)"
try ls "$R/lib/firmware/brcm/" 2>/dev/null
try ls "$R/lib/firmware/" 2>/dev/null | sed -n '1,15p'

sec "usuários e SSH"
try grep -E '^(root|pi):' "$R/etc/shadow" | cut -d: -f1,2 | cut -c1-6
try grep -E '^\s*PermitRootLogin|^\s*PasswordAuthentication|^\s*Port' \
      "$R/etc/ssh/sshd_config" 2>/dev/null
try ls -l "$R/etc/systemd/system/ssh.service" "$R/etc/systemd/system/multi-user.target.wants/ssh.service" 2>/dev/null

sec "hostname"
try cat "$R/etc/hostname"

printf '\n'
