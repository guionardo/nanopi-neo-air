#!/usr/bin/env bash
#
# install-headless-flash.sh — instala o auto-flash da eMMC no cartão eflasher.
#
# O que faz: monta a partição rootfs do cartão (p3, ext4) e instala lá
#   /opt/headless/flash-emmc.sh   (scripts/flash-emmc-headless.sh)
#   /opt/headless/unsparse.sh     (scripts/unsparse.sh)
#   /opt/headless/ARMED           (flag que arma a execução única)
#   /etc/systemd/system/flash-emmc.service  (+ enable)
# e desabilita o eflasher-gui.service (que precisa de display e falha aqui).
#
# Resultado: no próximo boot com o cartão, a eMMC é gravada do payload, a
# partição rootfs é verificada com e2fsck e a placa desliga sozinha.
# Depois: remover o cartão e ligar — o sistema sobe da eMMC.
#
# Uso:
#   sudo ./scripts/install-headless-flash.sh /dev/sdX
#
# Não escreve nada na eMMC; só mexe no cartão.

set -euo pipefail

die() { printf 'erro: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

usage() {
  cat <<'EOF'
Uso: sudo install-headless-flash.sh <sd-device>

  sd-device  dispositivo de bloco inteiro do cartão eflasher (ex: /dev/sdb)

O cartão permanece com todo o payload intacto; apenas ganha um serviço
systemd que grava a eMMC no próximo boot, sem GUI e sem serial.
EOF
}

[[ $# -eq 1 ]] || { usage; exit 1; }
[[ $EUID -eq 0 ]] || die "execute como root (sudo)."

DEV=$1
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FLASH=$HERE/flash-emmc-headless.sh
UNSPARSE=$HERE/unsparse.sh

[[ -f $FLASH ]]    || die "script ausente: $FLASH"
[[ -f $UNSPARSE ]] || die "script ausente: $UNSPARSE"
[[ -b $DEV ]] || die "não é um dispositivo de bloco: $DEV"
[[ $DEV =~ ^/dev/(sd[a-z]+|mmcblk[0-9]+|vd[a-z]+)$ ]] \
  || die "informe o disco inteiro, sem partição (ex: /dev/sdb)"

# --- identificação do cartão -------------------------------------------------
DEV_NAME=$(basename "$DEV")
ROOT_SRC=$(findmnt -no SOURCE / || true)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -n1 || true)
[[ -n $ROOT_DISK && $ROOT_DISK == "$DEV_NAME" ]] \
  && die "recusando $DEV: é o disco do sistema em execução"

# o eflasher tem 3 partições: p1 exFAT (payload), p2 FAT (boot), p3 ext4 (rootfs)
ROOTFS="${DEV}p3"
[[ -e $ROOTFS ]] || { ROOTFS="${DEV}3"; }
[[ -b $ROOTFS ]] || die "partição rootfs não encontrada (esperado ${DEV}p3)"

info "cartão  : $DEV ($(lsblk -bdno SIZE "$DEV" | awk '{print int($1/1024/1024)" MiB"}'))"
info "rootfs  : $ROOTFS"

MNT=$(mktemp -d)
cleanup() { umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true; }
trap cleanup EXIT

# se o desktop automontou a partição, solta antes (evita dois pontos de montagem)
while read -r mp; do
  [[ -z $mp ]] && continue
  info "desmontando montagem automática em $mp..."
  umount "$mp" || die "falha ao desmontar $mp"
done < <(findmnt -rno TARGET --source "$ROOTFS" 2>/dev/null || true)

info "montando $ROOTFS (somente para leitura/escrita do cartão)..."
mount -t ext4 "$ROOTFS" "$MNT" || die "falha ao montar $ROOTFS"

# --- verificação: é mesmo o cartão eflasher? ---------------------------------
[[ -e $MNT/opt/eflasher-gui ]] \
  || die "este cartão não parece ser o eflasher (falta /opt/eflasher-gui)"
[[ -d $MNT/mnt ]] || mkdir -p "$MNT/mnt"
info "cartão eflasher confirmado"

# --- instalar os scripts -----------------------------------------------------
info "instalando scripts em /opt/headless..."
install -d -m 0755 "$MNT/opt/headless"
install -m 0755 "$FLASH"    "$MNT/opt/headless/flash-emmc.sh"
install -m 0755 "$UNSPARSE" "$MNT/opt/headless/unsparse.sh"

# --- unidade systemd ---------------------------------------------------------
info "instalando flash-emmc.service..."
cat > "$MNT/etc/systemd/system/flash-emmc.service" <<'EOF'
[Unit]
Description=Grava eMMC a partir do payload do eflasher (headless, sem GUI)
After=local-fs.target systemd-modules-load.service
Before=eflasher-gui.service multi-user.target
ConditionPathExists=/opt/headless/ARMED

[Service]
Type=oneshot
ExecStart=/opt/headless/flash-emmc.sh
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

ln -sf /etc/systemd/system/flash-emmc.service \
      "$MNT/etc/systemd/system/multi-user.target.wants/flash-emmc.service"

# --- desabilitar a GUI (não roda sem display) --------------------------------
for d in multi-user.target.wants graphical.target.wants; do
  rm -f "$MNT/etc/systemd/system/$d/eflasher-gui.service"
done
ln -sf /dev/null "$MNT/etc/systemd/system/eflasher-gui.service"

# --- armar a execução única --------------------------------------------------
install -m 0644 /dev/null "$MNT/opt/headless/ARMED"
info "auto-flash armado (roda uma vez e se desarma)"

# --- segundo gancho: /etc/rc.local (comprovadamente executado nesta imagem) ---
# O journal da sessão 4 mostra "Started /etc/rc.local" — é um ponto confiável.
# Os dois gatilhos rodam no mesmo boot, então flash-emmc.sh tem uma trava
# (flock) e o segundo a sair sem gravar; sem isso os dois poderiam escrever na
# eMMC ao mesmo tempo.
RCLOCAL=$MNT/etc/rc.local
MARK='# --- auto-flash eMMC (headless) ---'
HOOK='( /opt/headless/flash-emmc.sh >/dev/null 2>&1 & )'
[[ -f $RCLOCAL ]] || printf '#!/bin/sh -e\nexit 0\n' > "$RCLOCAL"

if grep -qF "$MARK" "$RCLOCAL"; then
  info "gancho no rc.local já presente"
else
  awk -v mark="$MARK" -v hook="$HOOK" '
    { line[NR] = $0 }
    END {
      placed = 0
      for (i = 1; i <= NR; i++) {
        if (!placed && line[i] ~ /^[[:space:]]*exit[[:space:]]+0[[:space:]]*$/) {
          print mark; print hook; print ""; placed = 1
        }
        print line[i]
      }
      if (!placed) { print mark; print hook }
    }' "$RCLOCAL" > "$RCLOCAL.new"
  mv "$RCLOCAL.new" "$RCLOCAL"
  chmod 0755 "$RCLOCAL"
  info "gancho adicionado ao rc.local"
fi

if ! grep -qF 'opt/headless/flash-emmc.sh' "$RCLOCAL"; then
  die "não consegui instalar o gancho no rc.local"
fi

sync
umount "$MNT"
trap - EXIT
rmdir "$MNT" 2>/dev/null || true

printf '\n'
info "concluído."
cat <<'EOF'

Próximos passos:
  1. Remover o cartão do PC com segurança.
  2. Colocar no NanoPi e ligar.
  3. O cartão grava a eMMC (~5-10 min, com ruído de I/O no console —
     normal), verifica com e2fsck e desliga sozinho.
  4. Remover o cartão, ligar de novo: o sistema sobe da eMMC.

O resultado fica em /root/flash-emmc.log dentro do cartão (para conferir
depois em outro PC, se algo der errado).
EOF
