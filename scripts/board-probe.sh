#!/bin/sh
#
# board-probe.sh — coleta o estado do Wi-Fi/da rede DENTRO da placa e grava em
# um arquivo, para ser lido depois no PC (o cartão é o canal, não a serial).
#
# Instalado no rootfs por scripts/install-probe.sh, que o chama no boot via
# /etc/rc.local. Também pode ser rodado à mão na placa.
#
# Saída: /root/board-probe.txt  (e /boot/board-probe.txt, se /boot for gravável)

OUT=${PROBE_OUT:-/root/board-probe.txt}

exec >"$OUT" 2>&1

echo "=== board-probe ==="
echo "data: $(date -Is 2>/dev/null || date)"
echo "uptime: $(cut -d. -f1 /proc/uptime 2>/dev/null) s"
echo "kernel: $(uname -srm)"
echo "cmdline: $(cat /proc/cmdline 2>/dev/null)"

echo
echo "=== rfkill ==="
rfkill list 2>&1 || echo "(rfkill ausente)"

echo
echo "=== interfaces (ip -br) ==="
ip -br link 2>&1
ip -br addr 2>&1

echo
echo "=== /proc/net/wireless ==="
cat /proc/net/wireless 2>&1

echo
echo "=== MAC do wlan0 ==="
cat /sys/class/net/wlan0/address 2>&1
cat /sys/class/net/wlan0/operstate 2>&1

echo
echo "=== módulos ==="
lsmod 2>&1 | grep -E 'brcm|cfg80211|mac80211|sdio' || echo "(nenhum módulo de Wi-Fi carregado)"

echo
echo "=== parâmetros do brcmfmac ==="
for p in /sys/module/brcmfmac/parameters/*; do
  [ -e "$p" ] && echo "$(basename "$p") = $(cat "$p" 2>/dev/null)"
done

echo
echo "=== dmesg (rede) ==="
dmesg 2>&1 | grep -iE 'brcm|cfg80211|wlan|sdio|mmc[0-9]|firmware' | tail -n 150

echo
echo "=== domínio regulatório ==="
iw reg get 2>&1 || echo "(iw ausente)"

echo
echo "=== iw dev ==="
iw dev 2>&1 || true

echo
echo "=== wpa_supplicant: status ==="
wpa_cli -i wlan0 status 2>&1 | head -30

echo
echo "=== wpa_supplicant: varreduras ==="
n=0
while [ "$n" -lt 3 ]; do
  echo "--- tentativa $n ---"
  wpa_cli -i wlan0 scan 2>&1
  sleep 10
  wpa_cli -i wlan0 scan_results 2>&1 | head -40
  n=$((n + 1))
done

echo
echo "=== wpa_supplicant: tentativa de associação ==="
wpa_cli -i wlan0 status 2>&1 | head -30
wpa_cli -i wlan0 list_networks 2>&1 | head -10

echo
echo "=== processos de rede ==="
ps w 2>/dev/null | grep -E 'wpa_supplicant|dhclient|ifup|dhcpcd' | grep -v grep

echo
echo "=== firmware instalado ==="
ls -l /lib/firmware/brcm/ 2>&1 | head -12
echo "--- sha256 ---"
sha256sum /lib/firmware/brcm/brcmfmac43430-sdio.* 2>&1
echo "--- 3 primeiras linhas do NVRAM ---"
head -3 /lib/firmware/brcm/brcmfmac43430-sdio.txt 2>&1
echo "--- xtalfreq/boardrev ---"
grep -E '^(xtalfreq|boardrev|prodid)=' /lib/firmware/brcm/brcmfmac43430-sdio.txt 2>&1

echo
echo "=== configuração de rede ==="
sed -E 's/(psk=).*/\1***OCULTA***/' /etc/wpa_supplicant/wpa_supplicant.conf 2>&1
grep -vE '^\s*#|^\s*$' /etc/network/interfaces 2>&1

echo
echo "=== fim ==="

sync
# cópia de cortesia na partição FAT, se existir e estiver gravável
if [ -d /boot ] && cp -f "$OUT" /boot/board-probe.txt 2>/dev/null; then
  echo "(cópia gravada em /boot/board-probe.txt)"
fi
