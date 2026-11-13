# 05 — Gravar o SO no eMMC

Com a eMMC virgem, a placa só inicia pelo microSD. Este passo usa o **eflasher**:
um sistema que roda a partir do cartão e escreve a imagem escolhida na eMMC.

Resultado esperado: a placa passa a iniciar **sem cartão**, com o sistema em
memória interna (mais rápido e mais resistente a vibração).

## Como o eflasher funciona

```
microSD com eflasher  →  placa inicia o eflasher  →  você escolhe a imagem
      →  eflasher grava na eMMC  →  desliga  →  remove SD  →  inicia da eMMC
```

O eflasher **não** é o sistema final: é um instalador temporário. Você vai usar
o cartão duas vezes, com imagens diferentes.

## Passo 1 — Baixar a imagem eflasher

No diretório oficial (`01_Official images`), pegue a linha `eflasher`:

| Arquivo | Observação |
| --- | --- |
| `h3-eflasher-friendlycore-jammy-4.14-armhf-YYYYMMDD.img.gz` | Instala o FriendlyCore 22.04 na eMMC |
| `h3-eflasher-multiple-os-YYYYMMDD-25g.img.gz` | Várias imagens no mesmo cartão; **desabilita o flash automático** e exige seleção manual |

Verifique a integridade como em [02](02-preparo-imagem.md):

```bash
gzip -t h3-eflasher-*.img.gz && echo OK
```

## Passo 2 — Gravar o eflasher no microSD

Cartão de **≥ 4 GB** (o eflasher é pequeno). Processo idêntico ao
[03](03-gravacao-sd.md):

```bash
sudo ./scripts/flash-sd.sh ~/nanopi/images/h3-eflasher-friendlycore-jammy-*.img.gz /dev/sdX
```

**Guarde o cartão com a imagem `sd`** (a que você usou na etapa 04). Ele será
útil se algo der errado depois.

## Passo 3 — Iniciar o eflasher

1. Insira o cartão com o eflasher.
2. Conecte o console serial (UART0, 115200) — **obrigatório sem monitor**.
3. Energize com 5 V/2 A.

Sinais de boot do eflasher:

- LEDs: um aceso fixo e outro piscando (na V1.0: verde aceso, azul piscando).
- Console serial mostra o menu do eflasher ou um shell.

> O eflasher é baseado em Debian/Ubuntu minimal e pode levar 20–40 s até exibir
> o menu. Não desligue nesse intervalo.

## Passo 4 — Escolher a imagem e iniciar a gravação

Se o menu não aparecer sozinho, abra-o:

```bash
# login: root / fa
eflasher
```

Menu (resumido):

```
1) FriendlyCore (Ubuntu Core 22.04)   [4.14 armhf]   --> eMMC
2) FriendlyCore (Ubuntu Core 20.04)   [4.14 armhf]   --> eMMC
3) Debian Core 13                     [4.14 armhf]   --> eMMC
...
```

Digite o número da imagem desejada (ex.: `1`), confirme com `yes` quando pedido.

### Aviso obrigatório antes de confirmar

> **A eMMC será totalmente apagada.** Qualquer dado anterior é perdido.
> Se a placa já tem um sistema em uso, faça backup antes (ver
> [09-manutencao.md](09-manutencao.md)).

## Passo 5 — Aguardar

| Etapa | Tempo típico | Sinal |
| --- | --- | --- |
| Preparação | 10–30 s | log de criação de partições |
| Escrita | **5–15 min** | LED piscando; progresso no console |
| Verificação | 1–3 min | log de checagem |
| Conclusão | — | mensagem de sucesso / "please power off" |

**Não interrompa a energia.** Desligar no meio da escrita deixa a eMMC em estado
inconsistente e a placa pode não iniciar por nenhum meio até você refazer o
processo com o cartão.

## Passo 6 — Primeiro boot pela eMMC

Quando o log indicar conclusão:

```bash
sudo poweroff        # ou: sync && sudo shutdown -h now
```

1. Aguarde o LED STAT apagar / a placa parar.
2. **Remova o microSD.** Este passo é o mais esquecido: com o cartão presente a
   placa vai iniciar pelo cartão de novo.
3. Energize.

Confirme que está na eMMC:

```bash
lsblk
```

Esperado: um device `mmcblk2` (ou `mmcblk0` dependendo do kernel) com as
partições do sistema, e **sem** `mmcblk1`/`mmcblk0` correspondente ao cartão.

```bash
findmnt -no SOURCE /
# deve apontar para uma partição da eMMC, ex: /dev/mmcblk2p2
```

Confirme também a expansão do rootfs:

```bash
df -h /
# ~7 GB disponíveis em uma eMMC de 8 GB
```

Se o sistema não iniciar sem cartão, veja
[troubleshooting → eMMC](10-troubleshooting.md#emmc-não-inicia-placa-morta-sem-cartão).

## Passo 7 — Reconfigurar o que é específico do eMMC

O sistema na eMMC é uma instalação nova, não um clone: senhas voltam ao padrão
(`pi`/`pi`, `root`/`fa`), Wi-Fi precisa ser reconfigurado e hostname volta ao
padrão.

Repita, agora na eMMC:

1. `sudo npi-config` → senha, hostname, timezone, SSH
2. Wi-Fi ([07](07-rede.md))
3. Pacotes e chaves SSH ([06](06-configuracao-base.md))
4. **Backup da eMMC** assim que o sistema estiver do jeito que você quer
   ([09](09-manutencao.md)) — antes de instalar qualquer coisa arriscada

## Alternativa: cartão como sistema definitivo

Se preferir manter o SO no cartão (eMMC intacta como reserva):

- pule este documento;
- use a imagem `sd` direto;
- escreva pouco no cartão (log em RAM, `noatime`), porque cartão desgasta;
- tenha sempre uma imagem gravada de reserva.

Para um controlador que fica ligado 24/7, a eMMC é a escolha mais robusta.
