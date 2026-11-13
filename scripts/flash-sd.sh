#!/usr/bin/env bash
#
# flash-sd.sh — grava uma imagem (.img ou .img.gz) em um cartão microSD.
#
# Uso:
#   sudo ./scripts/flash-sd.sh <imagem.img|imagem.img.gz> <device>
#
# Exemplo:
#   sudo ./scripts/flash-sd.sh ~/nanopi/images/h3-sd-friendlycore-jammy-4.14-armhf-20240101.img.gz /dev/sdb
#
# O script se recusa a escrever em discos que contenham o sistema em execução
# e exige confirmação explícita antes de destruir os dados do destino.
#
set -euo pipefail

die() { printf 'erro: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

usage() {
  cat <<'EOF'
Uso: sudo flash-sd.sh <imagem.img|imagem.img.gz> <device>

  imagem   arquivo .img ou .img.gz da distribuição
  device   dispositivo de bloco inteiro (ex: /dev/sdb), NÃO uma partição

Exemplo:
  sudo ./flash-sd.sh ~/images/h3-sd-friendlycore-jammy.img.gz /dev/sdb
EOF
}

[[ $# -eq 2 ]] || { usage; exit 1; }
[[ $EUID -eq 0 ]] || die "execute como root (sudo)."

IMG=$1
DEV=$2

# --- validação da imagem -----------------------------------------------------
[[ -f $IMG ]] || die "imagem não encontrada: $IMG"

case $IMG in
  *.img.gz)
    command -v gzip >/dev/null || die "gzip não instalado."
    info "verificando integridade do gzip (pode demorar)..."
    gzip -t "$IMG" || die "arquivo gzip corrompido: $IMG"
    ;;
  *.img) ;;
  *) die "extensão não suportada (use .img ou .img.gz): $IMG" ;;
esac

IMG_BYTES=$(case $IMG in
  *.gz) gzip -l "$IMG" | awk 'NR==2 {print $2}' ;;
  *)    stat -c %s "$IMG" ;;
esac)
[[ ${IMG_BYTES:-0} -gt 104857600 ]] || die "imagem suspeita (${IMG_BYTES:-0} bytes). É a imagem certa?"

# --- validação do destino ----------------------------------------------------
[[ -b $DEV ]] || die "não é um dispositivo de bloco: $DEV"

[[ $DEV =~ ^/dev/(sd[a-z]+|mmcblk[0-9]+|nvme[0-9]+n[0-9]+|vd[a-z]+)$ ]] \
  || die "informe o disco inteiro, sem número de partição: ex /dev/sdb (não /dev/sdb1)"

DEV_NAME=$(basename "$DEV")
DEV_SIZE=$(lsblk -bdno SIZE "$DEV")
DEV_MODEL=$(lsblk -dno MODEL "$DEV" 2>/dev/null | xargs || true)

[[ $DEV_SIZE -ge $IMG_BYTES ]] \
  || die "destino menor que a imagem ($DEV_SIZE < $IMG_BYTES bytes)."

# recusa o disco que hospeda o sistema em execução
ROOT_SRC=$(findmnt -no SOURCE / || true)
if [[ -n $ROOT_SRC ]]; then
  ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -n1 || true)
  [[ -n $ROOT_DISK ]] && [[ $ROOT_DISK == "$DEV_NAME" ]] \
    && die "recusando gravar em $DEV: é o disco do sistema em execução."
fi

for mnt in / /boot /boot/efi /home; do
  src=$(findmnt -no SOURCE "$mnt" 2>/dev/null || true)
  [[ -z $src ]] && continue
  disk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)
  [[ $disk == "$DEV_NAME" ]] && die "recusando gravar em $DEV: contém $mnt montado."
done

# --- confirmação -------------------------------------------------------------
printf '\n'
info "imagem : $IMG"
info "tamanho: $IMG_BYTES bytes ($((IMG_BYTES / 1024 / 1024)) MiB)"
info "destino: $DEV  [$DEV_NAME]  ${DEV_MODEL:-desconhecido}  $((DEV_SIZE / 1024 / 1024)) MiB"
printf '\n'
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL "$DEV" || true
printf '\n'
printf 'TODOS os dados em %s serão apagados.\n' "$DEV"
read -r -p "Digite o nome do dispositivo (${DEV_NAME}) para confirmar: " CONFIRM
[[ $CONFIRM == "$DEV_NAME" ]] || die "confirmação incorreta; abortando."

# --- desmontar ---------------------------------------------------------------
info "desmontando partições de $DEV..."
while read -r part; do
  [[ -z $part ]] && continue
  umount "$part" 2>/dev/null || true
done < <(lsblk -lno NAME,MOUNTPOINT "$DEV" | awk '$2 != "" {print "/dev/" $1}')

swapoff "$DEV" 2>/dev/null || true

# --- gravar ------------------------------------------------------------------
info "gravando (não remova o cartão)..."
if [[ $IMG == *.gz ]]; then
  gunzip -c "$IMG" | dd of="$DEV" bs=4M conv=fsync status=progress
else
  dd if="$IMG" of="$DEV" bs=4M conv=fsync status=progress
fi

sync
partprobe "$DEV" 2>/dev/null || true

info "concluído."
printf '\n'
lsblk -o NAME,SIZE,TYPE,FSTYPE "$DEV" || true
printf '\nVerifique as partições e remova o cartão com segurança antes de usar.\n'
