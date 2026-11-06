# Plano de correções e melhorias de experiência — plataforma Vinha, com foco no Financeiro

Data: 06/11/2026. Situação: proposta. Nada neste documento está implementado, exceto o que estiver marcado como entregue.

## 1. Como a análise foi feita

- Leitura do código do painel (`app/`), da API (`app/api/`), das migrações (`supabase/migrations/`) e dos estilos (`app/*.css`).
- Telas do Financeiro, de Programação e de Comunicação abertas com dados fictícios, em computador (1440 px) e celular (390 px), com o servidor de desenvolvimento e respostas simuladas da API. Não houve acesso ao banco nem ao painel em produção.
- Números citados (quantidade de telas, textos pequenos, erros de lint) foram contados no repositório nesta data.

Escala de esforço: **P** até meio dia, **M** de um a três dias, **G** mais de três dias.

## 2. Diagnóstico

### 2.1 Financeiro — o que mais atrapalha o usuário

| # | Problema | Onde | Impacto |
| --- | --- | --- | --- |
| F1 | Campo de valor só aceita `1234,56`. Digitar `1.234,56` ou `R$ 1.234,56` gera erro. | `app/lib/finance-f1.ts` (`financeCents`), campos `name="amount"` em `FinanceModule`, `FinanceEntryEditor`, `FinanceReceivables`, `FinanceDigital` | Alto: é o campo mais usado e o erro parece culpa do usuário. |
| F2 | No celular, a lista de lançamentos fica cortada: valor, situação e o botão "Abrir lançamento" ficam fora da tela. | `FinanceModule` + `finance-f1.css` / `finance-responsive.css` | Alto: tesoureiro não consegue conferir nem abrir um lançamento pelo celular. |
| F3 | Datas em formato técnico: `2026-11-05`, `2026-06`, "Saldo contábil até 2026-11-06". | Tabelas de lançamentos, contas a receber/pagar, fluxo de caixa, relatórios | Médio: leitura lenta e aparência de sistema inacabado. |
| F4 | 13 abas numa linha só; a última aparece cortada ("Relatórios e") e telas diárias se misturam com cadastros (contas, categorias, centros, fornecedores). | `financeSections` em `app/lib/finance-f1.ts` | Alto: o usuário não encontra a tarefa. |
| F5 | Dois seletores de igreja: o do cabeçalho do painel e o "Igreja / unidade" do Financeiro. | `DashboardApp` (cabeçalho) e `FinanceModule` | Médio: dúvida sobre qual vale. |
| F6 | Contas a receber/pagar não têm ação direta de **Receber** ou **Pagar**. É preciso entrar em "Baixas e parcelas". | `FinanceReceivables` | Alto: a baixa é a operação mais repetida do mês. |
| F7 | Visão geral repete a tabela completa de lançamentos, com 8 filtros abertos, e o fluxo de caixa ocupa uma tela inteira (um bloco alto por mês, com "Previsto R$ 0,00" repetido). | `FinanceModule` (seção `geral`) | Médio: a visão geral não responde rápido "como estamos?". |
| F8 | Oito filtros sempre visíveis em Lançamentos e Contas; não há atalhos como "Vencidas", "Vencem esta semana", "Este mês". | `FinanceModule`, `FinanceReceivables` | Médio. |
| F9 | Novo lançamento começa pela "Frequência" (avulso, repetição, parcelas), escolha rara, antes de Tipo e Valor. Tipo é uma lista em vez de dois botões Entrada/Saída. Conta começa vazia mesmo quando a igreja tem uma conta só. | `FinanceModule` (formulário de lançamento) | Médio: mais cliques em toda operação. |
| F10 | Relatórios abrem com as 19 colunas marcadas; os títulos quebram no meio da palavra ("NÚ MER O"). | `FinanceReports` + `finance-reports.css` | Médio. |
| F11 | Uma resposta incompleta da API derruba a tela inteira da Conciliação (`data?.bank.filter`), sem mensagem amigável. Não há proteção por seção. | `FinanceReconciliation.tsx:26`, `FinanceModule` | Alto em caso de falha: a tela some. |
| F12 | Textos de 8 a 11 px: 36 ocorrências em `finance-digital.css` e 18 em `finance-f1.css`. | CSS do financeiro | Médio: leitura difícil, principalmente para tesoureiros mais velhos. |
| F13 | Cada linha tem botões grandes ("Abrir lançamento", "Baixas e parcelas") e a linha em si não é clicável. | Tabelas do financeiro | Baixo/médio. |

### 2.2 Plataforma — pontos transversais

| # | Problema | Evidência |
| --- | --- | --- |
| P1 | Tipografia mista: títulos em Georgia (serifa) no Financeiro, Eventos e Kids; títulos sem serifa em Programação e Comunicação. | `font:600 … Georgia` em `globals.css`, `events.css`, `permissions.css`, `kids-operations.css` |
| P2 | Textos muito pequenos em vários módulos. | Ocorrências de 8 a 11 px: `globals.css` 46, `finance-digital.css` 36, `event-operations.css` 22, `member-app.css` 18 |
| P3 | Módulos em desenvolvimento (Escalas, Louvor, Famílias e termos, Aplicativo do membro) aparecem no menu como qualquer outro; o aviso só surge depois do clique. | `releaseCatalog` em `app/lib/release-availability.ts` e `DashboardNavigation` |
| P4 | Sem proteção de erro por tela: um erro de renderização derruba o painel inteiro. | Nenhum `ErrorBoundary` envolvendo os módulos em `DashboardApp` |
| P5 | Confirmações com a janela nativa do navegador (`confirm`) em 6 telas, diferente dos diálogos do sistema. | `EventCheckout`, `EventOperationsPanel`, `EventTicketRegistrations`, `EventTicketsAdmin`, `ProgrammingDetail`, `PushCampaigns` |
| P6 | Dívida técnica que dificulta evoluir com segurança: 411 erros e 188 avisos de lint no projeto; erros de tipagem em `app/vinculos/*`; código minificado em uma linha na maior parte dos componentes. | `pnpm lint`, `tsc --noEmit` |
| P7 | Código sem uso: `ProgrammingNavigation.tsx`, `CommunicationHub.tsx`, `MemberAgendaAdmin.tsx`. | Nenhum import |
| P8 | Catálogo de liberação desatualizado (Comunicação e Transmissões não citam push, métricas, banners nem ao vivo automático). | `app/lib/release-availability.ts` |

Já entregue nesta branch: padronização de layout de Comunicação e Ao vivo (Push e Métricas no padrão de página, escala única de texto e botões, tabelas legíveis no celular).

## 3. Princípios para as correções

1. **A tarefa mais comum primeiro.** Lançar, receber, pagar e conferir o saldo precisam de no máximo dois cliques a partir do menu.
2. **Aceitar o que a pessoa digita.** Valores com ou sem `R$`, ponto de milhar e vírgula; datas exibidas em `dd/mm/aaaa`.
3. **Uma igreja selecionada por vez,** a do cabeçalho.
4. **Celular de verdade.** Toda lista vira cartão legível com o valor e a ação principal visíveis, sem rolagem lateral.
5. **Falha localizada.** Erro numa seção mostra mensagem e botão "Tentar de novo"; o resto do painel continua funcionando.
6. **Uma escala visual.** Texto mínimo de 12 px, corpo de 14 px, botões de 44 px no celular, mesma família de títulos em todos os módulos.
7. **Sem regressão de segurança.** Nenhuma mudança afrouxa validação no servidor, permissões ou auditoria; o servidor continua sendo a fonte da verdade.

## 4. Estrutura de execução

### Fase 0 — Correções críticas (1 PR, esforço M)

**Entregue em 06/11/2026.** Valor aceita `R$ 1.234,56`, `1.234,56`, `1234,56`, `1234` e `12.50`, com formatação ao sair do campo, no navegador e no servidor (`financeMoneyInput` e `financeMoneyField` em `app/lib/finance-f1.ts`), nos lançamentos, edição, contas a receber e pagar (incluindo juros, multa, desconto e taxa), recebimentos digitais, orçamento e filtros de relatório. Lançamentos e Contas a receber/pagar viram cartões até 760 px. `SectionErrorBoundary` protege cada módulo do painel e as seções do Financeiro; a Conciliação deixou de cair com resposta incompleta. Verificado no navegador com dados fictícios e com a suíte de testes (641/641).

| Item | Solução | Aceite |
| --- | --- | --- |
| F1 Valor em reais | Normalizar a entrada antes de validar, no cliente e no servidor: remover `R$` e espaços, aceitar ponto de milhar válido (`1.234,56`) e vírgula decimal. Rejeitar formatos ambíguos (`1.23,4`). Campo com máscara ao sair do foco (`1.234,56`). | `R$ 1.234,56`, `1.234,56`, `1234,56` e `1234` resultam no mesmo valor; testes unitários em `scripts/` cobrindo casos válidos e inválidos. |
| F2 Lista no celular | Em telas até 760 px, transformar lançamentos e contas em cartões: descrição, valor (com cor de entrada/saída), vencimento, situação e ação principal; demais dados num "ver mais". | Captura a 390 px mostra valor, situação e ação de todos os itens, sem rolagem lateral. |
| F11 / P4 Proteção de erro | `ErrorBoundary` por módulo no `DashboardApp` e por seção no Financeiro, com mensagem e "Tentar de novo". Corrigir acessos sem proteção (`data?.bank.filter`). | Resposta incompleta da API mostra aviso na seção; menu e cabeçalho continuam funcionando. |

### Fase 1 — Financeiro no dia a dia (2 a 3 PRs, esforço M cada)

| Item | Solução | Aceite |
| --- | --- | --- |
| F4 Navegação | Separar as 13 abas em dois grupos. **Operação:** Visão geral, Lançamentos, Contas a receber, Contas a pagar, Conciliação, Fechamento, Relatórios. **Cadastros:** Contas bancárias e caixas, Categorias, Centros de custo, Fornecedores, Contas recebedoras, Recebimentos digitais. Abas roláveis com indicação visual no celular. Rotas atuais preservadas. | Nenhuma aba cortada a 1440 px; links antigos (`secao=…`) continuam abrindo a mesma tela. |
| F5 Um seletor de igreja | Financeiro passa a seguir a igreja do cabeçalho. O seletor interno só aparece para quem consolida várias igrejas, rotulado "Consolidar igrejas". | Trocar a igreja no cabeçalho atualiza o Financeiro; consolidação continua disponível a quem tem acesso. |
| F6 Receber/Pagar direto | Botão **Receber** ou **Pagar** em cada título em aberto, abrindo a baixa já preenchida com valor em aberto, data de hoje e a conta do título. Juros, multa e desconto ficam recolhidos em "Ajustar valores". | Baixa total em 2 cliques; baixa parcial continua possível; histórico e auditoria iguais aos de hoje. |
| F3 Datas | Utilitário único de exibição (`dd/mm/aaaa`; meses como `jun/2026`) usado em todas as telas do financeiro e nos relatórios na tela. Exportações CSV mantêm o formato atual, para não quebrar planilhas. | Nenhuma data `aaaa-mm-dd` visível nas telas do financeiro. |
| F9 Novo lançamento | Ordem: Entrada/Saída (dois botões grandes), Valor, Descrição, Conta (preenchida quando só existe uma, ou com a última usada), Categoria, Data, "Já foi pago/recebido". Frequência e centro de custo em "Mais opções". | Lançamento simples preenchido em menos de 30 segundos num teste com usuário. |
| F8 Atalhos de filtro | Botões rápidos: Vencidas, Vencem em 7 dias, Este mês, Mês passado. Filtros detalhados recolhidos em "Mais filtros", com contador dos filtros ativos. | Cada atalho aplica o filtro sem abrir o painel de filtros. |

### Fase 2 — Visão geral e relatórios (2 PRs, esforço M)

| Item | Solução | Aceite |
| --- | --- | --- |
| F7 Visão geral | Painel com: saldo por conta, entradas × saídas do mês, contas vencidas e as que vencem nos próximos 7 dias (com Receber/Pagar), gráfico compacto de 6 meses e atalho para Lançamentos no lugar da tabela completa. | A visão geral cabe em uma tela e meia a 1440 px; os números batem com Lançamentos para o mesmo período. |
| F10 Relatórios | Modelos prontos de colunas (Resumo, Prestação de contas, Completo); "Resumo" como padrão. Títulos de coluna sem quebra no meio da palavra; tabela larga com rolagem horizontal e primeira coluna fixa. | Relatório padrão com no máximo 8 colunas; exportações continuam com todas as colunas escolhidas. |
| F13 Linhas clicáveis | A linha inteira abre o lançamento; os botões ficam menores, num menu "⋯" com as ações secundárias. | Navegação por teclado e leitor de tela preservada (linha com foco e nome acessível). |
| F12 Textos pequenos | Revisar `finance-digital.css`, `finance-f1.css`, `finance-reports.css` e `finance-providers.css` com o mínimo de 12 px e o corpo de 14 px. | Nenhum texto do financeiro abaixo de 12 px. |

### Fase 3 — Plataforma (contínua, PRs pequenos)

| Item | Solução | Esforço |
| --- | --- | --- |
| P1 Tipografia | Definir uma família de títulos (manter Georgia como marca **ou** sem serifa em tudo) e aplicar via tokens em `shared/design-tokens.ts` / `app/vinha-tokens.css`. | M |
| P2 Escala de texto | Mesmo mínimo de 12 px em `globals.css`, `event-operations.css`, `member-app.css` e demais módulos, priorizando as telas mais usadas. | M |
| P3 Menu honesto | Selo "Em breve" nos módulos em desenvolvimento, ou ocultá-los do menu por configuração revisada. | P |
| P5 Confirmações | Substituir `confirm()` pelo diálogo padrão (`ProgrammingModal` / `Dialog`) com texto da consequência. | P |
| P6 Dívida técnica | Expandir o Prettier (`pnpm format`) por pasta a cada PR; zerar os erros de tipagem de `app/vinculos/*`; impedir que o número de erros de lint aumente, como já é feito com `check:buttons`. | Contínuo |
| P7 / P8 Limpeza | Remover código sem uso; atualizar o catálogo de liberação conforme a homologação. | P |
| Pendências de Programação e Comunicação | Banners e arquivos próprios no app; agendamento e saída do ar de avisos; categorias no app; vínculo de transmissão com evento e gravação no catálogo (detalhes na análise de 06/11/2026). | M a G |

## 5. Ordem recomendada e dependências

1. **Fase 0** primeiro: elimina os bloqueios (valor recusado, celular cortado, tela que some).
2. **Fase 1**: F4 e F5 antes de F6, porque a nova navegação define onde ficam os botões Receber/Pagar. F3 pode correr em paralelo.
3. **Fase 2** depois que a Fase 1 estiver em uso, com retorno de pelo menos um tesoureiro.
4. **Fase 3** em PRs pequenos, intercalados, sem bloquear as fases do Financeiro.

## 6. Como validar cada entrega

- Testes automatizados existentes (`pnpm test:release`, `pnpm test:security`, `scripts/*.test.mjs` do financeiro, `pnpm db:test` com o banco local) e build (`pnpm build:vercel`).
- Novos testes unitários para a leitura de valores (F1) e o formato de datas (F3).
- Capturas a 1440 px e 390 px de cada tela alterada, anexadas ao PR.
- Conferência com um usuário real do financeiro: lançar uma entrada, uma saída, receber um título e gerar a prestação de contas do mês, cronometrando o tempo antes e depois.
- Nenhuma mudança em regra de cálculo, permissão ou auditoria sem teste de banco correspondente.
