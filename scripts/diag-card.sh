#!/usr/bin/env bash
#
# diag-card.sh — diagnóstico SOMENTE LEITURA do cartão do NanoPi.
#
# Usado quando o auto-flash não rodou: coleta o estado do serviço, o target
# padrão, o journal do último boot gravado no cartão e o boot.scr que o U-Boot
# realmente executa. Nada é escrito no cartão (montagens sempre com -o ro).
#
# Uso:
#   sudo ./scripts/diag-card.sh [device]

set -uo pipefail

die() { printf 'erro: %s\n' "$*" >&2; exit 1; }
sec() { printf '\n===== %s =====\n' "$*"; }
try() { "$@" 2>&1 || printf '  (falhou: %s)\n' "$*"; }

[[ $EUID -eq 0 ]] || die "execute como root (sudo)."

part_of() {
  local d=$1 n=$2
  case $d in
    *mmcblk*|*nvme*|*loop*) echo "${d}p${n}" ;;
    *)                      echo "${d}${n}" ;;
  esac
}

DEV=${1:-}
if [[ -z $DEV ]]; then
  ROOT_DISK=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null | head -n1 || true)
  while read -r name; do
    [[ -z $name || $name == "$ROOT_DISK" ]] && continue
    [[ -b $(part_of "/dev/$name" 3) ]] || continue
    DEV=/dev/$name
  done < <(lsblk -dno NAME,TYPE | awk '$2 == "disk" {print $1}')
fi
[[ -n ${DEV:-} && -b $DEV ]] || die "cartão não encontrado; informe: $0 /dev/sdX"

P1=$(part_of "$DEV" 1)
P2=$(part_of "$DEV" 2)
P3=$(part_of "$DEV" 3)

printf 'cartão: %s\n' "$DEV"
lsblk -o NAME,SIZE,TYPE,FSTYPE "$DEV"

R=$(mktemp -d); B=$(mktemp -d)
cleanup() { umount "$R" 2>/dev/null; umount "$B" 2>/dev/null; rmdir "$R" "$B" 2>/dev/null; }
trap cleanup EXIT

[[ -b $P3 ]] || die "sem p3 em $DEV"
mount -t ext4 -o ro "$P3" "$R" || die "falha ao montar $P3 (ro)"

# ---------------------------------------------------------------- serviço ----
sec "serviço instalado"
try ls -l "$R/opt/headless/"
try cat "$R/opt/headless/ARMED"
sec "unit file"
try cat "$R/etc/systemd/system/flash-emmc.service"
sec "estado do enable / masks"
try ls -l "$R/etc/systemd/system/multi-user.target.wants/"
try ls -l "$R/etc/systemd/system/eflasher-gui.service"
try ls -l "$R/etc/systemd/system/graphical.target.wants/" 
sec "default.target"
try ls -l "$R/etc/systemd/system/default.target"
try readlink -f "$R/etc/systemd/system/default.target"

sec "validação do unit pelo systemd (sem bootar)"
try systemctl --root="$R" list-unit-files --type=service --no-pager

# ------------------------------------------------------------------ journal ---
sec "journals gravados no cartão (persistentes?)"
try ls -ld "$R/var/log/journal"
try ls -1 "$R/var/log/journal" 

if [[ -d $R/var/log/journal ]] && command -v journalctl >/dev/null; then
  sec "journal — boots registrados"
  try journalctl --directory="$R/var/log/journal" --list-boots --no-pager
  sec "journal — último boot (200 linhas)"
  try journalctl --directory="$R/var/log/journal" -b -1 -n 200 --no-pager
  sec "journal — menções ao nosso serviço (todos os boots)"
  try journalctl --directory="$R/var/log/journal" --no-pager \
        | grep -iE 'flash-emmc|headless|unsparse|eflasher' | tail -n 60
fi

sec "logs tradicionais (mtime indica se o boot mexeu no rootfs)"
try ls -la "$R/var/log/" 
for f in syslog messages boot.log daemon.log; do
  [[ -f $R/var/log/$f ]] || continue
  printf '\n--- %s (tail) ---\n' "$f"
  try tail -n 25 "$R/var/log/$f"
done

sec "fstab do cartão"
try cat "$R/etc/fstab"

# ------------------------------------------------------------- boot.scr/etc ---
if [[ -b $P2 ]]; then
  if mount -t vfat -o ro "$P2" "$B" 2>/dev/null; then
    sec "partição de boot do cartão (p2) — conteúdo"
    try ls -l "$B"
    for f in boot.cmd boot.scr uEnv.txt; do
      [[ -f $B/$f ]] || continue
      printf '\n--- %s ---\n' "$f"
      if [[ $f == *.scr ]]; then
        try strings "$B/$f" | sed -n '1,60p'
      else
        try cat "$B/$f"
      fi
    done
    umount "$B"
  else
    printf '  (não consegui montar %s como vfat)\n' "$P2"
  fi
fi

sec "resumo"
printf 'ARMED presente: %s\n' "$([[ -e $R/opt/headless/ARMED ]] && echo sim || echo nao)"
printf 'log de flash  : %s\n' "$([[ -f $R/root/flash-emmc.log ]] && echo presente || echo ausente)"
