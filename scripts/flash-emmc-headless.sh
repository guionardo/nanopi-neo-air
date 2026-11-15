#!/bin/bash
#
# flash-emmc-headless.sh — grava a eMMC a partir do payload do eflasher,
# sem GUI e sem console serial.
#
# Roda DENTRO do rootfs do próprio eflasher (Ubuntu ou Debian), como serviço
# systemd oneshot no primeiro boot. Faz o que o /opt/eflasher-gui faria, mas
# lendo o payload Android sparse com scripts/unsparse.sh.
#
# Instalação: scripts/install-headless-flash.sh (executado no PC, com sudo).
# Chamado por: /etc/systemd/system/flash-emmc.service
#
# Sem argumentos. Ao final: desarma-se e desliga a placa.

set -uo pipefail

# O payload e os offsets vem do cartao eflasher (eflasher.conf + partmap.txt),
# entao o script serve para qualquer imagem eflasher (bookworm, trixie, ...).
# Os valores abaixo sao apenas fallback do layout H3 conhecido.
PAYLOAD_DIR=${PAYLOAD_DIR:-}
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

# --- descobrir o payload (autoStart do eflasher.conf) -----------------------
if [[ -z ${PAYLOAD_DIR:-} ]]; then
  for conf in "$MNT/eflasher.conf" "$MNT"/*/eflasher.conf; do
    [[ -f $conf ]] || continue
    name=$(sed -n 's/^[[:space:]]*autoStart[[:space:]]*=[[:space:]]*//p' "$conf" \
           | head -n1 | tr -d '\r')
    [[ -n $name && -d "$MNT/$name" ]] && { PAYLOAD_DIR=$MNT/$name; break; }
  done
fi
if [[ -z ${PAYLOAD_DIR:-} ]]; then
  # sem autoStart valido: aceita o unico diretorio com rootfs.img
  for d in "$MNT"/*/; do
    [[ -f $d/rootfs.img ]] && { PAYLOAD_DIR=${d%/}; break; }
  done
fi
[[ -n ${PAYLOAD_DIR:-} && -d $PAYLOAD_DIR ]] \
  || die "payload nao encontrado em $MNT (eflasher.conf sem autoStart valido?)"
log "payload: $PAYLOAD_DIR"

# --- offsets do partmap.txt (fallback: layout H3 fixo) ----------------------
UBOOT_OFF=0x2000
OFF_BOOT=0x1800000
LEN_BOOT=0x2800000
OFF_ROOTFS=0x4000000
LEN_ROOTFS=0x58000000
OFF_USERDATA=0x5C000000
IMG_UBOOT=u-boot-sunxi-with-spl.bin
IMG_BOOT=boot.img
IMG_ROOTFS=rootfs.img
IMG_USERDATA=userdata.img

if [[ -f $PAYLOAD_DIR/partmap.txt ]]; then
  while IFS= read -r line; do
    [[ $line == flash=* ]] || continue
    part=$(printf '%s' "$line" | cut -d: -f2)
    off=$(printf '%s'  "$line" | cut -d: -f4 | cut -d, -f1)
    len=$(printf '%s'  "$line" | cut -d: -f4 | cut -d, -f2)
    img=$(printf '%s'  "$line" | cut -d: -f5 | tr -d ';\r')
    [[ -n $off && -n $img ]] || continue
    case $part in
      boot0)    UBOOT_OFF=$off;    IMG_UBOOT=$img ;;
      boot)     OFF_BOOT=$off;     LEN_BOOT=$len;    IMG_BOOT=$img ;;
      rootfs)   OFF_ROOTFS=$off;   LEN_ROOTFS=$len;  IMG_ROOTFS=$img ;;
      userdata) OFF_USERDATA=$off; IMG_USERDATA=$img ;;
    esac
  done < "$PAYLOAD_DIR/partmap.txt"
fi
log "layout: boot=0x$(printf '%x' "$OFF_BOOT") rootfs=0x$(printf '%x' "$OFF_ROOTFS") userdata=0x$(printf '%x' "$OFF_USERDATA")"

# --- tabela de particoes (MBR) ----------------------------------------------
# O eflasher cria a tabela antes de gravar; sem isso uma eMMC virgem (ou com
# tabela de outra placa) ficaria sem p1/p2/p3. So reescreve se estiver diferente.
SEC=512
P1_START=$((OFF_BOOT / SEC));    P1_SIZE=$((LEN_BOOT / SEC))
P2_START=$((OFF_ROOTFS / SEC))
P3_START=$((OFF_USERDATA / SEC))
if (( ${LEN_ROOTFS:-0} > 0 )); then
  P2_SIZE=$((LEN_ROOTFS / SEC))
else
  P2_SIZE=$((P3_START - P2_START))
fi
P3_SIZE=$(( (EMMC_BYTES - OFF_USERDATA) / SEC ))

need_table=0
cur_p1=$(cat "/sys/block/$emmc/${emmc}p1/start" 2>/dev/null || true)
cur_p2=$(cat "/sys/block/$emmc/${emmc}p2/start" 2>/dev/null || true)
cur_p3=$(cat "/sys/block/$emmc/${emmc}p3/start" 2>/dev/null || true)
[[ $cur_p1 == "$P1_START" && $cur_p2 == "$P2_START" && $cur_p3 == "$P3_START" ]]   || need_table=1

if (( need_table )); then
  log "criando tabela de particoes: p1=$P1_START+$P1_SIZE p2=$P2_START+$P2_SIZE p3=$P3_START+$P3_SIZE"
  if command -v parted >/dev/null; then
    parted -s "$EMMC" mklabel msdos \
      mkpart primary "${P1_START}s" "$((P1_START + P1_SIZE - 1))s" \
      mkpart primary "${P2_START}s" "$((P2_START + P2_SIZE - 1))s" \
      mkpart primary "${P3_START}s" "$((P3_START + P3_SIZE - 1))s" \
      >/dev/null || die "falha ao criar a tabela de particoes (parted)"
  elif command -v sfdisk >/dev/null; then
    sfdisk --no-reread --wipe always "$EMMC" >/dev/null <<EOF || die "falha ao criar a tabela de particoes (sfdisk)"
label: dos
unit: sectors
sector-size: 512

start=$P1_START, size=$P1_SIZE, type=83
start=$P2_START, size=$P2_SIZE, type=83
start=$P3_START, size=$P3_SIZE, type=83
EOF
  else
    die "sem parted/sfdisk: nao consigo criar a tabela de particoes"
  fi
  partprobe "$EMMC" 2>/dev/null || true
  partx -u "$EMMC" 2>/dev/null || true
  udevadm settle 2>/dev/null || sleep 1
else
  log "tabela de particoes ja compativel (p1/p2/p3)"
fi

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
(( UBOOT_OFF % 1024 == 0 )) || die "offset do U-Boot nao alinhado a 1 KiB: $UBOOT_OFF"
log "gravando U-Boot ($IMG_UBOOT) em offset $UBOOT_OFF"
dd if="$PAYLOAD_DIR/$IMG_UBOOT" of="$EMMC" \
   bs=1024 seek=$((UBOOT_OFF / 1024)) conv=notrunc status=none || die "falha ao gravar U-Boot"

# 2) p1 — boot FAT
(( OFF_BOOT % 1048576 == 0 )) || die "offset do boot nao alinhado a 1 MiB: $OFF_BOOT"
log "gravando boot ($IMG_BOOT) em offset $((OFF_BOOT / 1048576)) MiB"
dd if="$PAYLOAD_DIR/$IMG_BOOT" of="$EMMC" \
   bs=1M seek=$((OFF_BOOT / 1048576)) conv=notrunc status=none || die "falha ao gravar o boot"

# 3) p2 — rootfs ext4
log "gravando rootfs ($IMG_ROOTFS) em offset $OFF_ROOTFS"
grava_sparse "$PAYLOAD_DIR/$IMG_ROOTFS" "$OFF_ROOTFS" rootfs

# 4) p3 — userdata ext4
log "gravando userdata ($IMG_USERDATA) em offset $OFF_USERDATA"
grava_sparse "$PAYLOAD_DIR/$IMG_USERDATA" "$OFF_USERDATA" userdata

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
