#!/usr/bin/env bash
#
# install-probe.sh — instala a sonda board-probe.sh no rootfs do cartão e a
# agenda para rodar sozinha no próximo boot.
#
# Serve para diagnosticar a placa sem serial: a placa liga, tenta o Wi-Fi,
# grava o que aconteceu em /root/board-probe.txt, você desliga, põe o cartão no
# PC e lê o arquivo.
#
# Uso:
#   sudo ./scripts/install-probe.sh /dev/sdX

set -uo pipefail

die() { printf 'erro: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

[[ $EUID -eq 0 ]] || die "execute como root (sudo)."
DEV=${1:-}
[[ -n $DEV ]] || die "uso: $0 /dev/sdX"

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SRC=$HERE/board-probe.sh
[[ -f $SRC ]] || die "não achei $SRC"

part_of() {
  local d=$1 n=$2
  case $d in *mmcblk*|*nvme*) echo "${d}p${n}" ;; *) echo "${d}${n}" ;; esac
}

P3=$(part_of "$DEV" 3)
[[ -b $P3 ]] || die "partição rootfs não encontrada: $P3"

R=$(mktemp -d)
cleanup() { umount "$R" 2>/dev/null; rmdir "$R" 2>/dev/null; }
trap cleanup EXIT

while read -r mp; do
  [[ -n $mp ]] && { info "desmontando $mp"; umount "$mp"; }
done < <(findmnt -rno TARGET --source "$P3" 2>/dev/null || true)

info "montando $P3"
mount -t ext4 "$P3" "$R" || die "falha ao montar $P3"

install -d "$R/usr/local/sbin"
install -m 0755 "$SRC" "$R/usr/local/sbin/board-probe.sh"
[[ -x $R/usr/local/sbin/board-probe.sh ]] || die "falha ao instalar a sonda"
info "sonda instalada em /usr/local/sbin/board-probe.sh"

# --- agendamento no boot -----------------------------------------------------
# Unit systemd (e não hook no rc.local): o systemd mata o cgroup quando o
# rc.local termina, então um processo em background disparado de lá não
# sobrevive. Type=simple garante que a sonda roda sem atrasar o boot.
UNIT=$R/etc/systemd/system/board-probe.service
cat > "$UNIT" <<'EOF'
[Unit]
Description=Sonda de diagnostico do Wi-Fi (grava /root/board-probe.txt)
After=network.target
Wants=network.target

[Service]
Type=simple
# espera o ifupdown/wpa_supplicant tentarem o Wi-Fi antes de fotografar
ExecStart=/bin/sh -c 'sleep 45; exec /usr/local/sbin/board-probe.sh'
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$UNIT"

mkdir -p "$R/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/board-probe.service \
      "$R/etc/systemd/system/multi-user.target.wants/board-probe.service"
info "board-probe.service instalado e habilitado (roda 45 s após o boot)"

printf '\n'
info "pronto. Próximo boot da placa grava /root/board-probe.txt"
printf 'Depois: desligue, traga o cartão e rode\n'
printf '  sudo ./scripts/diag-wifi-card.sh %s   # (+ leitura da sonda)\n' "$DEV"

sync
