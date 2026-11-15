#!/usr/bin/env bash
#
# provision-emmc-wifi.sh — configura o Wi-Fi do sistema da **eMMC** a partir do
# sistema do cartão (que está no ar, com rede funcionando).
#
# Por que assim: a placa não tem serial confiável nem Ethernet. Uma vez com o
# cartão na rede, dá para montar o rootfs da eMMC pela rede (SSH), copiar o
# firmware que já provou funcionar e deixar a eMMC pronta para bootar sozinha.
#
# Roda NA PLACA, como root:
#   sudo ./provision-emmc-wifi.sh "minha-rede" "senha" [MAC]
#
# O sistema da eMMC usa NetworkManager (não ifupdown), então o perfil é um
# keyfile .nmconnection — nada de /etc/network/interfaces.

set -euo pipefail

SSID=${1:?uso: $0 "SSID" "SENHA" [MAC] [HOSTNAME]}
PSK=${2:?uso: $0 "SSID" "SENHA" [MAC] [HOSTNAME]}
MAC=${3:-}
NEW_HOST=${4:-}
E=/mnt/emmc

info() { printf '==> %s\n' "$*"; }
die() { printf 'erro: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "execute como root"

# --- localiza a raiz da eMMC (o disco que não é o atual) ---------------------
ROOTDEV=$(findmnt -n -o SOURCE /)
ROOTDISK=${ROOTDEV%p*}
EMMC=""
for d in /dev/mmcblk*p2; do
  [[ -b $d ]] || continue
  [[ ${d%p2} == "$ROOTDISK" ]] && continue
  EMMC=$d; break
done
[[ -n $EMMC ]] || die "não encontrei a rootfs da eMMC"
info "sistema atual: $ROOTDEV · rootfs da eMMC: $EMMC"

mountpoint -q "$E" || { mkdir -p "$E"; mount "$EMMC" "$E"; }
mount -o remount,rw "$E"
info "eMMC montada em $E"

# --- 1. firmware: o que funciona, como arquivo real (não symlink) ------------
# A eMMC traz symlinks para /lib/firmware/ap6212/, mas o NVRAM de lá é o
# genérico do AW-NB197SM (pa2ga0/papdmode errados para este AP6212).
FWSRC=/lib/firmware/brcm
FWDST=$E/lib/firmware/brcm
mkdir -p "$FWDST"

for f in brcmfmac43430-sdio.bin brcmfmac43430-sdio.txt; do
  [[ -f $FWSRC/$f ]] || die "sem $FWSRC/$f no cartão (rode wifi-inject.sh antes)"
  rm -f "$FWDST/$f"
  install -m 0644 "$FWSRC/$f" "$FWDST/$f"
  info "firmware instalado na eMMC: $f"
done

grep -q 'AP6212_NVRAM' "$FWDST/brcmfmac43430-sdio.txt" \
  || die "o NVRAM copiado não é o do AP6212 — abortando"
info "NVRAM confirmado: AP6212"

# --- 2. perfil do NetworkManager -------------------------------------------
uuid=$(python3 -c 'import uuid;print(uuid.uuid4())' 2>/dev/null || echo "3f1c9a54-0f0b-5e4e-9d33-9a5b0f7c1e21")
CONNDIR=$E/etc/NetworkManager/system-connections
mkdir -p "$CONNDIR"
CONN=$CONNDIR/"$SSID".nmconnection

umask 077
cat > "$CONN" <<EOF
[connection]
id=$SSID
uuid=$uuid
type=wifi
autoconnect=true
autoconnect-priority=10

[wifi]
ssid=$SSID
mode=infrastructure
# 2 = desligado. Precisa ficar em [wifi]: em [connection] o NM ignora e o
# rádio fica em power-save (latência de ~60 ms em vez de ~15 ms).
powersave=2
EOF

if [[ -n $MAC ]]; then
  cat >> "$CONN" <<EOF
cloned-mac-address=$MAC
EOF
fi

cat >> "$CONN" <<EOF

[wifi-security]
key-mgmt=wpa-psk
psk=$PSK

[ipv4]
method=auto

[ipv6]
method=auto
EOF
chmod 600 "$CONN"
info "perfil criado: $CONN"

# --- 3. senhas (opcional) ---------------------------------------------------
# Por padrão NÃO mexe em senha: copiar o hash do sistema do cartão sobrescreveria
# uma senha já trocada na eMMC. Use SYNC_PASS=1 só em instalação nova.
if [[ ${SYNC_PASS:-0} == 1 ]]; then
  for u in root pi; do
    h=$(grep "^$u:" /etc/shadow | cut -d: -f2 || true)
    if [[ -n ${h:-} && -f $E/etc/shadow ]] && grep -q "^$u:" "$E/etc/shadow"; then
      sed -i "s|^$u:[^:]*:|$u:$h:|" "$E/etc/shadow"
      info "senha de '$u' sincronizada do cartão"
    fi
  done
else
  info "senhas preservadas (use SYNC_PASS=1 para copiar do cartão)"
fi

# --- 4. ssh habilitado (a eMMC já traz; só garante) -------------------------
mkdir -p "$E/etc/systemd/system/multi-user.target.wants"
[[ -e $E/etc/systemd/system/multi-user.target.wants/ssh.service ]] \
  || ln -sf /lib/systemd/system/ssh.service \
        "$E/etc/systemd/system/multi-user.target.wants/ssh.service"
info "sshd habilitado no boot da eMMC"

# --- 4b. hostname (opcional) ------------------------------------------------
# Sem isso o primeiro boot roda o friendlyelec_firstuse.sh e o hostname vira o
# nome padrão da placa. Criar /etc/firstuse marca "já configurado" e evita que
# ele sobrescreva o nome escolhido.
if [[ -n ${NEW_HOST:-} ]]; then
  [[ $NEW_HOST =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] \
    || die "hostname inválido: '$NEW_HOST'"
  printf '%s\n' "$NEW_HOST" > "$E/etc/hostname"
  if grep -q '^127\.0\.1\.1' "$E/etc/hosts"; then
    sed -i "s|^127\.0\.1\.1.*|127.0.1.1\t$NEW_HOST|" "$E/etc/hosts"
  else
    printf '127.0.1.1\t%s\n' "$NEW_HOST" >> "$E/etc/hosts"
  fi
  printf '1\n' > "$E/etc/firstuse"
  info "hostname definido na eMMC: $NEW_HOST"
fi

# --- 5. relatório ----------------------------------------------------------
printf '\n'
info "Wi-Fi da eMMC configurado para \"$SSID\""
printf 'Obs.: /etc/firstuse ainda não existe — no primeiro boot o\n'
printf 'friendlyelec_firstuse.sh vai acertar o hostname para o nome da placa.\n'
printf 'Ajuste o hostname depois, com a eMMC já no ar.\n'

sync
umount "$E"
info "pronto — pode desligar, tirar o cartão e ligar"
