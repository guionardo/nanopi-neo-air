# 11 — Decisões e pendências

Registro curto do "por quê" de cada escolha. O objetivo não é burocracia: é não
repetir a mesma pesquisa meses depois, nem esquecer o que estava pendente.

Formato: contexto → decisão → consequência. Uma entrada por decisão.

---

## D-001 — Sistema operacional: FriendlyCore (Ubuntu Core), kernel 4.14, armhf

**Data:** 2026-11-13
**Status:** aceita

**Contexto:** a placa é H3 (ARMv7 32 bits), 512 MB. A FriendlyElec publica
FriendlyCore, Debian Core, FriendlyWrt e imagens legadas com kernel 3.4.

**Decisão:** usar FriendlyCore (mais recente, Ubuntu Core 22.04 "jammy") com
kernel 4.14 mainline, 32 bits.

**Motivos:**

- é a distribuição que a FriendlyElec mantém e testa na NEO Air;
- kernel 4.14 é mainline: estável e sem o superaquecimento do BSP 3.4;
- sem X/desktop: menos RAM e menos superfície de ataque;
- traz `npi-config`, NetworkManager, bluez e `RPi.GPIO_NP` já integrados.

**Consequências:**

- não haverá aceleração VPU/GPU (irrelevante para controle);
- apenas pacotes e imagens Docker `arm32v7`;
- atualizar de distro no futuro provavelmente exigirá reinstalação, não
  `do-release-upgrade`.

---

## D-002 — Sistema no eMMC, não no cartão SD

**Data:** 2026-11-13
**Status:** aceita

**Contexto:** a placa tem 8 GB de eMMC e slot microSD.

**Decisão:** instalar o sistema na eMMC via eflasher; manter um cartão de
recuperação.

**Motivos:** eMMC é mais rápida e robusta que cartão (sem contato mecânico
sujeito a vibração/oxidação), e libera o slot para o cartão de resgate.

**Consequências:** reinstalar exige cartão + eflasher; backup da eMMC passa a ser
obrigatório antes de mudanças arriscadas.

---

## D-003 — Documentação em Markdown, em português, dentro do repositório

**Data:** 2026-11-13
**Status:** aceita

**Decisão:** `docs/` com arquivos numerados + índice com checklists; linguagem
operacional (comando → resultado esperado → o que fazer se falhar).

**Motivos:** versionável, revisável em diff, funciona offline e não depende de
wiki externa (a wiki da FriendlyElec é a fonte, mas não é estável nem localizada).

---

## D-004 — Console serial como pré-requisito obrigatório

**Data:** 2026-11-13
**Status:** aceita

**Contexto:** a NEO Air não tem HDMI nem Ethernet.

**Decisão:** nenhuma etapa de gravação/instalação é executada sem adaptador
USB-TTL 3.3 V conectado e log sendo gravado.

**Consequências:** custo de ~R$ 20 num adaptador evita horas de tentativa e erro;
todo boot relevante deixa um arquivo de log como evidência.

---

## Registro da placa

Preencher na primeira vez que a placa bootar.

| Campo | Valor |
| --- | --- |
| Versão do hardware | a confirmar (LEDs: ver [00](00-hardware.md)) |
| MAC Wi-Fi (`wlan0`) | `02:00:00:00:00:01` (fixado no NVRAM; antes era aleatório por boot) |
| IP em produção | `192.168.1.50` (DHCP; reservar lease de `02:00:00:00:00:01` no roteador) |
| Hostname | `ctl-nanopi` |
| Imagem gravada (nome do arquivo) | `debian-bookworm-core` 20250402 (payload do eflasher, via `flash-emmc-headless.sh`) |
| Data da instalação | 2026-11-13 (flash) · 2026-11-14 (provisão Wi-Fi) |
| SHA-256 da imagem | |
| Kernel instalado | 4.14.111 (armhf) |
| U-Boot | 2017.11 (15/06/2021), board `nanopi-neo-air`, `cpu=h3` |
| Userland na eMMC | Debian 12 bookworm, NetworkManager, rootfs em overlayfs |
| Local físico / responsável | |
| Nº de série da etiqueta | |

### D-005 — Estado real da placa difere do pressuposto inicial

**Data:** 2026-11-13
**Status:** aceita (corrige o planejamento)

**Contexto:** o setup partiu de "eMMC virgem, boot apenas por SD". Ao conectar o
console serial, observou-se que a placa **já inicia pela eMMC**, com ambiente
U-Boot corrompido (`bad CRC, using default environment`) e **loop de reset a
cada ~4,5 s** durante o coldplug do udev no initramfs.

**Decisão:** tratar a eMMC como **conteúdo não confiável** e não depender dela.
Antes de qualquer serviço, estabilizar o boot — primeiro testando fonte 5 V/2 A;
persistindo, refazer o eflasher com imagem oficial.

**Consequências:**

- a etapa 05 (gravação do eMMC) passa a ser **recuperação**, não instalação limpa;
- o cartão SD deixa de ser opcional: é o caminho de reinstalação;
- evidências e comandos ficam em [12-log-de-bordo.md](12-log-de-bordo.md);
- nenhuma credencial do sistema atual é conhecida — não há como assumir `pi`/`pi`.

### D-006 — Wi-Fi: firmware e NVRAM versionados no repositório, com procedência

**Data:** 2026-11-14
**Status:** aceita

**Contexto:** o `brcmfmac` precisa de dois arquivos. O `.bin` é firmware genérico
do chip BCM43430 (serve de qualquer origem). O `.txt` é o **NVRAM**, com a
calibração de rádio do **módulo** — e usar o NVRAM de outro módulo BCM43430 faz
o rádio inicializar e não varrer nada (`Failed to initiate sched scan` em loop,
nenhum `Trying to associate`).

**Decisão:** manter `firmware/brcmfmac43430-sdio.{bin,txt}` no git, com
`firmware/README.md` explicando a origem, e um script reprodutível de extração
([`scripts/extract-firmware.sh`](../scripts/extract-firmware.sh)) a partir da
imagem oficial da FriendlyElec, que é git-ignored por tamanho.

**Consequências:**

- instalar/atualizar Wi-Fi passa a ser `wifi-inject.sh ... ./firmware`, que
  **sobrescreve** o que houver (guardando `.bak`);
- o repositório deixa de depender de "lembrar de onde veio o arquivo";
- arquivos binários pequenos e insubstituíveis ficam versionados — 400 KB é
  aceitável para remover uma classe inteira de erro silencioso.

### D-007 — Papel do controlador: host headless acessível por SSH

**Data:** 2026-11-14
**Status:** aceita — fecha a pendência P-01

**Contexto:** a placa ficou operacional em 2026-11-14 (eMMC bootando sem cartão,
Wi-Fi com NVRAM correto, SSH por chave, hostname `ctl-nanopi`). Não existe ainda
uma aplicação definida: o uso imediato é ter uma máquina Linux sempre ligada na
rede local, acessível por SSH.

**Decisão:** o papel é **host Linux headless com acesso SSH na LAN**. Nada de
serviço exposto para a internet, nada de GPIO em uso. Toda mudança futura deve
preservar quatro propriedades:

1. boot autônomo pela eMMC, sem cartão e sem console;
2. reconexão automática do Wi-Fi (NetworkManager, perfil `minha-rede`);
3. acesso por chave SSH (senha como alternativa local);
4. recuperação pelo cartão SD (canal oficial de conserto).

**Consequências:**

- não é preciso decidir portas nem GPIOs agora — a [D-002](#d-002--sistema-no-emmc-não-no-cartão-sd)
  já garante o armazenamento, e o resto fica disponível;
- segurança passa a ser o eixo principal: atualizações, senha forte, chave SSH,
  e **só a porta 22 aberta** (mais NTP/UDP 123);
- P-03 (VPN) e P-08 (UPS) continuam abertas, mas agora são as únicas que mudam o
  uso real de "máquina de bancada" para "máquina de produção";
- o display LCD ([B-001](13-backlog.md#b-001--display-lcd-nokia-5110-84x48))
  passa a ser o único periférico planejado, e o conteúdo dele já foi definido:
  CPU, memória, uptime e IP.

## D-008 · Sistema final em Debian 13 (trixie)

**Data:** 2026-11-15 · **Status:** aceita (validação em andamento)

**Contexto.** A placa subiu com Debian 12 (bookworm, payload de 2025-04-02) e
foi toda configurada nele. Em 2026-03-30 o fabricante publicou os payloads
`h3-eflasher-debian-trixie-core-4.14-armhf` e
`h3-sd-debian-trixie-core-4.14-armhf`, com o mesmo kernel de vendor (4.14.111).

**Decisão.** O alvo do instalador passa a ser **Debian 13 (trixie)**, payload
`debian-trixie-core`. O Debian 12 fica como instalação histórica — é o sistema
descrito no [log de bordo](12-log-de-bordo.md) e no artigo.

**Consequências.**

- `scripts/flash-emmc-headless.sh` deixa de ter caminho e offsets fixos: lê o
  `autoStart` do `eflasher.conf` e os offsets do `partmap.txt`, então serve
  para qualquer imagem eflasher (bookworm, trixie, ubuntu-noble…);
- o kernel continua 4.14.111 (payload do fabricante), logo tudo o que foi
  aprendido sobre NVRAM do AP6212, SPI e overlayfs continua valendo;
- nada é herdado da instalação 12 (senhas, pacotes, perfis): a eMMC é regravada
  do zero e provisionada pelo instalador;
- o artigo precisa deixar claro que bookworm foi o ponto de partida, não o
  destino.

## Pendências

O que ainda precisa de decisão. Atualizar conforme for resolvendo.

| # | Pendência | Impacto | Bloqueia? |
| --- | --- | --- | --- |
| P-01 | ~~Papel do controlador~~ — **resolvida em [D-007](#d-007--papel-do-controlador-host-headless-acessível-por-ssh)**: host headless via SSH | — | não |
| P-02 | Definir o mapa de GPIOs da aplicação (quais pinos, com pull-up?) | evita conflito com funções de boot | não |
| P-03 | Escolher método de acesso remoto (VPN? WireGuard? Tailscale?) | exposição na rede | não |
| P-04 | Definir política de backup (rede vs USB; frequência) | recuperação após falha | não |
| P-05 | Gabinete/dissipação: case 3D ou caixa comercial? | temperatura em carga | não |
| P-06 | Fonte definitiva (marca/modelo) e proteção contra queda | estabilidade | não |
| P-07 | Medir consumo real em idle e em carga | dimensionamento e autonomia | não |
| P-08 | Definir se haverá UPS/mini-no-break | continuidade | não |

### Perguntas abertas sobre a aplicação

Arquivadas pela [D-007](#d-007--papel-do-controlador-host-headless-acessível-por-ssh)
(não há aplicação: o papel é host SSH). Ficam registradas para quando houver:

1. O controlador precisa funcionar **offline**? (define dependência de NTP/DNS)
2. Ele aciona cargas elétricas? Quantas, que tensão/corrente?
3. Há requisito de **tempo de resposta** (< 100 ms? segundos?)?
4. Ele precisa **guardar histórico**? Por quanto tempo? (eMMC tem limite)
5. Quem acessa a interface? Só na rede local ou remotamente?
6. Ele precisa sobreviver a **queda de energia** sem corromper? (define read-only rootfs)
7. Existe prazo/entrega que force uma solução mais simples?

## Alternativas descartadas

| Opção | Por que não |
| --- | --- |
| Kernel 3.4 / BSP Allwinner | esquenta muito, pacotes antigos, sem manutenção |
| OpenWrt / FriendlyWrt | excelente como roteador, pobre como host de aplicação |
| Armbian | suporte comunitário à NEO Air é irregular; menos reproduzível |
| arm64 | H3 é ARMv7, não existe imagem oficial 64 bits |
| Android | sem HDMI, caso de uso não se aplica |
