#!/bin/bash
#
# flash-emmc-headless.sh — grava a eMMC a partir do payload do eflasher,
# sem GUI e sem console serial.
#
# Roda DENTRO do rootfs do cartão eflasher (Debian 12 core), como serviço
# systemd oneshot no primeiro boot. Faz o que o /opt/eflasher-gui faria, mas
# lendo o payload Android sparse com scripts/unsparse.sh.
#
# Instalação: scripts/install-headless-flash.sh (executado no PC, com sudo).
# Chamado por: /etc/systemd/system/flash-emmc.service
#
# Sem argumentos. Ao final: desarma-se e desliga a placa.

set -uo pipefail

PAYLOAD_DIR=/mnt/debian-bookworm-core
UNSPARSE=/opt/headless/unsparse.sh
ARMED=/opt/headless/ARMED
LOG=/root/flash-emmc.log
MNT=/mnt

# --- log em arquivo e no console ---------------------------------------------
exec >>"$LOG" 2>&1

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { log "ERRO: $*"; log "FLASH_FAILED — placa NAO sera desligada"; exit 1; }

log "===== inicio do flash headless ====="

[[ -f $ARMED ]] || die "flag $ARMED ausente; nada a fazer"
rm -f "$ARMED"          # desarma: nunca roda duas vezes

# --- localizar o SD (boot) e a eMMC (destino) --------------------------------
root_src=$(findmnt -no SOURCE / 2>/dev/null || true)
root_disk=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -n1 || true)
[[ -n $root_disk ]] || die "nao consegui identificar o disco do sistema em execucao"
log "sistema em execucao em /dev/$root_disk"

emmc=""
for d in /sys/block/mmcblk*; do
  n=$(basename "$d")
  case $n in *boot*|*rpmb) continue ;; esac
  [[ $n == "$root_disk" ]] && continue
  emmc=$n
done
[[ -n $emmc ]] || die "nenhum disco eMMC encontrado (alem do SD $root_disk)"

EMMC=/dev/$emmc
EMMC_BYTES=$(lsblk -bdno SIZE "$EMMC") || die "nao consegui ler o tamanho de $EMMC"
log "destino: $EMMC ($((EMMC_BYTES / 1024 / 1024)) MiB)"

# trava de segurança: a eMMC do NEO Air tem ~7,3 GiB; o SD do eflasher tem 64 GB
if (( EMMC_BYTES < 4 * 1024 * 1024 * 1024 || EMMC_BYTES > 32 * 1024 * 1024 * 1024 )); then
  die "tamanho inesperado para eMMC ($((EMMC_BYTES / 1024 / 1024)) MiB); abortando"
fi

# --- disponibilizar o payload (exFAT na p1 do SD) ---------------------------
SD_P1=/dev/${root_disk}p1
modprobe exfat 2>/dev/null || true
if ! mountpoint -q "$MNT"; then
  mount -t exfat "$SD_P1" "$MNT" || die "nao consegui montar $SD_P1 em $MNT"
fi
[[ -d $PAYLOAD_DIR ]] || die "payload ausente: $PAYLOAD_DIR"

# --- funcoes auxiliares ------------------------------------------------------
# le um campo u32 little-endian do cabecalho Android sparse
sparse_u32() { od -An -tu4 -j "$2" -N 4 "$1" | tr -d ' \n'; }

grava_sparse() {   # grava_sparse <arquivo.img> <offset_bytes> <rotulo>
  local img=$1 off=$2 rotulo=$3
  [[ -f $img ]] || die "imagem ausente: $img"

  local magic chunks blks
  magic=$(od -An -tx4 -j 0 -N 4 "$img" | tr -d ' \n')
  [[ $magic == ed26ff3a ]] || die "$img nao e Android sparse (magic=$magic)"

  # cabecalho: magic@0 file_hdr_sz@8 blk_sz@12 total_blks@16 total_chunks@20
  chunks=$(sparse_u32 "$img" 20)
  blks=$(sparse_u32 "$img" 16)
  [[ -n $chunks && -n $blks ]] || die "cabecalho sparse ilegivel em $img"
  log "$rotulo: $chunks chunks, $blks blocos, offset $off"

  bash "$UNSPARSE" "$img" "$EMMC" "$off" "$chunks" || die "$rotulo: decodificador falhou"
  log "$rotulo: gravado"
}

# --- gravar ------------------------------------------------------------------
# 1) U-Boot na area de usuario (NAO em mmcblk*boot0 — conferido na sessao 5)
log "gravando U-Boot em offset 0x2000"
dd if="$PAYLOAD_DIR/u-boot-sunxi-with-spl.bin" of="$EMMC" \
   bs=1024 seek=8 conv=notrunc status=none || die "falha ao gravar U-Boot"

# 2) p1 — boot FAT, offset 0x1800000 (24 MiB)
log "gravando boot (FAT) em offset 24 MiB"
dd if="$PAYLOAD_DIR/boot.img" of="$EMMC" \
   bs=1M seek=24 conv=notrunc status=none || die "falha ao gravar boot.img"

# 3) p2 — rootfs ext4, offset 0x4000000 (64 MiB)
grava_sparse "$PAYLOAD_DIR/rootfs.img" 67108864 rootfs

# 4) p3 — userdata ext4, offset 0x5C000000 (1472 MiB)
grava_sparse "$PAYLOAD_DIR/userdata.img" 1543503872 userdata

sync
log "sync concluido"

# --- verificar ---------------------------------------------------------------
if command -v e2fsck >/dev/null; then
  log "verificando p2 com e2fsck -fn (pode demorar)"
  if e2fsck -fn "${EMMC}p2" >/tmp/e2fsck-p2.txt 2>&1; then
    log "p2 OK: superbloco ext4 valido e sem erros"
    VERIFY=ok
  else
    log "p2 FALHOU na verificacao:"
    sed -n '1,20p' /tmp/e2fsck-p2.txt
    VERIFY=falhou
  fi
else
  log "e2fsck ausente; verificacao pulada"
  VERIFY=pulada
fi

umount "$MNT" 2>/dev/null || true

log "FLASH_DONE verify=$VERIFY"
log "desligando a placa: remova o cartao e ligue de novo para subir pela eMMC"

# --- desligar ----------------------------------------------------------------
sync
/usr/sbin/poweroff -f 2>/dev/null || poweroff -f 2>/dev/null || \
  { echo o > /proc/sysrq-trigger 2>/dev/null || true; }
