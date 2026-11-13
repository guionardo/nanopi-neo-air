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
| MAC Wi-Fi (`wlan0`) | a obter quando o boot estabilizar |
| IP em produção | |
| Hostname | `ctl-nanopi` (sugerido) |
| Imagem gravada (nome do arquivo) | desconhecida — eMMC veio com sistema de origem não identificada |
| Data da instalação | anterior a 2026-11-13 |
| SHA-256 da imagem | |
| Kernel instalado | 4.14.111 (armhf) |
| U-Boot | 2017.11 (15/06/2021), board `nanopi-neo-air`, `cpu=h3` |
| Userland na eMMC | Ubuntu 24.04 (systemd 255.4-1ubuntu8.2) |
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

## Pendências

O que ainda precisa de decisão. Atualizar conforme for resolvendo.

| # | Pendência | Impacto | Bloqueia? |
| --- | --- | --- | --- |
| P-01 | **Papel do controlador** (sensores, rede, mídia, servidor?) | define pacotes, portas, GPIOs, consumo | **sim** para a fase 3 |
| P-02 | Definir o mapa de GPIOs da aplicação (quais pinos, com pull-up?) | evita conflito com funções de boot | não |
| P-03 | Escolher método de acesso remoto (VPN? WireGuard? Tailscale?) | exposição na rede | não |
| P-04 | Definir política de backup (rede vs USB; frequência) | recuperação após falha | não |
| P-05 | Gabinete/dissipação: case 3D ou caixa comercial? | temperatura em carga | não |
| P-06 | Fonte definitiva (marca/modelo) e proteção contra queda | estabilidade | não |
| P-07 | Medir consumo real em idle e em carga | dimensionamento e autonomia | não |
| P-08 | Definir se haverá UPS/mini-no-break | continuidade | não |

### Perguntas abertas sobre a aplicação

Estas respostas mudam o projeto — vale escrever antes de instalar qualquer coisa:

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
