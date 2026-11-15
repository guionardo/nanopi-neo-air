#!/usr/bin/env bash
#
# install.sh — instalação de ponta a ponta do NanoPi NEO Air como host headless.
#
# Um computador Linux com leitor de cartão SD é tudo que você precisa: o script
# confere as ferramentas, baixa/verifica a imagem, grava o cartão, injeta Wi-Fi +
# firmware + chave SSH, arma a gravação da eMMC e depois conversa com a placa
# pela rede — sem monitor, sem teclado e sem adaptador serial.
#
# Uso:
#   ./install.sh check            # ambiente, dependências e dispositivo
#   ./install.sh card             # grava e prepara o cartão SD
#   ./install.sh net              # espera a placa, grava a eMMC e provisiona
#   ./install.sh verify           # confere o sistema que subiu da eMMC
#   ./install.sh all              # card + net (com pausas para trocar o cartão)
#
# Configuração: install.conf (criado na primeira execução, permissão 600) ou
# variáveis de ambiente com os mesmos nomes.
#
# Requisitos no computador: Linux, bash, curl (ou wget) e leitor de cartão.
# Se faltar algo do pacote base, use --install-deps (apt/dnf/pacman).
#
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONF=${CONF:-$HERE/install.conf}
CACHE=${CACHE:-$HERE/.cache}
SKIP_DEPS=0
ASSUME_YES=0
DRY_RUN=0

# --- cores -------------------------------------------------------------------
if [[ -t 1 ]]; then
  B=$'\e[1m'; R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; N=$'\e[0m'
else
  B=''; R=''; G=''; Y=''; C=''; N=''
fi

info()  { printf '%s==>%s %s\n' "$G" "$N" "$*"; }
step()  { printf '\n%s%s%s\n' "$B" "$*" "$N"; }
warn()  { printf '%saviso:%s %s\n' "$Y" "$N" "$*" >&2; }
die()   { printf '%serro:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
install.sh — NanoPi NEO Air: instalação sem monitor, sem serial e sem GUI

  ./install.sh check      verifica ambiente, dependências e cartão
  ./install.sh card       baixa a imagem, grava o cartão e injeta a configuração
  ./install.sh net        encontra a placa, espera a eMMC e provisiona o sistema
  ./install.sh verify     confere o sistema que subiu da eMMC (Wi-Fi, SSH, falhas)
  ./install.sh all        card + net

Opções:
  --config ARQUIVO   usa outro install.conf (padrão: ./install.conf)
  --yes              não pede confirmação (use com cuidado)
  --skip-deps        não tenta instalar dependências
  --dry-run          mostra o que faria, sem escrever no cartão
  -h, --help         esta ajuda

Variáveis (install.conf ou ambiente):
  SSID            nome da rede Wi-Fi (diferencia maiúsculas de minúsculas)
  PSK             senha da rede (WPA2, 8+ caracteres)
  HOSTNAME_NEW    hostname da placa (padrão: nanopi)
  IMAGE           caminho local ou URL da imagem do cartão (.img/.img.gz)
  IMAGE_SHA256    checksum esperado da imagem (recomendado)
  SD_DEV          dispositivo do cartão (ex.: /dev/sdb)
  WIFI_MAC        MAC fixo opcional (02:xx…), para o roteador não trocar o lease
  SSH_KEY         chave privada usada no acesso (padrão: ~/.ssh/id_ed25519)
  BOARD_IP        IP da placa (pula a descoberta automática)

A imagem é a do eflasher da FriendlyElec (a que contém o payload da eMMC).
Baixe em https://wiki.friendlyelec.com/wiki/index.php/NanoPi_NEO_Air e passe o
arquivo em IMAGE. O script não distribui a imagem por questões de licença.
EOF
}

# --- argumentos --------------------------------------------------------------
CMD=${1:-help}
shift || true
while (($#)); do
  case $1 in
    --config) CONF=$2; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --skip-deps) SKIP_DEPS=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help|help) CMD=help; shift ;;
    *) die "opção desconhecida: $1 (use --help)" ;;
  esac
done

[[ $CMD == help ]] && { usage; exit 0; }

# --- root (com re-execução via sudo) -----------------------------------------
need_root() {
  [[ $EUID -eq 0 ]] && return 0
  command -v sudo >/dev/null || die "precisa de root; instale sudo ou rode como root"
  info "elevando com sudo (mantendo a configuração)"
  # -E preserva as variáveis já exportadas; o arquivo install.conf é lido de novo
  exec sudo -E -- bash "$0" "$CMD" --config "$CONF" \
    $( ((ASSUME_YES)) && echo --yes ) $( ((SKIP_DEPS)) && echo --skip-deps ) \
    $( ((DRY_RUN)) && echo --dry-run )
}

# --- dependências ------------------------------------------------------------
REQUIRED=(dd mount umount findmnt lsblk sha256sum awk sed grep ssh ssh-keygen ip)
OPTIONAL=(curl wget gzip zstd)
missing=()
for c in "${REQUIRED[@]}"; do command -v "$c" >/dev/null || missing+=("$c"); done
have_downloader() { command -v curl >/dev/null || command -v wget >/dev/null; }

install_deps() {
  local pkgs="coreutils util-linux mount ssh-client openssh-client gzip"
  [[ -f /etc/debian_version ]] && { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pkgs curl; return; }
  [[ -f /etc/fedora-release || -f /etc/redhat-release ]] && { dnf install -y coreutils util-linux openssh-clients gzip curl; return; }
  [[ -f /etc/arch-release ]] && { pacman -Sy --noconfirm coreutils util-linux openssh gzip curl; return; }
  return 1
}

check_deps() {
  if ((${#missing[@]})); then
    warn "faltando: ${missing[*]}"
    if ((SKIP_DEPS)); then
      die "instale manualmente: ${missing[*]}"
    fi
    info "tentando instalar as dependências do sistema"
    install_deps || die "instale manualmente: ${missing[*]}"
    missing=()
    for c in "${REQUIRED[@]}"; do command -v "$c" >/dev/null || missing+=("$c"); done
    ((${#missing[@]}==0)) || die "ainda faltando: ${missing[*]}"
  fi
  have_downloader || die "instale curl ou wget"
  info "dependências ok"
}

# --- configuração ------------------------------------------------------------
SSID=${SSID:-}; PSK=${PSK:-}; HOSTNAME_NEW=${HOSTNAME_NEW:-nanopi}
IMAGE=${IMAGE:-}; IMAGE_SHA256=${IMAGE_SHA256:-}
SD_DEV=${SD_DEV:-}; WIFI_MAC=${WIFI_MAC:-}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/id_ed25519}
BOARD_IP=${BOARD_IP:-}

load_conf() {
  [[ -f $CONF ]] || return 0
  perms=$(stat -c %a "$CONF")
  [[ $perms == 600 || $perms == 400 ]] || warn "permissões de $CONF são $perms (ideal 600: contém a senha do Wi-Fi)"
  # shellcheck disable=SC1090
  set -a; . "$CONF"; set +a
  SSID=${SSID:-}; PSK=${PSK:-}; HOSTNAME_NEW=${HOSTNAME_NEW:-nanopi}
  IMAGE=${IMAGE:-}; IMAGE_SHA256=${IMAGE_SHA256:-}
  SD_DEV=${SD_DEV:-}; WIFI_MAC=${WIFI_MAC:-}
  SSH_KEY=${SSH_KEY:-$HOME/.ssh/id_ed25519}; BOARD_IP=${BOARD_IP:-}
}

save_conf() {
  umask 077
  {
    printf '# install.sh — configuração da instalação (NÃO versionar)\n'
    printf 'SSID=%q\n' "$SSID"
    printf 'PSK=%q\n' "$PSK"
    printf 'HOSTNAME_NEW=%q\n' "$HOSTNAME_NEW"
    printf 'IMAGE=%q\n' "$IMAGE"
    printf 'IMAGE_SHA256=%q\n' "${IMAGE_SHA256:-}"
    printf 'SD_DEV=%q\n' "${SD_DEV:-}"
    printf 'WIFI_MAC=%q\n' "${WIFI_MAC:-}"
    printf 'SSH_KEY=%q\n' "$SSH_KEY"
    printf 'BOARD_IP=%q\n' "${BOARD_IP:-}"
  } > "$CONF"
  chmod 600 "$CONF"
  info "configuração salva em $CONF (600)"
}

ask() { # ask VAR "pergunta" [padrão]
  local var=$1 prompt=$2 def=${3:-} val
  if [[ -n ${!var:-} ]]; then return 0; fi
  if [[ $def != "" ]]; then read -r -p "$prompt [$def]: " val || true
  else read -r -p "$prompt: " val || true; fi
  printf -v "$var" '%s' "${val:-$def}"
}

ask_secret() {
  [[ -n ${PSK:-} ]] && return 0
  local v1 v2
  read -r -s -p "Senha do Wi-Fi (WPA2): " v1; printf '\n'
  read -r -s -p "Repita a senha: " v2; printf '\n'
  [[ $v1 == "$v2" ]] || die "as senhas não conferem"
  ((${#v1} >= 8)) || die "senha com menos de 8 caracteres (WPA2 exige 8+)"
  PSK=$v1
}

ensure_config() {
  local changed=0
  if [[ -z $SSID ]]; then ask SSID "SSID da rede Wi-Fi (maiúsculas importam)" || true; changed=1; fi
  [[ -n $SSID ]] || die "SSID é obrigatório"
  [[ -n $PSK ]] || { ask_secret; changed=1; }
  if [[ -z $HOSTNAME_NEW ]]; then HOSTNAME_NEW=nanopi; changed=1; fi
  [[ $HOSTNAME_NEW =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] \
    || die "hostname inválido: '$HOSTNAME_NEW'"
  if [[ -n $WIFI_MAC && ! $WIFI_MAC =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
    die "WIFI_MAC inválido: '$WIFI_MAC'"
  fi
  ((changed)) && save_conf || true
}

ensure_key() {
  if [[ ! -f $SSH_KEY ]]; then
    info "gerando chave SSH em $SSH_KEY (ed25519, sem passphrase)"
    mkdir -p "$(dirname "$SSH_KEY")"
    ssh-keygen -t ed25519 -N '' -f "$SSH_KEY" -C "nanopi-install" >/dev/null
  fi
  [[ -f $SSH_KEY.pub ]] || ssh-keygen -y -f "$SSH_KEY" > "$SSH_KEY.pub"
  info "chave pública: $SSH_KEY.pub"
}

# --- imagem ------------------------------------------------------------------
resolve_image() {
  local url=$IMAGE
  if [[ $url =~ ^https?:// ]]; then
    mkdir -p "$CACHE"
    local out=$CACHE/$(basename "${url%%\?*}")
    if [[ -f $out ]]; then
      info "imagem já baixada: $out"
    else
      info "baixando $url"
      if command -v curl >/dev/null; then
        curl -fL --retry 3 -C - -o "$out" "$url"
      else
        wget -c -O "$out" "$url"
      fi
    fi
    IMAGE=$out
  fi
  [[ -f $IMAGE ]] || die "imagem não encontrada: $IMAGE"
  case $IMAGE in
    *.gz)  gzip -t "$IMAGE" || die "gzip corrompido: $IMAGE" ;;
    *.img|*.img.xz|*.xz) ;;
    *) die "formato não suportado (use .img ou .img.gz): $IMAGE" ;;
  esac
  if [[ -n $IMAGE_SHA256 ]]; then
    info "conferindo sha256 (pode demorar)"
    local got; got=$(sha256sum "$IMAGE" | awk '{print $1}')
    [[ $got == "$IMAGE_SHA256" ]] || die "sha256 não confere: esperado $IMAGE_SHA256, obtido $got"
    info "checksum ok"
  else
    warn "sem IMAGE_SHA256: a integridade da imagem não foi verificada"
  fi
  info "imagem: $IMAGE ($(du -h "$IMAGE" | cut -f1))"
}

# --- cartão ------------------------------------------------------------------
check_sd() {
  [[ -n ${SD_DEV:-} ]] || ask SD_DEV "Dispositivo do cartão SD (ex.: /dev/sdb)"
  [[ -b $SD_DEV ]] || die "não é dispositivo de bloco: $SD_DEV (veja lsblk)"
  [[ $SD_DEV =~ ^/dev/(sd[a-z]+|mmcblk[0-9]+|nvme[0-9]+n[0-9]+|vd[a-z]+)$ ]] \
    || die "informe o disco inteiro, sem partição: ex /dev/sdb"

  local root_src root_disk
  root_src=$(findmnt -no SOURCE / || true)
  root_disk=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -1 || true)
  [[ -n $root_disk && $root_disk == "$(basename "$SD_DEV")" ]] \
    && die "recusando $SD_DEV: é o disco do sistema em execução"

  local mounted
  mounted=$(lsblk -rno MOUNTPOINT "$SD_DEV" 2>/dev/null | grep -v '^$' | head -3 | xargs echo || true)
  if [[ -n $mounted ]]; then
    die "$SD_DEV tem partições montadas ($mounted); desmonte antes (umount)"
  fi

  local size_mb
  size_mb=$(lsblk -bdno SIZE "$SD_DEV" | awk '{print int($1/1024/1024)}')
  ((size_mb >= 7000)) || die "cartão pequeno demais: ${size_mb} MiB (o eflasher pede ~8 GB)"

  info "cartão: $SD_DEV (${size_mb} MiB) · modelo: $(lsblk -dno MODEL "$SD_DEV" | xargs echo)"
}

confirm_card() {
  ((ASSUME_YES)) && return 0
  cat <<EOF

${R}${B}Todos os dados de $SD_DEV serão apagados.${N}
Cartão: $(lsblk -dno MODEL,SIZE "$SD_DEV" | xargs echo)

Digite o caminho do dispositivo para confirmar:
EOF
  local t; read -r t
  [[ $t == "$SD_DEV" ]] || die "confirmação não confere; nada foi escrito"
}

# --- fases -------------------------------------------------------------------
phase_check() {
  check_deps
  ensure_config
  resolve_image
  check_sd
  echo
  info "tudo pronto para './install.sh card'"
}

phase_card() {
  need_root
  check_deps
  ensure_config
  ensure_key
  resolve_image
  check_sd
  ((DRY_RUN)) || confirm_card

  local dev=$SD_DEV
  if ((DRY_RUN)); then
    info "[dry-run] gravar $IMAGE em $dev"
    info "[dry-run] injetar firmware + Wi-Fi + chave em $dev"
    info "[dry-run] armar gravação da eMMC em $dev"
    return 0
  fi

  step "1/3 · gravando a imagem no cartão"
  bash "$HERE/scripts/flash-sd.sh" "$IMAGE" "$dev"

  step "2/3 · injetando firmware, Wi-Fi e chave SSH"
  bash "$HERE/scripts/wifi-inject.sh" "$dev" "$SSID" "$PSK" "$HERE/firmware" "${WIFI_MAC:-}" "$SSH_KEY.pub"

  step "3/3 · armando a gravação da eMMC no primeiro boot"
  bash "$HERE/scripts/install-headless-flash.sh" "$dev"

  sync
  cat <<EOF

${G}${B}Cartão pronto.${N}

  1. coloque o cartão na placa e ligue;
  2. a placa grava a eMMC sozinha (~15 min) e desliga;
  3. ligue de novo, ainda com o cartão, e rode:  ./install.sh net

EOF
}

board_ssh() { # board_ssh <ip> <comando...>
  local ip=$1; shift
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=6 -o LogLevel=ERROR -i "$SSH_KEY" "root@$ip" "$@"
}

discover_board() {
  [[ -n ${BOARD_IP:-} ]] && { info "usando BOARD_IP=$BOARD_IP"; return 0; }
  mkdir -p "$CACHE"
  local iface subnet ip have_ping=0
  command -v ping >/dev/null && have_ping=1
  iface=$(ip -4 route show default | awk '/default/{print $5; exit}')
  [[ -n $iface ]] || die "sem rota padrão; informe BOARD_IP"
  subnet=$(ip -4 -o addr show dev "$iface" | awk '{print $4}' | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3}')
  info "procurando a placa em ${subnet}.0/24 (SSH na porta 22)"
  for i in $(seq 1 254); do
    (
      if ((have_ping)) && ! ping -c1 -W1 "${subnet}.${i}" >/dev/null 2>&1; then
        exit 0
      fi
      (exec 3<>"/dev/tcp/${subnet}.${i}/22") 2>/dev/null && echo "${subnet}.${i}"
    ) &
  done > "$CACHE/candidates" 2>/dev/null || true
  wait
  for ip in $(sort -u "$CACHE/candidates"); do
    if board_ssh "$ip" true 2>/dev/null; then
      BOARD_IP=$ip
      info "placa encontrada: $BOARD_IP"
      return 0
    fi
  done
  die "não achei a placa. Confira o Wi-Fi do cartão ou informe BOARD_IP=..."
}

wait_flash() {
  local ip=$1 tries=${2:-120} log
  info "aguardando a gravação da eMMC (até ~20 min)"
  for ((i=1; i<=tries; i++)); do
    log=$(board_ssh "$ip" 'cat /root/flash-emmc.log 2>/dev/null | tail -3' 2>/dev/null || true)
    if grep -q 'FLASH_DONE verify=ok' <<<"$log"; then
      info "eMMC gravada e verificada (verify=ok)"
      return 0
    fi
    if grep -q 'FLASH_FAILED' <<<"$log"; then
      printf '%s\n' "$log" >&2
      die "a gravação da eMMC falhou — log acima"
    fi
    printf '.'
    sleep 10
  done
  echo
  die "tempo esgotado esperando a gravação; veja /root/flash-emmc.log no cartão"
}

phase_net() {
  check_deps
  load_conf
  ensure_config
  ensure_key
  mkdir -p "$CACHE"

  step "1/3 · encontrando a placa (cartão no lugar)"
  discover_board

  if ! board_ssh "$BOARD_IP" 'findmnt -no SOURCE /' | grep -qE 'mmcblk0p?[0-9]+'; then
    warn "a placa não parece estar bootando pelo cartão; siga com cuidado"
  fi
  board_ssh "$BOARD_IP" 'ls /dev/mmcblk*p2' >/dev/null 2>&1 \
    || die "não vejo a eMMC na placa; o cartão está no lugar?"

  step "2/3 · aguardando a gravação da eMMC"
  wait_flash "$BOARD_IP"
  cat <<EOF

${Y}A placa desliga sozinha depois de gravar.${N}
Ligue de novo, ${B}ainda com o cartão${N}, e pressione Enter para provisionar a eMMC.
EOF
  ((ASSUME_YES)) || read -r _

  discover_board
  board_ssh "$BOARD_IP" 'true' || die "a placa não respondeu no segundo boot"

  step "3/3 · provisionando o sistema da eMMC"
  scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
      -i "$SSH_KEY" "$HERE/scripts/provision-emmc-wifi.sh" "root@$BOARD_IP:/root/"
  board_ssh "$BOARD_IP" "bash /root/provision-emmc-wifi.sh $(printf '%q' "$SSID") $(printf '%q' "$PSK") $(printf '%q' "${WIFI_MAC:-}") $(printf '%q' "$HOSTNAME_NEW")"

  info "desligando a placa para você trocar o cartão"
  board_ssh "$BOARD_IP" 'sync; poweroff' 2>/dev/null || true
  cat <<EOF

${G}${B}eMMC provisionada.${N}

  1. retire o cartão SD;
  2. ligue a placa;
  3. em ~1 minuto rode:  ./install.sh verify

EOF
}

phase_verify() {
  check_deps; load_conf
  [[ -n ${BOARD_IP:-} ]] || discover_board
  local ip=$BOARD_IP src fails
  info "conferindo $ip"
  src=$(board_ssh "$ip" 'findmnt -no SOURCE /')
  info "root em: $src"
  grep -q 'mmcblk0p' <<<"$src" || warn "o root não está na eMMC (mmcblk0p2) — cartão ainda no lugar?"
  board_ssh "$ip" 'hostname; uptime -p'
  board_ssh "$ip" 'iw dev wlan0 link 2>/dev/null | sed -n "2p;6p"'
  fails=$(board_ssh "$ip" 'systemctl --failed --no-legend --no-pager | wc -l')
  info "unidades falhando: $fails"
  (( fails == 0 )) || warn "há unidades falhando; rode: ssh root@$ip systemctl --failed"
  info "pronto"
}

# --- main --------------------------------------------------------------------
load_conf

case $CMD in
  check)  phase_check ;;
  card)   phase_card ;;
  net)    phase_net ;;
  verify) phase_verify ;;
  all)    phase_card; phase_net; phase_verify ;;
  *)      usage; exit 1 ;;
esac
