# Contrato entre a plataforma e os aplicativos

Base criada na Etapa 3 · PR 1. Tudo que a plataforma (painel e API) e os aplicativos (app de cada ministério e Vinha Equipe) precisam combinar fica em `shared/`. Quando uma regra muda ali, a web e os apps passam a usar a regra nova juntos, e o TypeScript acusa quem ficou para trás.

## O que fica em `shared/`

| Arquivo | Para que serve |
|---|---|
| `shared/contract/errors.ts` | Formato único de erro: `{error, fields?, code?}`. `fields` aponta o campo a corrigir (`title`, `items.0.cpf`). `ApiError` é o erro que os clientes recebem. |
| `shared/contract/push.ts` | Regras de campanhas de push (título, texto, link, público, agendamento) usadas pelo formulário do painel, pelo Vinha Equipe e por `/api/push/campaigns`. |
| `shared/contract/checkout.ts` | Regras do comprador e dos participantes no checkout com ou sem cadastro (`/api/event-orders`). |
| `shared/contract/staff.ts` | Formatos que o Vinha Equipe lê: ministério, igreja, funções de equipe, check-in por QR. |
| `shared/contract/apps.ts` | Aperto de mão: cabeçalho `x-vinha-client`, versões mínimas e `/api/app/compat`. |
| `shared/design-tokens.ts` | Cores, raios e tipografia da Vinha. Gera `app/vinha-tokens.css` (tema do Tailwind) e alimenta `staff-app/src/theme.ts`. |

O banco continua repetindo todas as regras. O contrato só responde antes e indica o campo, sem substituir as verificações do Supabase.

## Regras para quem desenvolve

1. **Mudou uma regra de formulário?** Altere em `shared/contract`, não no componente. O servidor e os apps passam a usar a mesma mensagem.
2. **Mudou uma cor?** Altere `shared/design-tokens.ts` e rode `pnpm run tokens`. O CI falha se o CSS estiver desatualizado ou se algum contraste ficar abaixo do mínimo AA.
3. **Mudança na API que um app antigo não entende?** Suba `contractVersion` e o `minimum` do app em `shared/contract/apps.ts`. Os apps consultam `/api/app/compat` ao abrir e pedem atualização.
4. **Nova versão de um app:** a versão vem do `package.json` do app. Atualize `latest` em `apps.ts` para avisar quem está numa versão anterior.
5. **Formatação:** `pnpm run format` usa o Prettier (`.prettierrc.json`) nas pastas novas e no código compartilhado. A lista de pastas cresce a cada PR da Etapa 3, para não gerar conflito com trabalho em andamento.

## Como os apps acessam `shared/`

Os dois `metro.config.cjs` incluem `../shared` e resolvem os pacotes importados por ele (React, zod) a partir da pasta do próprio app. Assim o build do EAS, que instala só a pasta do app, funciona igual ao build local. O `zod` fica fixo em 4.4.3 na raiz e nos dois apps.

## Permissões finas e fuso horário (Etapa 3 · PR 2)

- **Concessões por igreja** para secretaria e liderança: `agenda` (criar e editar eventos), `checkin` (entrada por QR, lista e inscritos), `publishing` (avisos e publicações) e `push`. Elas ficam em `private.staff_grants` e são gerenciadas em Comunicação → Equipe e fuso horário (`/api/staff-access`). As concessões só acrescentam acesso: responsáveis, administração e pastores continuam com tudo, e a regra antiga de autonomia de comunicação continua valendo.
- **O que cada pessoa pode fazer:** `GET /api/staff-access?action=mine` responde, por igreja, `{agenda, checkin, publishing, push, timezone}`. O Vinha Equipe mostra só as ações liberadas.
- **Fuso por ministério e por igreja:** em `private.church_timezones`, lido por `private.unit_timezone(unit)`, com Brasília como padrão. Programação (criação, edição, calendário e retirada de vendas), métricas de evento, filtro de aniversário e aniversários automáticos usam o fuso da igreja. As leituras de `/api/programming` respondem `timezone`, e o painel mostra e edita os horários nesse fuso (`shared/timezone.ts`). Kids, células e financeiro continuam em Brasília até as próximas etapas.
- A configuração financeira dos eventos (contas recebedoras, finalidades e conferência de pagamentos) continua exclusiva da administração.

## Kids: estações e fuso (Etapa 3 · PR 3)

- O contrato do Kids (`shared/contract/kids.ts`) é o mesmo para o painel e o Vinha Equipe. O `app/lib/kids-operations.ts` apenas o reexporta.
- **Estação de recepção:** tablet ou celular registrado pela coordenação do Kids ou pela supervisão de uma sessão (`/api/kids-station`: `register`, `heartbeat`, `revoke`, lista no GET). Desativar uma estação apaga a sessão de login daquele aparelho, e o Kids passa a recusar o token restante (`private.session_alive`). O painel mostra as estações em Kids → Estações de recepção.
- O Kids do painel, as respostas da API e as funções do banco (entrada, retirada, relatórios e idade) usam o fuso da igreja.
- `staff_access('mine')` informa `kids` e `kidsStations` por igreja. O Vinha Equipe já tem as chamadas prontas em `staff-app/src/kids.ts`; as telas entram na próxima etapa do app.
- Retirada continua exigindo internet e conferência do adulto autorizado. Não há retirada offline.

## Endereços e layout (Etapa 3 · PR 4)

- Programação e Comunicação têm endereços próprios, como `/painel/programacao/agenda` e `/painel/comunicacao/push` (`shared/dashboard-route.ts`). Links antigos com `?pagina=eventos&secao=…` continuam funcionando e são reescritos para o novo endereço. Os outros módulos seguem com `?pagina=`.
- Abas no topo dos dois módulos (`app/ModuleTabs.tsx`): cada aba é um link real, que pode ser compartilhado ou salvo nos favoritos.
- As cores base do painel (`--green`, `--ink`, `--muted`, `--line` e `--cream`) e as das telas de Programação e Comunicação vêm dos tokens da Vinha. O cinza secundário ficou mais escuro para atingir o contraste AA.

## Recorrência e agenda em calendários (Etapa 4 · PR 1)

- **Recorrência:** diária, semanal, mensal ou anual. Termina após N encontros (até 120), em uma data ou "sem término" (cria as datas dos próximos 12 meses, até 120). A regra está em `shared/recurrence.ts` e é repetida no banco por `private.programming_repeat_count`. Mês sem o dia escolhido usa o último dia (31/01 → 28/02).
- **Assinatura da agenda:** link secreto por igreja (`/api/agenda/feed?t=…`, também como `webcal://`), criado, trocado ou desativado em Programação → Agenda da igreja por quem gerencia a agenda. Entram só eventos publicados dos últimos 30 dias e dos próximos 12 meses; eventos cancelados aparecem como cancelados.
- **Adicionar ao calendário:** botão na página pública do evento (`/api/agenda/event?id=…`). A página pública passou a mostrar os horários no fuso da igreja.

## Avisos com texto formatado e banco de imagens (Etapa 4 · PR 2)

- **Texto dos avisos:** Markdown simples guardado como texto (`shared/rich-text.ts`): `## título`, `**negrito**`, `*itálico*`, `[link](https://…)`, listas, `> destaque` e `![descrição](img:<id>)`. Avisos antigos, em texto puro, continuam iguais. Painel (`app/RichText.tsx`) e app (`android-app/src/RichText.tsx`) montam os blocos com componentes próprios, sem HTML. Links só `https`, `mailto` e `tel`.
- **Banco de imagens** (`/api/publishing-images`): JPEG, PNG ou WebP de até 5 MB, identificados pelo conteúdo do arquivo e guardados em bucket privado. A imagem é servida ao público só se estiver em um aviso publicado do mesmo ministério; quem publica naquela igreja também vê a prévia. Arquivar tira a imagem do banco, mas os avisos já publicados continuam mostrando.
- O editor de avisos tem botões de formatação, prévia, inserir imagem (até 10 por aviso) e "Escolher do banco de imagens" para a capa de avisos e banners.
