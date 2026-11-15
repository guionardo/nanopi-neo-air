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
#   sudo ./scripts/wifi-inject.sh /dev/sdX "SSID" "SENHA" [pasta-de-firmware] [MAC] [chave-ssh.pub]
#
# A pasta de firmware, se informada, deve conter brcmfmac43430-sdio.bin e
# brcmfmac43430-sdio.txt (ex.: extraídos de outra imagem FriendlyElec).
# As credenciais NÃO vão para o git: este script só as escreve no cartão.

set -uo pipefail

die() { printf 'erro: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
warn() { printf 'aviso: %s\n' "$*" >&2; }

[[ $EUID -eq 0 ]] || die "execute como root (sudo)."
[[ $# -ge 3 ]] || die "uso: $0 /dev/sdX \"SSID\" \"SENHA\" [pasta-de-firmware] [MAC]"

DEV=$1; SSID=$2; PSK=$3; FWDIR=${4:-}
WIFI_MAC=${5:-${WIFI_MAC:-}}
SSH_PUB=${6:-${SSH_PUB:-}}

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
  # Com FWDIR informado, ele é autoritativo: sobrescreve (com .bak). É assim que
  # se troca um NVRAM errado — o "já presente" do cartão pode ser justamente o
  # problema (ver firmware/README.md).
  if [[ -n $FWDIR && -f $FWDIR/$f ]]; then
    if [[ -f $FWDEST/$f ]] && cmp -s "$FWDIR/$f" "$FWDEST/$f"; then
      info "firmware idêntico ao do cartão: $f"
    else
      [[ -f $FWDEST/$f ]] && cp -a "$FWDEST/$f" "$FWDEST/$f.bak"
      install -m 0644 "$FWDIR/$f" "$FWDEST/$f"
      if [[ -f $FWDEST/$f.bak ]]; then
        info "firmware SUBSTITUÍDO (original em $f.bak): $f"
      else
        info "firmware copiado de $FWDIR: $f"
      fi
    fi

  elif [[ -f $FWDEST/$f ]]; then
    info "firmware já presente: $f"

  elif [[ -f $FWDEST/brcmfmac43430-sdio.bin.zst || -f $FWDEST/brcmfmac43430-sdio.bin.xz ]]; then
    info "firmware comprimido presente (o kernel descomprime sozinho)"

  else
    warn "firmware ausente: $f"
    need_fw=1
  fi
done

# o NVRAM precisa ser o do AP6212; avisa se for o genérico do linux-firmware
if [[ -f $FWDEST/brcmfmac43430-sdio.txt ]]; then
  if grep -q 'AP6212_NVRAM' "$FWDEST/brcmfmac43430-sdio.txt"; then
    info "NVRAM: AP6212 (correto para esta placa)"
  else
    warn "NVRAM NÃO é o do AP6212 — xtalfreq provavelmente errado, o rádio não varre"
    warn "Use: sudo $0 $DEV \"SSID\" \"SENHA\" ./firmware"
  fi
fi

# --- 1b. MAC fixo (opcional) ------------------------------------------------
# Sem isso o brcmfmac gera um MAC aleatório a cada boot (o macaddr do NVRAM é
# placeholder), e o lease no roteador muda de endereço. Com WIFI_MAC fixamos um
# MAC localmente administrado (primeiro octeto 02/06/0A/0E).
if [[ -n ${WIFI_MAC:-} ]]; then
  if [[ $WIFI_MAC =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
    FWTXT=$FWDEST/brcmfmac43430-sdio.txt
    [[ -f $FWTXT ]] || die "sem $FWTXT para fixar o MAC"
    sed -i -E "s/^macaddr=.*/macaddr=$WIFI_MAC/; s/^il0macaddr=.*/il0macaddr=$WIFI_MAC/" "$FWTXT"
    info "MAC fixado no NVRAM: $WIFI_MAC"
  else
    die "WIFI_MAC inválido: '$WIFI_MAC' (esperado aa:bb:cc:dd:ee:ff)"
  fi
fi

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

# Varredura normal em vez de sched scan: o brcmfmac desta placa responde
# "Failed to initiate sched scan" em loop e nunca devolve resultados.
disable_scan_offload=1
ap_scan=1

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

# --- 4b. chave SSH (opcional) -----------------------------------------------
# Sem isso o acesso é por senha (pi/fa do cartão). Com a chave, o instalador
# consegue entrar sem prompt e o dia a dia fica em login por chave.
if [[ -n ${SSH_PUB:-} ]]; then
  [[ -f $SSH_PUB ]] || die "chave SSH não encontrada: $SSH_PUB"
  key=$(cat "$SSH_PUB")
  [[ $key =~ ^(ssh-ed25519|ssh-rsa|ecdsa-) ]] || die "arquivo não parece uma chave pública: $SSH_PUB"
  for home in root home/pi; do
    [[ -d $R/$home ]] || continue
    install -d -m 700 "$R/$home/.ssh"
    touch "$R/$home/.ssh/authorized_keys"
    grep -qF "$key" "$R/$home/.ssh/authorized_keys" || printf '%s\n' "$key" >> "$R/$home/.ssh/authorized_keys"
    chmod 600 "$R/$home/.ssh/authorized_keys"
    info "chave SSH instalada em /$home/.ssh/authorized_keys"
  done
fi

# --- 5. resumo ---------------------------------------------------------------
printf '\n'
if (( need_fw )); then
  warn "SEM firmware do Wi-Fi: o wlan0 não vai subir."
  warn "Passe a pasta com brcmfmac43430-sdio.bin/.txt como 4º argumento."
else
  info "firmware ok — Wi-Fi deve subir"
fi

printf '\nCredenciais gravadas para SSID "%s".\n' "$SSID"
printf 'SSID diferencia maiúsculas de minúsculas — se o scan mostrar outra grafia\n'
printf '(ex.: minha-rede), o wpa_supplicant varre para sempre e nunca associa.\n'
printf 'No boot: wlan0 pega IP por DHCP e o sshd escuta na porta 22.\n'
printf 'Login: pi/fa (ou root/fa). Descubra o IP pelo seu roteador.\n'

sync
