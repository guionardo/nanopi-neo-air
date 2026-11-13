#!/usr/bin/env bash
#
# show-flash-log.sh — lê o resultado do auto-flash headless direto do cartão.
#
# Depois que o NanoPi grava a eMMC, o veredito fica em /root/flash-emmc.log
# dentro do cartão. Este script monta a p3 do cartão (somente leitura),
# mostra o log e sinaliza o estado:
#
#   FLASH_DONE verify=ok      → eMMC gravada e validada; pode subir sem cartão
#   FLASH_DONE verify=falhou  → gravou, mas o ext4 não validou (investigar)
#   FLASH_DONE verify=pulada  → gravou; e2fsck ausente no cartão
#   FLASH_FAILED              → parou antes de terminar
#   (vazio/ausente)           → o serviço não chegou a rodar
#
# Uso:
#   sudo ./scripts/show-flash-log.sh [device]
#
#   device   disco inteiro do cartão (ex: /dev/sdc). Se omitido, tenta detectar.

set -euo pipefail

die() { printf 'erro: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

[[ $EUID -eq 0 ]] || die "execute como root (sudo)."

ROOT_SRC=$(findmnt -no SOURCE / || true)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -n1 || true)

part_of() {   # part_of <disco> <n> → caminho da partição (mmcblk usa 'p')
  local d=$1 n=$2
  case $d in
    *mmcblk*|*nvme*|*loop*) echo "${d}p${n}" ;;
    *)                      echo "${d}${n}" ;;
  esac
}

DEV=${1:-}
if [[ -z $DEV ]]; then
  candidates=()
  while read -r name; do
    [[ -z $name ]] && continue
    [[ $name == "$ROOT_DISK" ]] && continue
    p3=$(part_of "/dev/$name" 3)
    [[ -b $p3 ]] || continue
    candidates+=("/dev/$name")
  done < <(lsblk -dno NAME,TYPE | awk '$2 == "disk" {print $1}' | grep -E '^(sd[a-z]+|mmcblk[0-9]+|vd[a-z]+)$')

  case ${#candidates[@]} in
    0) die "nenhum cartão com 3ª partição encontrado. Informe o device: $0 /dev/sdX" ;;
    1) DEV=${candidates[0]} ;;
    *) printf 'Candidatos encontrados:\n' >&2
       printf '  %s\n' "${candidates[@]}" >&2
       die "mais de um candidato; informe qual: $0 /dev/sdX" ;;
  esac
fi

P3=$(part_of "$DEV" 3)
[[ -b $P3 ]] || die "partição rootfs não encontrada em $DEV"

info "lendo $P3"
MNT=$(mktemp -d)
trap 'umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true' EXIT

mount -t ext4 -o ro "$P3" "$MNT" || die "falha ao montar $P3 (ro)"

LOG=$MNT/root/flash-emmc.log
ARMED=$MNT/opt/headless/ARMED

printf '\n'
if [[ ! -f $LOG ]]; then
  info "log ausente — o serviço provavelmente não rodou"
  [[ -e $ARMED ]] && printf '     a flag ARMED ainda existe: nada gravado.\n'
  exit 1
fi

info "conteúdo de /root/flash-emmc.log:"
printf -- '----------------------------------------\n'
cat "$LOG"
printf -- '----------------------------------------\n\n'

# --- veredito ----------------------------------------------------------------
state=$(grep -E '^\[[0-9:]+\] (FLASH_DONE|FLASH_FAILED)' "$LOG" | tail -n1 || true)
verify=$(sed -n 's/.*verify=\([a-z]*\).*/\1/p' <<<"$state" | tail -n1)

printf 'ESTADO: '
case $state in
  *FLASH_DONE*ok*)      printf 'SUCESSO — eMMC gravada e validada pelo e2fsck.\n' ;;
  *FLASH_DONE*falhou*)  printf 'ATENCAO — gravou, mas a p2 nao validou. Guarde o log.\n' ;;
  *FLASH_DONE*pulada*)  printf 'OK com ressalva — gravou, mas sem e2fsck para validar.\n' ;;
  *FLASH_DONE*)         printf 'gravou (verify=%s).\n' "${verify:-?}" ;;
  *FLASH_FAILED*)       printf 'FALHOU — a gravacao nao terminou.\n' ;;
  *)                    printf 'INCONCLUSIVO — log sem marcador final.\n' ;;
esac

[[ -e $ARMED ]] && printf 'ARMED ainda presente: o serviço não consumiu a flag (não rodou).\n' || true

printf '\n'
lsblk -o NAME,SIZE,TYPE,FSTYPE "$DEV" || true
