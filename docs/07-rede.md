# 07 — Rede

A NEO Air tem **apenas `wlan0`**. Não existe `eth0` a menos que você adicione um
adaptador USB-Ethernet no header GPIO2. Toda a estratégia de rede depende disso.

## Stack: NetworkManager

O FriendlyCore usa **NetworkManager**, não `/etc/network/interfaces`. Comandos
úteis:

```bash
nmcli general status
nmcli dev status          # estados: connected / disconnected / unmanaged
nmcli connection show
nmcli dev wifi list
```

Se um device aparecer como **`unmanaged`**, o NetworkManager está ignorando. Causa
mais comum: entradas em `/etc/network/interfaces` marcando a interface como
gerida pelo `ifupdown`.

```bash
cat /etc/network/interfaces.d/*
```

Solução: remover/comentar qualquer bloco sobre `wlan0` nesses arquivos e:

```bash
sudo systemctl restart NetworkManager
```

## Conectar a um Wi-Fi

```bash
sudo nmcli dev wifi rescan
sudo nmcli dev wifi list
sudo nmcli dev wifi connect "MINHA_REDE" password "MINHA_SENHA" ifname wlan0
```

A conexão é salva e volta automaticamente no próximo boot. Verifique:

```bash
nmcli -f NAME,DEVICE,AUTOCONNECT connection show
ip -4 addr show wlan0
nmcli dev show wlan0 | grep -E 'GENERAL.CONNECTION|IP4.ADDRESS'
```

### Rede oculta

```bash
sudo nmcli dev wifi connect "REDE_OCULTA" password "SENHA" hidden yes
```

### Redes com WPA2-Enterprise / 802.1X

```bash
sudo nmcli connection add type wifi con-name "corp" ifname wlan0 ssid "CORP"
sudo nmcli connection modify "corp" wifi-sec.key-mgmt wpa-eap
sudo nmcli connection modify "corp" 802-1x.eap peap 802-1x.identity "usuario"
sudo nmcli connection modify "corp" 802-1x.password "senha"
sudo nmcli connection up "corp"
```

## IP fixo (recomendado para controlador)

Um controlador com IP dinâmico é uma fonte de dor de cabeça. Duas abordagens:

### A. Reserva no DHCP do roteador (preferida)

Mais simples e sem risco de conflito: no roteador, reserve o MAC da placa.

```bash
cat /sys/class/net/wlan0/address     # MAC a cadastrar no roteador
```

Vantagem: se você trocar de rede, nada quebra.

### B. IP estático no device

```bash
sudo nmcli connection modify "MINHA_REDE" \
  ipv4.method manual \
  ipv4.addresses 192.168.1.50/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns "192.168.1.1 1.1.1.1"
sudo nmcli connection up "MINHA_REDE"
```

Para reverter ao DHCP:

```bash
sudo nmcli connection modify "MINHA_REDE" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns ""
sudo nmcli connection up "MINHA_REDE"
```

## Modo Access Point (a placa vira o roteador)

Útil para acesso direto de campo, sem infraestrutura. O FriendlyCore traz o
script `turn-wifi-into-apmode`:

```bash
sudo turn-wifi-into-apmode yes
# informe nome do hotspot e senha quando pedido
```

Resultado: a placa cria uma rede e fica em `192.168.8.1`.

```bash
ssh root@192.168.8.1      # senha: fa (padrão)
```

Economia de energia no modo AP:

```bash
sudo iwconfig wlan0 power off
```

Voltar ao modo estação:

```bash
sudo turn-wifi-into-apmode no
```

> **Atenção:** em modo AP a placa perde o acesso à sua rede. Mantenha o console
> serial conectado, ou o comando de retorno vai exigir ir fisicamente na placa.

## Prioridade entre redes salvas

Se você cadastrou várias redes, defina a ordem de preferência:

```bash
nmcli -f NAME,AUTOCONNECT-PRIORITY connection show
sudo nmcli connection modify "REDE_PRINCIPAL" connection.autoconnect-priority 10
sudo nmcli connection modify "REDE_BACKUP"    connection.autoconnect-priority 5
```

Maior número = maior prioridade.

## Estabilidade de Wi-Fi (importante para 24/7)

O AP6212 é 2.4 GHz e de alcance modesto. Para um controlador que não pode cair:

```bash
# 1) desligar power-save (causa desconexões e latência alta)
sudo iwconfig wlan0 power off
# tornar permanente:
echo -e '[connection]\nwifi.powersave = 2' | sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf
sudo systemctl restart NetworkManager
```

```bash
# 2) verificar qualidade do sinal (Rx)
iwconfig wlan0 | grep -E 'Bit Rate|Signal|Quality'
```

| Sinal | Qualidade | Ação |
| --- | --- | --- |
| melhor que -60 dBm | excelente | ok |
| -60 a -70 dBm | boa | ok |
| -70 a -80 dBm | fraca | reposicionar / antena melhor |
| pior que -80 dBm | ruim | desconexões prováveis |

```bash
# 3) watchdog opcional: reconecta se o link cair
nmcli connection modify "MINHA_REDE" connection.autoconnect yes
```

## Firewall mínimo

Para um controlador exposto na rede local, limite a superfície:

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
sudo ufw enable
sudo ufw status verbose
```

Ajuste a sub-rede e as portas conforme a aplicação (ex.: 1883 para MQTT, 8080
para interface web). **Não exponha a placa diretamente à internet** — use VPN
(WireGuard/Tailscale) se precisar de acesso remoto.

## Diagnóstico rápido

```bash
nmcli dev status
nmcli -f all dev show wlan0 | grep -E 'IP4|GENERAL.STATE'
ip route
cat /etc/resolv.conf
ping -c3 192.168.1.1        # gateway
ping -c3 1.1.1.1            # internet por IP
ping -c3 deb.debian.org     # DNS
```

| Sintoma | Provável causa |
| --- | --- |
| `unmanaged` | `/etc/network/interfaces` conflitando |
| Conecta e cai | power-save ou sinal fraco |
| Tem IP, sem internet | gateway/DNS errado |
| Ping por IP ok, nome não | DNS |
| Não vê nenhuma rede | antena desconectada / `rfkill` |

```bash
rfkill list
sudo rfkill unblock all
```

## Próximo passo

[08 — GPIO e barramentos](08-gpio.md)
