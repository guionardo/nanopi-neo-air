# Índice da documentação

Documentação do setup do controlador baseado em NanoPi NEO Air.
Ordem sugerida de leitura = ordem numérica.

| # | Documento | O que cobre | Status |
| --- | --- | --- | --- |
| 00 | [Hardware e pinagem](00-hardware.md) | Specs, versões V1.0/V1.1, LEDs, mapa de pinos, limites elétricos | ✅ |
| 01 | [Lista de materiais](01-materiais.md) | Checklist de itens e ferramentas de bancada | ✅ |
| 02 | [Download e verificação da imagem](02-preparo-imagem.md) | Escolha do SO, nomes de arquivo, checksum | ✅ |
| 03 | [Gravação do microSD](03-gravacao-sd.md) | `dd`/script, Etcher, validação pós-gravação | ✅ |
| 04 | [Primeiro boot e acesso](04-primeiro-boot.md) | LEDs, console serial, credenciais, Wi-Fi inicial | ✅ |
| 05 | [Gravar o SO no eMMC](05-gravacao-emmc.md) | eflasher, seleção de imagem, remoção do SD | ✅ |
| 06 | [Configuração base](06-configuracao-base.md) | npi-config, hostname, timezone, chaves SSH, pacotes, swap | ✅ |
| 07 | [Rede](07-rede.md) | NetworkManager/nmcli, IP fixo, modo AP, prioridade | ✅ |
| 08 | [GPIO e barramentos](08-gpio.md) | Pinagem, I2C/SPI/UART/PWM, WiringNP, RPi.GPIO | ✅ |
| 09 | [Operação e manutenção](09-manutencao.md) | Temperatura/frequência, logs, backup do eMMC, atualização | ✅ |
| 10 | [Troubleshooting](10-troubleshooting.md) | Falhas de boot, rede, eMMC, energia | ✅ |
| 11 | [Decisões e pendências](11-decisoes.md) | ADRs curtos e o que falta definir | 📝 vivo |
| 12 | [Log de bordo](12-log-de-bordo.md) | O que foi realmente observado na bancada, com evidências | 📝 vivo |
| 99 | [Referências](99-referencias.md) | Links oficiais e comunidade | ✅ |

## Checklists de progresso

### Fase 0 — Diagnóstico da placa recebida

- [x] Adaptador USB-TTL 3.3 V conectado (`/dev/ttyUSB0`, PL2303)
- [x] Console serial lendo a 115200 8N1
- [x] Inventário da eMMC e do ambiente U-Boot (ver [log de bordo](12-log-de-bordo.md))
- [ ] **Confirmar fonte 5 V/2 A** (suspeita principal do loop de reset)
- [ ] Estabilizar o boot (fonte adequada ou reflash da eMMC)

### Fase 1 — Placa operacional (boot por SD)

- [ ] Fonte 5 V/2 A e cabo confiáveis separados
- [ ] Adaptador USB-TTL 3.3 V disponível
- [ ] Imagem `sd` baixada e checksum conferido
- [ ] microSD gravado e validado
- [ ] Boot com log no console serial capturado
- [ ] Login `pi`/`pi` e `sudo npi-config` acessível

### Fase 2 — Sistema no eMMC

- [x] Imagem `eflasher` gravada no SD
- [x] `eflasher` executado e concluído sem erro (`FLASH_DONE verify=ok`, 2min39s)
- [x] Boot a partir do eMMC sem cartão (LED verde piscando)
- [ ] `df -h` confirmando expansão do rootfs

### Fase 3 — Configuração de produção

- [ ] Hostname, timezone e locale definidos
- [ ] Senhas trocadas; chave SSH instalada
- [ ] Wi-Fi conectado com persistência após reboot
- [ ] `apt` atualizado; pacotes base instalados
- [ ] Backup da imagem do eMMC arquivado
- [ ] Papel do controlador definido (ver [11-decisoes.md](11-decisoes.md))

## Convenções

- Comandos precedidos de `$` rodam como usuário `pi`; `#` como root.
- `sdX` é sempre **placeholder** — confirme o device com `lsblk` antes.
- Referências à wiki oficial usam o formato `[wiki: Título](url)`.
