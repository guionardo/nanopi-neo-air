#!/usr/bin/env bash
#
# wifi-inject.sh — injeta credenciais de Wi-Fi (e firmware, se faltar) no
# rootfs do cartão eflasher, para a placa subir com SSH pela rede.
#
# Por que assim: a NEO Air não tem Ethernet e não expõe gadget USB utilizável.
# O cartão já boota (LED verde piscando) e tem sshd habilitado com pi/fa.
# Configurando o Wi-Fi no rootfs do cartão, você ganha SSH sem serial.
#
# Uso:
#   sudo ./scripts/wifi-inject.sh /dev/sdX "SSID" "SENHA" [pasta-de-firmware]
#
# A pasta de firmware, se informada, deve conter brcmfmac43430-sdio.bin e
# brcmfmac43430-sdio.txt (ex.: extraídos de outra imagem FriendlyElec).
# As credenciais NÃO vão para o git: este script só as escreve no cartão.

set -uo pipefail

die() { printf 'erro: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
warn() { printf 'aviso: %s\n' "$*" >&2; }

[[ $EUID -eq 0 ]] || die "execute como root (sudo)."
[[ $# -ge 3 ]] || die "uso: $0 /dev/sdX \"SSID\" \"SENHA\" [pasta-de-firmware]"

DEV=$1; SSID=$2; PSK=$3; FWDIR=${4:-}

part_of() {
  local d=$1 n=$2
  case $d in *mmcblk*|*nvme*) echo "${d}p${n}" ;; *) echo "${d}${n}" ;; esac
}

P3=$(part_of "$DEV" 3)
[[ -b $P3 ]] || die "partição rootfs não encontrada: $P3"
[[ ${#PSK} -ge 8 ]] || die "senha Wi-Fi com menos de 8 caracteres (WPA2 exige 8+)"

R=$(mktemp -d)
cleanup() { umount "$R" 2>/dev/null; rmdir "$R" 2>/dev/null; }
trap cleanup EXIT

while read -r mp; do
  [[ -n $mp ]] && { info "desmontando $mp"; umount "$mp"; }
done < <(findmnt -rno TARGET --source "$P3" 2>/dev/null || true)

info "montando $P3"
mount -t ext4 "$P3" "$R" || die "falha ao montar $P3"

# --- 1. firmware do brcmfmac ------------------------------------------------
FWDEST=$R/lib/firmware/brcm
mkdir -p "$FWDEST"

need_fw=0
for f in brcmfmac43430-sdio.bin brcmfmac43430-sdio.txt; do
  if [[ -f $FWDEST/$f ]]; then
    info "firmware já presente: $f"

  elif [[ -n $FWDIR && -f $FWDIR/$f ]]; then
    install -m 0644 "$FWDIR/$f" "$FWDEST/$f"
    info "firmware copiado de $FWDIR: $f"

  elif [[ -f $FWDEST/brcmfmac43430-sdio.bin.zst || -f $FWDEST/brcmfmac43430-sdio.bin.xz ]]; then
    info "firmware comprimido presente (o kernel descomprime sozinho)"

  else
    warn "firmware ausente: $f"
    need_fw=1
  fi
done

# variações que alguns kernels procuram
for f in brcmfmac43430-sdio.clm_blob brcmfmac43430-sdio.AP6212.txt; do
  [[ -n $FWDIR && -f $FWDIR/$f && ! -f $FWDEST/$f ]] && \
    install -m 0644 "$FWDIR/$f" "$FWDEST/$f"
done

# --- 2. credenciais do wpa_supplicant ---------------------------------------
CONF=$R/etc/wpa_supplicant/wpa_supplicant.conf
mkdir -p "$R/etc/wpa_supplicant"
[[ -f $CONF ]] && cp -a "$CONF" "$CONF.bak"

umask 077
cat > "$CONF" <<EOF
# gerado por scripts/wifi-inject.sh
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=BR

network={
    ssid="$SSID"
    psk="$PSK"
    key_mgmt=WPA-PSK
    priority=10
}
EOF
chmod 600 "$CONF"
info "wpa_supplicant.conf escrito (permissão 600)"

# --- 3. ifupdown: wlan0 por DHCP --------------------------------------------
IFACES=$R/etc/network/interfaces
[[ -f $IFACES ]] || die "sem /etc/network/interfaces"
cp -a "$IFACES" "$IFACES.bak"

if grep -qE '^\s*iface\s+wlan0' "$IFACES"; then
  info "já existe bloco wlan0; preservando o original em .bak"
else
  cat >> "$IFACES" <<'EOF'

# --- wlan0 gerenciado por wpa_supplicant (scripts/wifi-inject.sh) ---
allow-hotplug wlan0
iface wlan0 inet dhcp
    pre-up rfkill unblock wifi || true
    wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
EOF
  info "bloco wlan0 adicionado em /etc/network/interfaces"
fi

# o wpa_supplicant.service do systemd brigaria com o do ifupdown pelo wlan0
if [[ -L $R/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service ]] || \
   [[ -L $R/etc/systemd/system/wpa_supplicant.service ]]; then
  rm -f "$R/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service"
  ln -sf /dev/null "$R/etc/systemd/system/wpa_supplicant.service"
  info "wpa_supplicant.service mascarado (who controla o wlan0 é o ifupdown)"
fi

# --- 4. SSH e utilitários ----------------------------------------------------
for c in dhclient udhcpc dhcpcd; do
  [[ -x $R/sbin/$c || -x $R/usr/sbin/$c ]] && info "cliente DHCP: $c"
done
[[ -e $R/etc/systemd/system/multi-user.target.wants/ssh.service ]] \
  && info "ssh.service habilitado" || warn "ssh.service não habilitado"
grep -E '^\s*PasswordAuthentication' "$R/etc/ssh/sshd_config" 2>/dev/null | head -n1

# --- 5. resumo ---------------------------------------------------------------
printf '\n'
if (( need_fw )); then
  warn "SEM firmware do Wi-Fi: o wlan0 não vai subir."
  warn "Passe a pasta com brcmfmac43430-sdio.bin/.txt como 4º argumento."
else
  info "firmware ok — Wi-Fi deve subir"
fi

printf '\nCredenciais gravadas para SSID "%s".\n' "$SSID"
printf 'No boot: wlan0 pega IP por DHCP e o sshd escuta na porta 22.\n'
printf 'Login: pi/fa (ou root/fa). Descubra o IP pelo seu roteador.\n'

sync
