# 09 — Operação e manutenção

Sistema no eMMC, configurado. Agora: manter saudável, medir, e ter como voltar
atrás.

## Monitoramento básico

```bash
# temperatura + frequência de cada core (ferramenta da FriendlyElec)
cpu_freq
```

```
Aavailable frequency(KHz):
        480000 624000 816000 1008000
Current frequency(KHz):
        CPU0 online=1 temp=45230C governor=ondemand freq=1008000KHz
```

Interpretação do campo `temp`: valor em **mili-graus** com sufixo `C` —
`45230C` = 45,23 °C.

Alternativa padrão do kernel:

```bash
cat /sys/class/thermal/thermal_zone0/temp    # 45230 = 45.23 °C
```

### Faixas de referência (H3, kernel 4.14, sem dissipador)

| Temperatura | Estado | Ação |
| --- | --- | --- |
| 30–50 °C | normal em idle | nenhuma |
| 50–65 °C | normal sob carga | ok |
| 65–80 °C | quente | melhorar ventilação |
| > 80 °C | throttling | dissipador obrigatório, reduzir carga |
| > 90 °C | risco | desligar e revisar projeto térmico |

### Ajustar frequência

```bash
cpu_freq -s 816000      # fixa em 816 MHz (menos calor, menos consumo)
cpu_freq                # volta ao governor ondemand após reboot
```

Para um controlador que fica 24/7 fazendo pouco processamento, **fixar em
624–816 MHz** reduz calor e consumo sem perda perceptível. Meça antes e depois:

```bash
# consumo aproximado: meça a corrente na fonte com um USB power meter
```

## Script de saúde (cole e agende)

```bash
sudo tee /usr/local/bin/saude.sh >/dev/null <<'EOF'
#!/bin/bash
echo "== $(date -Is) =="
echo "-- uptime: $(uptime -p)"
echo "-- temp:   $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)"
echo "-- load:   $(cut -d' ' -f1-3 /proc/loadavg)"
echo "-- ram:";    free -h | sed -n '2p'
echo "-- disco:";  df -h / | tail -1
echo "-- wifi:    $(iwconfig wlan0 2>/dev/null | grep -oE 'Signal level=[^ ]+')"
echo "-- erros no dmesg: $(dmesg --level=err,crit,alert 2>/dev/null | wc -l)"
echo "-- servico: $(systemctl is-active controlador.service 2>/dev/null)"
EOF
sudo chmod +x /usr/local/bin/saude.sh
```

## Logs

```bash
journalctl -b -p err            # erros desta inicialização
journalctl -u controlador -n 50 # últimas linhas do seu serviço
journalctl --since "1 hour ago"
dmesg -T --level=err,crit        # kernel, com timestamps legíveis
```

Se você configurou journal volátil ([06](06-configuracao-base.md#8-reduzir-escrita-desnecessária-na-emmc)),
os logs somem no reboot. Para um controlador, considere enviar logs para fora:

```bash
# exemplo: enviar para um syslog remoto
echo '*.* @@192.168.1.10:514' | sudo tee /etc/rsyslog.d/50-remoto.conf
sudo systemctl restart rsyslog
```

## Relógio: o ponto fraco sem rede

A placa **não tem RTC com bateria**. Sem rede, ela inicia com a data de
compilação da imagem.

```bash
timedatectl
```

Se `System clock synchronized: no` e você está offline:

```bash
sudo date -s "2026-11-13 10:00:00"
```

Para sobreviver a reboots offline, grave a hora periodicamente em disco:

```bash
sudo apt install -y fake-hwclock
sudo systemctl enable --now fake-hwclock
```

> `fake-hwclock` não é um relógio real: ele salva a última hora conhecida e a
> restaura no boot. Erro acumula enquanto desligada.

## Atualizações — com cuidado

```bash
sudo apt update
apt list --upgradable
```

Política sugerida para controlador em produção:

| Ação | Frequência | Risco |
| --- | --- | --- |
| `apt update` + verificar lista | semanal | nenhum |
| atualizações de segurança | mensal | baixo |
| `apt full-upgrade` | só com backup feito | médio/alto |
| trocar de kernel | praticamente nunca | alto |

Fluxo seguro:

```bash
# 1. backup da eMMC (seção abaixo)
# 2. atualizar
sudo apt update && sudo apt upgrade -y
# 3. reiniciar e validar
sudo reboot
# 4. conferir
uname -r; systemctl --failed
```

Segure pacotes que você não quer que mudem:

```bash
sudo apt-mark hold linux-image-current-sunxi   # ajuste o nome real
apt-mark showhold
```

### Evitar atualização acidental do kernel

Antes de qualquer upgrade grande, registre a versão:

```bash
uname -r | tee ~/kernel-original.txt
dpkg -l | grep -E '^ii  linux-image' | tee -a ~/kernel-original.txt
```

## Backup e restauração da eMMC

O backup mais valioso é a imagem **completa** da eMMC: qualquer erro vira um
restore de 20 minutos.

### Backup pela rede (sem desmontar nada)

O sistema precisa estar rodando normalmente. Do seu PC:

```bash
ssh root@<IP> "dd if=/dev/mmcblk2 bs=4M status=progress" \
  | gzip -1 > nanopi-emmc-$(date +%Y%m%d).img.gz
```

- Confirme o device **antes**: `ssh root@<IP> lsblk` → a eMMC é o device que
  contém `/` (normalmente `mmcblk2`, `mmcblk0` em alguns kernels).
- 8 GB por Wi-Fi 2.4 GHz leva **20–40 min**. Faça com a placa perto do roteador.
- Arquivo final: ~1–2 GB comprimido.

### Backup local (mais rápido, precisa de armazenamento USB)

Com um pendrive no header GPIO2 ou hub USB:

```bash
lsblk                                   # identifique o pendrive, ex: /dev/sda1
sudo mkdir -p /mnt/usb && sudo mount /dev/sda1 /mnt/usb
sudo dd if=/dev/mmcblk2 of=/mnt/usb/nanopi-emmc-$(date +%Y%m%d).img bs=4M status=progress conv=fsync
sync && sudo umount /mnt/usb
```

### Restauração

1. Grave a imagem `sd` do FriendlyCore em um cartão ([03](03-gravacao-sd.md)).
2. Dê boot **pelo cartão** (a eMMC não deve estar em uso).
3. Confirme que está no cartão:

```bash
findmnt -no SOURCE /        # deve ser /dev/mmcblk0p2 (cartão), NÃO mmcblk2
lsblk
```

4. Grave o backup na eMMC:

```bash
# enviando do PC para a placa via ssh
gunzip -c nanopi-emmc-YYYYMMDD.img.gz | ssh root@<IP> "dd of=/dev/mmcblk2 bs=4M conv=fsync status=progress"
```

5. `sync`, desligue, remova o cartão, ligue.

### Alternativa recomendada: "imagem de fábrica" própria

Em vez de restaurar um `dd` (que exige o mesmo tamanho de eMMC), mantenha um
cartão eflasher pronto com a sua configuração base. Menos elegante, mas
**sempre funciona** — é o mesmo caminho da instalação inicial.

Fluxo: configure a placa como quer → grave a eMMC em imagem → coloque essa
imagem no diretório `FRIENDLYARM` do cartão eflasher → qualquer placa igual pode
ser restaurada a partir dali.

## Saúde da eMMC

`mmc-utils` lê contadores do próprio chip:

```bash
sudo apt install -y mmc-utils
sudo mmc extcsd read /dev/mmcblk2 | grep -E 'LIFE_TIME|PRE_EOL'
```

| Campo | Significado |
| --- | --- |
| `LIFE_TIME_EST_TYP_A/B` | desgaste estimado em décimos (0x01 = 10%, 0x0A = 100%) |
| `PRE_EOL_INFO` | 0x01 normal, 0x02 warning (80%), 0x03 urgente |

Registre esses valores a cada trimestre. Subiu de 0x01 para 0x05 em pouco tempo?
Tem escrita demais — reveja logs, swap e banco de dados.

## Rotina de manutenção sugerida

| Frequência | Tarefa |
| --- | --- |
| diária (automática) | `/usr/local/bin/saude.sh` + alerta se temp > 75 °C ou serviço inativo |
| semanal | `apt update`, conferir `systemctl --failed`, `df -h` |
| mensal | atualizar pacotes, revisar logs de erro, testar restore do backup |
| trimestral | ler `LIFE_TIME_EST`, limpar eMMC (`fstrim -av`), revisar cabos/antena |
| ao mudar algo | **backup antes**, backup depois |

```bash
# trim: recupera blocos livres na eMMC (evita degradação de escrita)
sudo fstrim -av
```

## Checklist de "pronto para produção"

- [ ] Senhas trocadas; SSH por chave; autologin desabilitado
- [ ] IP fixo (reserva DHCP) e hostname definido
- [ ] Power-save do Wi-Fi desligado
- [ ] Serviço systemd com `Restart=on-failure` e `journalctl` funcionando
- [ ] Swap configurada e `swappiness` baixo
- [ ] Logs limitados ou enviados para fora
- [ ] Backup da eMMC testado (restaurou pelo menos uma vez)
- [ ] Dissipador/ventilação instalado; temperatura em carga < 75 °C
- [ ] Console serial acessível para emergência
- [ ] Etiqueta na placa com hostname, IP e data
