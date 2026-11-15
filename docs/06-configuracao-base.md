# 06 — Configuração base

Deixar o sistema em um estado mínimo, seguro e previsível, **imediatamente após**
instalar na eMMC. Faça nesta ordem.

## 1. npi-config — o painel de configuração

```bash
sudo npi-config
```

| Seção | O que ajustar | Por quê |
| --- | --- | --- |
| `Change User Password` | trocar senha do `pi` | `pi`/`pi` é público |
| `Change Hostname` | ex. `ctl-nanopi` | identificar na rede |
| `Localisation Options` → Timezone | `America/Sao_Paulo` | logs com hora correta |
| `Localisation Options` → Locale | `pt_BR.UTF-8` (opcional) | acentos no console |
| `Localisation Options` → Keyboard | conforme o teclado | só afeta console local |
| `Interfacing Options` → SSH | Enable | administração remota |
| `Interfacing Options` → I2C/SPI/Serial/PWM | habilitar conforme uso | ver [08](08-gpio.md) |
| `Boot Options` → Autologin | **Disable** em produção | acesso físico não deve dar shell |
| `Advanced Options` → Expand Filesystem | já feito automaticamente | conferir com `df -h` |

> O `Serial` do npi-config controla a serial **de aplicação** (UART1/UART2 nos
> headers). Não desabilite o UART0 do console de debug — você perderia o acesso
> de recuperação.

## 2. Senha do root

```bash
sudo passwd root
```

Ou bloqueie o login direto do root (mais seguro, já que existe `sudo`):

```bash
sudo passwd -l root
```

## 3. Identidade e horário

```bash
sudo hostnamectl set-hostname ctl-nanopi
sudo timedatectl set-timezone America/Sao_Paulo
timedatectl                     # confirme "System clock synchronized: yes"
```

**Sem Wi-Fi não há NTP** e a placa inicia com data errada — o que quebra TLS,
logs e `apt`. Se o relógio estiver muito longe, force:

```bash
sudo date -s "2026-11-13 10:00:00"
sudo systemctl restart systemd-timesyncd
```

## 4. Chave SSH (em vez de senha)

No PC:

```bash
ssh-keygen -t ed25519 -C "nanopi-$(date +%Y%m%d)"   # se ainda não tiver
ssh-copy-id pi@<IP>
ssh pi@<IP> 'echo ok'                                # deve entrar sem senha
```

Depois desabilite senha por SSH:

```bash
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

**Mantenha o console serial conectado** até validar que a chave funciona. Se você
se trancar fora, a serial é o resgate.

Pelo [`install.sh`](15-instalador.md) isso já vem feito: o `net` copia a chave
do cartão para a eMMC e grava
`/etc/ssh/sshd_config.d/10-no-password.conf` (use `ALLOW_PASSWORD=1` para
manter o login por senha).

## 5. Atualizar o sistema

```bash
sudo apt update
sudo apt full-upgrade -y
sudo apt autoremove -y
sudo reboot
```

> `full-upgrade` em kernel 4.14 pode puxar atualização de kernel do repositório
> FriendlyElec. Se a placa usa um módulo compilado à mão, prefira `apt upgrade`
> e teste depois de reiniciar.

## 6. Pacotes base

Conjunto mínimo útil para qualquer papel de controlador:

```bash
sudo apt install -y \
  htop iotop ncdu tree \
  curl wget ca-certificates gnupg \
  vim less rsync \
  net-tools iproute2 dnsutils \
  jq \
  v4l-utils usbutils pciutils \
  ntpdate
```

Ferramentas de diagnóstico específicas da placa:

```bash
sudo apt install -y i2c-tools spi-tools python3-dev python3-pip
```

## 7. Swap

O FriendlyCore já cria uma swap de **512 MB**. Confira:

```bash
swapon --show
free -h
```

Com 512 MB de RAM isso é importante. Se quiser aumentar (cartão/eMMC sofre com
swap intenso, use com moderação):

```bash
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Ajuste a agressividade para não desgastar a eMMC:

```bash
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl --system
```

## 8. Reduzir escrita desnecessária na eMMC

A eMMC tem ciclos de escrita finitos. Para um controlador 24/7:

```bash
# logs em memória (perde os logs no reboot, mas evita desgaste)
sudo mkdir -p /var/log/journal
sudo sed -i 's/^#\?Storage=.*/Storage=volatile/' /etc/systemd/journald.conf
sudo sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=64M/' /etc/systemd/journald.conf
sudo systemctl restart systemd-journald
```

Opção mais conservadora: manter journal em disco mas limitado a 64 MB (só o
`SystemMaxUse`). Escolha conforme sua necessidade de auditoria — se o projeto é
de controle, perder log de reboot esconde causa de falha.

## 9. Fuso, locale e teclado (checagem final)

```bash
timedatectl
locale
localectl
```

## 10. Registro do estado final

```bash
{
  echo "== data: $(date -Is)"
  echo "== host: $(hostname)"
  echo "== so: $(. /etc/os-release; echo "$PRETTY_NAME")"
  echo "== kernel: $(uname -r)"
  echo "== disco:"; df -h /
  echo "== memoria:"; free -h
  echo "== rede:"; ip -4 addr
  echo "== servicos ativos:"; systemctl list-units --type=service --state=running --no-pager
} | tee ~/estado-inicial.txt
```

Guarde esse arquivo no repositório (sem dados sensíveis) e faça o backup da
eMMC **agora**, antes de instalar a aplicação.

## Próximo passo

[07 — Rede](07-rede.md) · [09 — Backup da eMMC](09-manutencao.md#backup-e-restauração-da-emmc)
