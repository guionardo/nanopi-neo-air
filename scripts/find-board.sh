#!/usr/bin/env bash
#
# find-board.sh — acha a placa na rede local (sem serial, sem nmap).
#
# Faz ping sweep na /24 e lista, para cada vizinho que responder, o MAC e se a
# porta 22 (SSH) está aberta. A placa deve aparecer com 22 aberta e MAC de
# Cypress/Broadcom (00:90:4C:…) do AP6212.
#
# Uso:
#   ./scripts/find-board.sh            # detecta a sub-rede pela rota padrão
#   ./scripts/find-board.sh 192.168.88 # sub-rede explícita

set -uo pipefail

subnet=${1:-$(ip route | awk '/^default/ {print $3; exit}' | cut -d. -f1-3)}
[[ $subnet =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "sub-rede inválida: $subnet" >&2; exit 1; }

printf '==> varrendo %s.0/24 (ping + porta 22)\n' "$subnet"

for i in $(seq 1 254); do
  ( ping -c1 -W1 "$subnet.$i" >/dev/null 2>&1 ) &
done
wait

printf '\n%-16s %-18s %s\n' "IP" "MAC" "SSH"
printf '%-16s %-18s %s\n' "----------------" "------------------" "----"

found=0
while read -r ip mac _; do
  [[ $ip == "$subnet."* ]] || continue
  [[ $mac == "<incomplete>" || -z $mac ]] && continue
  if (exec 3<>/dev/tcp/"$ip"/22) 2>/dev/null; then
    ssh=aberta; found=$((found+1))
  else
    ssh=-
  fi
  printf '%-16s %-18s %s\n' "$ip" "$mac" "$ssh"
done < <(ip neigh show | awk '{print $1, $5}')

printf '\n'
if (( found > 0 )); then
  printf 'Candidatos com SSH: %d. Teste: ssh pi@<ip>   (senha padrão: fa)\n' "$found"
else
  printf 'Nenhum host com SSH. A placa não subiu o wlan0 ou não pegou DHCP.\n'
fi
