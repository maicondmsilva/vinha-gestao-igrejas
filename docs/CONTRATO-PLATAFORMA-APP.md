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
