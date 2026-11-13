# 04 — Primeiro boot e acesso

Objetivo: ver a placa subir, entrar nela e conectá-la à rede — **sem monitor**,
já que a NEO Air não tem saída de vídeo.

## Antes de energizar

1. microSD gravado ([03](03-gravacao-sd.md)) inserido no slot da placa.
2. Antena Wi-Fi conectada no U.FL.
3. Adaptador USB-TTL ligado ao header UART0:

| Adaptador | Placa (UART0) |
| --- | --- |
| GND | pino 1 (GND) |
| RX | pino 3 (UART_TXD0) |
| TX | pino 4 (UART_RXD0) |
| **VCC — não conectar** | pino 2 (VDD_5V) |

4. Adaptador em **3.3 V** (confira o jumper).
5. Só então plugue a fonte 5 V/2 A no microUSB.

> Não alimente pela serial. O pino 2 é 5 V e o adaptador não fornece corrente
> suficiente — além de contornar a proteção da placa.

## Abrir o console serial

Primeiro, dê ao seu usuário acesso à porta serial (uma vez só, exige relogin):

```bash
sudo usermod -aG dialout "$USER"
```

Descubra a porta:

```bash
ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
dmesg | tail -5          # mostra "cp210x converter ... attached to ttyUSB0"
```

Conecte (115200 8N1, sem flow control):

```bash
picocom -b 115200 -l /tmp/nanopi-boot.log /dev/ttyUSB0
```

- **picocom**: sai com `Ctrl-A` `Ctrl-X`
- **minicom**: `minicom -D /dev/ttyUSB0 -b 115200`, sai com `Ctrl-A` `X`
- **screen**: `screen /dev/ttyUSB0 115200`, sai com `Ctrl-A` `K`

A flag `-l` do picocom grava tudo em `/tmp/nanopi-boot.log`. **Guarde esse log** —
ele é a evidência de que o boot ocorreu e a base para diagnosticar problemas.

## O que você deve ver

Sequência normal (timestamps variam):

```
U-Boot 20xx.xx ... (FriendlyElec)
DRAM:  512 MiB
...
Hit any key to stop autoboot:  0
...
[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 4.14.xxx ...
...
[  OK  ] Reached target Multi-User System.
```

Se parar em `Hit any key to stop autoboot`, a placa não achou o kernel —
veja [troubleshooting](10-troubleshooting.md).

### Diagnóstico pelos LEDs

| Momento | PWR | STAT |
| --- | --- | --- |
| Energizada, sem boot | aceso | apagado |
| Boot / acesso a disco | aceso | piscando |
| Sistema pronto | aceso | piscando lento (heartbeat) |
| Kernel panic / travada | aceso | apagado |

Cores conforme a versão da placa (V1.0: PWR verde/STAT azul; V1.1: PWR
vermelho/STAT verde) — ver [00-hardware.md](00-hardware.md).

## Primeiro login

O sistema faz **autologin** como `pi` no console serial.

| Conta | Usuário | Senha |
| --- | --- | --- |
| Não-root | `pi` | `pi` |
| Root | `root` | `fa` |

Pegue IP e confirme que o rootfs foi expandido:

```bash
ip -4 addr show wlan0
df -h /
```

Na primeira inicialização o script de expansão cresce o rootfs até o tamanho do
cartão. Se `df` mostrar ~1.5 G em um cartão de 32 G, a expansão falhou — veja
[troubleshooting](10-troubleshooting.md).

## Conectar ao Wi-Fi (necessário para SSH)

A NEO Air só tem `wlan0`. Duas formas:

### Via npi-config (recomendado)

```bash
sudo npi-config
```

Caminho: `Network Options` → `WiFi` → selecionar SSID → senha.
Depois confirme:

```bash
nmcli dev wifi list
ip -4 addr show wlan0
ping -c3 1.1.1.1
```

### Via nmcli (direto)

```bash
sudo nmcli r wifi on
sudo nmcli dev wifi                       # lista redes
sudo nmcli dev wifi connect "SSID" password "SENHA" ifname wlan0
```

Se o device aparecer como `unmanaged`, veja [07-rede.md](07-rede.md).

## SSH a partir do PC

```bash
ssh pi@<IP>
# senha: pi
```

Se a conexão for recusada:

```bash
# no console serial, como pi
sudo systemctl status ssh
sudo npi-config     # Interfacing Options → SSH → Enable
```

## Comandos de sanidade

Rode e registre a saída (cola no [09-manutencao.md](09-manutencao.md) depois):

```bash
uname -a
cat /etc/os-release
lsblk
free -h
cpu_freq
vcgencmd measure_temp 2>/dev/null || cat /sys/class/thermal/thermal_zone0/temp
nmcli dev status
ip -4 addr
```

## Registro de identidade da placa

Anote agora, é o que permite reconhecer a placa depois:

```bash
cat /sys/class/net/wlan0/address     # MAC do Wi-Fi
cat /sys/class/net/eth0/address 2>/dev/null
cat /proc/cpuinfo | grep -i serial
sudo blkid
```

Guarde em [11-decisoes.md](11-decisoes.md) (MAC, IP, versão do SO, data).

## Próximo passo

Sistema funcionando pelo cartão → agora instalar no eMMC:
[05 — Gravar o SO no eMMC](05-gravacao-emmc.md).

Se algo deu errado: [10 — Troubleshooting](10-troubleshooting.md).
