# Análise completa do módulo Financeiro — experiência, lógica e layout

Data: 07/11/2026. Base: código da `main` após o PR #100 (as Fases 0 e 1 já estão em produção). Telas abertas com dados fictícios em computador (1440 px) e celular (390 px). Não houve acesso ao banco nem ao painel de produção.

Objetivo: deixar o Financeiro simples e objetivo para o tesoureiro, sem afrouxar validação, permissões ou auditoria.

## 1. Resumo — o que mais importa

| # | Achado | Impacto | Seção |
| --- | --- | --- | --- |
| 1 | Erros do servidor viram uma frase genérica ("Revise os dados, os cadastros ativos e o período financeiro"), mesmo quando o banco sabe o motivo exato (mês fechado, conta inativa, categoria inválida). | Alto | 4.3 |
| 2 | Nenhum campo é destacado quando falta algo; o aviso é o balão do navegador ou uma mensagem no topo da janela. Obrigatórios e opcionais não são marcados de forma consistente. | Alto | 4.1, 4.2 |
| 3 | Fechar uma janela (X ou Esc) descarta o que foi digitado, sem perguntar. | Alto | 4.4 |
| 4 | Abrangência não permite escolher outra igreja sem trocar a igreja do topo. | Alto | 3 |
| 5 | Juros e multa entram na mesma categoria do título (ex.: juros do aluguel viram "Aluguel"), distorcendo os relatórios por categoria. | Médio/alto | 2.3 |
| 6 | Totais de Recebimentos digitais (bruto, taxas, devoluções, líquido) somam só a página exibida (até 100 pagamentos), não o período. | Médio/alto | 2.2 |
| 7 | Nomes de pessoas, fornecedores, contas e subcategorias aparecem nas tabelas com 10 px e cor clara; base da tabela em 12 px. | Médio | 7 |
| 8 | Textos longos e técnicos em quase todas as telas (OFX, FITID, Webhooks, escopo, contabilização, "operação F5"). | Médio | 5 |
| 9 | Filtro de período (De/Até) aparece em telas onde não vale (Categorias, Contas, Fornecedores, Fechamento). | Médio | 6 |
| 10 | Datas técnicas restantes em Conciliação e Fechamento (`2026-10-31`); edição de lançamento mostra `3520,00` sem ponto de milhar. | Baixo/médio | 6 |

## 2. Lógica financeira — taxas, juros, multa e devoluções

### 2.1 Recebimentos digitais (Pix/cartão pelo provedor) — **correto**

Fluxo conferido em `supabase/migrations/20261021093022_finance_f4_digital_receipts.sql` (`digital_post` e processamento do recebimento):

| Situação informada pelo provedor | Lançamentos criados (mesma conta) | Efeito no caixa |
| --- | --- | --- |
| Pagamento de R$ 10,00 com taxa de R$ 0,30 | Entrada R$ 10,00 (categoria da finalidade) + Saída R$ 0,30 (categoria de taxa) | **R$ 9,70** |
| Devolução total, provedor devolve a taxa | + Saída R$ 10,00 (categoria de devolução) + Entrada R$ 0,30 (estorno de taxa) | R$ 0,00 |
| Devolução total, provedor fica com a taxa | + Saída R$ 10,00 | − R$ 0,30 |
| Devolução parcial | Saída do valor devolvido informado | proporcional |

- Bruto, taxa e devolução vão para a **mesma conta**, então o saldo bancário fica líquido, exatamente como no exemplo de R$ 10,00 → R$ 9,70.
- A devolução registrada é a que o provedor informar; se ele alterar a taxa depois, a diferença entra como "estorno de taxa".
- Valores em centavos inteiros (sem arredondamento de ponto flutuante).
- Se o líquido do provedor não bater com bruto − taxa, ou se a devolução vier antes da primeira contabilização, o pagamento fica **"Requer análise"** e nada é lançado. Correto como proteção.
- O registro em partidas dobradas (bruto como receita e taxa como despesa) é a forma recomendada: a prestação de contas mostra quanto foi doado e quanto custou receber.

**Ajustes recomendados (tela, não lógica):**
- Pagamentos "Requer análise" mostram só um texto técnico, sem dizer o que fazer. Incluir ação clara: "Consultar novamente no provedor" e, se persistir, "Fale com a Vinha".
- Rótulo "Previsto" para dinheiro ainda não liberado pelo provedor → "A liberar".
- Coluna "Líquido contábil" → "Líquido em caixa".

### 2.2 Totais de Recebimentos digitais — **corrigir**

`digitalPageTotals` (`app/lib/finance-digital-display.ts`) soma só os itens da página carregada. Com mais de 100 pagamentos no período, os cartões do topo mostram menos do que de fato entrou. A tela avisa ("Resumo dos até 100 pagamentos desta página"), mas o número induz a erro.
**Proposta:** o servidor devolver os totais do período inteiro (mesma consulta, agregada) e a tela exibir "Total do período".

### 2.3 Baixa manual em Contas a receber/pagar — **ajustar classificação**

Em `private.finance_f2` (`20261020220610_finance_f2_payables_receivables.sql`), na baixa:
- `bruto = principal + juros + multa − desconto` é lançado em **um único movimento**, na categoria do título.
- A taxa vira saída separada na mesma conta (correto: o caixa fica líquido).

Problema: juros e multa ficam misturados com a categoria do título. Exemplos:
- Aluguel de R$ 2.500,00 pago com R$ 50,00 de multa → aparece "Aluguel R$ 2.550,00" no relatório.
- Mensalidade recebida com juros → juros somam em "Dízimos" ou "Mensalidades".

**Proposta:** lançar juros/multa em categorias próprias ("Juros e multas pagos" nas saídas; "Juros e multas recebidos" nas entradas) e o desconto em "Descontos concedidos/obtidos", mantendo o principal na categoria do título. Requer migração nova e teste de banco; os registros antigos permanecem como estão (sem reprocessar histórico).

## 3. Abrangência — selecionar igreja sem trocar a do topo

**Hoje:** "Abrangência" só oferece "Somente [igreja do topo]" ou "Consolidado". Para ver outra igreja é preciso trocar a igreja do cabeçalho.

**Como deve ficar:**
- Lista: "Consolidado · todas as autorizadas" + cada igreja em que a pessoa tem acesso financeiro (a lista já vem do servidor conforme permissão).
- Escolher uma igreja muda **só o Financeiro**; o cabeçalho continua na igreja visualizada.
- Ao sair do Financeiro ou recarregar a página, volta para a igreja do cabeçalho.
- Quando a igreja escolhida for diferente da do topo, mostrar um aviso discreto: "Você está vendo o financeiro de [igreja]. Voltar para [igreja do topo]".
- O servidor continua conferindo o acesso em cada consulta (sem mudança de permissão).

## 4. Formulários, obrigatórios e alertas

### 4.1 Marcação de obrigatórios

Hoje: obrigatórios usam o atributo do navegador, sem marca visual; alguns opcionais têm "· opcional", outros não. Proposta (padrão único):
- Marcar só os **opcionais** com "(opcional)" — a maioria dos campos é obrigatória, então isso polui menos que asteriscos.
- Agrupar opcionais em "Mais opções" (já feito no novo lançamento; estender para edição, baixa e cadastros).

Campos obrigatórios por formulário (confirmados no código e na validação do servidor):

| Formulário | Obrigatórios | Opcionais |
| --- | --- | --- |
| Novo lançamento / edição | Tipo, valor, descrição, conta, categoria (exceto transferência e saldo inicial), vencimento, data do pagamento quando "já foi pago/recebido" | Subcategoria, centro de custo, competência (padrão = vencimento), pessoa/fornecedor, observações, comprovante |
| Receber/Pagar (baixa) | Valor, conta, data, observação | Juros, multa, desconto, taxa (classificação da taxa obrigatória só se houver taxa), forma |
| Transferência | Valor, conta de origem, conta de destino (diferente da origem), data | Observações |
| Parcelamento/recorrência | Valor, quantidade (2 a 60), intervalo, primeiro vencimento, conta, categoria | Pessoa, observações |
| Categoria | Nome, tipo (entrada/saída) | Categoria principal (para subcategoria) |
| Conta bancária/caixa | Nome | Banco, agência/conta, descrição |
| Fornecedor | Nome | Documento, e-mail, telefone |

### 4.2 Aviso ao tentar salvar com algo faltando

Proposta: validar no navegador antes de enviar, com o mesmo padrão já usado em Push (`FieldError`):
- Mensagem logo abaixo do campo ("Informe o valor", "Escolha a categoria"), borda de erro e foco no primeiro campo com problema.
- Resumo no topo: "Faltam 2 campos: Valor, Categoria" com links para os campos.
- Se o campo estiver dentro de "Mais opções", abrir a seção automaticamente (hoje um campo obrigatório escondido em seção fechada impede o envio sem mensagem visível).
- Regras específicas: data de pagamento não pode ser futura; desconto não pode passar do principal; taxa não pode ser maior que o valor recebido; conta de destino diferente da origem.

### 4.3 Mensagens de erro do servidor

Hoje `app/api/finance-f1/route.ts` (`failure`) converte todo erro de validação em uma frase genérica. O banco já levanta motivos específicos. Mapear os principais:

| Motivo do banco | Mensagem proposta |
| --- | --- |
| `period_closed` | "Este mês já foi fechado. Reabra o período em Fechamento mensal para alterar." |
| `invalid_account`, `account_unavailable` | "A conta escolhida está inativa ou não pertence a esta igreja." |
| `invalid_category`, `invalid_classification` | "Escolha uma categoria ativa do tipo correto (entrada ou saída)." |
| `invalid_center` / `invalid_supplier` | "O centro de custo/fornecedor escolhido está inativo." |
| `opening_already_exists` | "Esta conta já tem saldo inicial. Edite o existente." |
| `entry_changed`, `request_conflict`, `invalid_revision` | "Outra pessoa alterou este lançamento. Atualize para ver a versão atual." |
| `reason_required` | "Informe a observação ou justificativa." |
| `finance_access_denied`, `finance_scope_denied` | "Você não tem acesso financeiro a esta igreja." |
| `report_limit_reduce_period` | "Período muito grande para este relatório. Reduza o intervalo." |

### 4.4 Perda de dados ao fechar janela

`Dialog` (em `FinanceModule.tsx`) fecha com X ou Esc sem perguntar. Proposta: se houver campo alterado, confirmar "Descartar o que foi preenchido?" com as opções Continuar editando / Descartar.

## 5. Textos — excesso e termos técnicos

Medição: ~12 mil caracteres de texto de apoio nas telas do financeiro; 36 textos com mais de 110 caracteres (o maior com 325). Princípio: uma frase curta por tela; detalhes em "Saiba mais" recolhido.

Exemplos de troca:

| Hoje | Proposta |
| --- | --- |
| "Compare o extrato OFX com movimentos efetivamente contabilizados. A importação não cria receita, despesa ou transferência." | "Importe o extrato do banco e confira com os lançamentos." |
| "Possível duplicidade por data, valor e descrição. Revise; FITIDs diferentes não são excluídos automaticamente." | "Pode ser um movimento repetido. Confira antes de conciliar." |
| "A conciliação bancária não é obrigatória para o fechamento administrativo. Sem extrato ou com pendências, proprietário/administrador pode fechar com ressalvas..." (259 caracteres) | "Você pode fechar o mês mesmo com pendências; elas ficam registradas." |
| "Baixa manual não faz transferência bancária, cobrança de cartão ou emissão de boleto. Séries geram de 2 a 60 previsões..." | "Registrar o recebimento aqui não movimenta o banco." |
| "Nenhuma operação F5 registrada." | "Nenhum fechamento ainda." |
| "Clareza em cada recebimento" (título de marketing) | "Pagamentos recebidos" |
| Cabeçalho das janelas "FINANCEIRO · VINHA" | Remover |
| Vocabulário misto "Natureza", "Recebimento/Pagamento", "Entrada/Saída" | Sempre "Tipo: Entrada / Saída" |
| Observação interna "F4 · Pedido <código>" / "F2 · título <código>" | "Pedido online nº …" / "Baixa do título L-…" |

## 6. Layout e navegação — por página

**Geral**
- Botão "⚙ Configurações" do topo leva só a Categorias e duplica o grupo Cadastros → remover.
- "Gerar relatório" duplica a aba Relatórios → manter só onde gera o relatório da própria tela (Conciliação, Fechamento), com nome específico ("Relatório desta conciliação").
- Filtro de período só nas telas de movimento (Visão geral, Lançamentos, Contas, Conciliação, Recebimentos digitais, Relatórios). Fechamento usa o mês; cadastros não usam período.
- Títulos com serifa (Georgia) só no Financeiro; demais módulos sem serifa → alinhar à identidade da plataforma.

**Visão geral** — painel que caiba numa tela: saldo por conta, entradas × saídas do mês, vencidas e as que vencem em 7 dias (com Receber/Pagar), gráfico compacto de 6 meses. Remover a tabela completa de lançamentos (já existe na aba Lançamentos). Fluxo de caixa hoje ocupa uma tela inteira com "Previsto R$ 0,00" repetido.

**Lançamentos** — linha inteira clicável; botão menor; classificação em uma linha ("Dízimos › Online"), sem "Sem subcategoria"/"Sem centro de custo" repetidos.

**Edição de lançamento** — valor formatado (`3.520,00`); "Natureza" → "Tipo" com os mesmos botões do novo lançamento; explicação de 325 caracteres em "Saiba mais".

**Conciliação**
- Selecionar automaticamente a conta quando a igreja tem uma só; quando houver várias, explicar por que "Importar extrato" está desativado ("Escolha a conta").
- Cada movimento do extrato tem 2–3 botões largos empilhados → um botão principal ("Conciliar com…") e um menu "⋯" (Criar lançamento, Desconsiderar).
- Datas técnicas na conferência de saldos e nos extratos importados.
- Tabela "Conferência dos saldos" corta no celular → cartões.

**Fechamento mensal** — remover a repetição da conferência de saldos (fica na Conciliação); checklist com ações diretas ("Ver 2 pendências" leva à Conciliação filtrada); datas formatadas.

**Recebimentos digitais** — totais do período (2.2); ação para "Requer análise" (2.1); "Pedido O0" → número legível; seções "Classificação e integrações" e "Destinação entre igrejas" movidas para Cadastros (são configuração).

**Categorias** — lista em árvore (categoria com suas subcategorias), separada por Entradas e Saídas, com contagem de uso; botões "Editar" e "Desativar" em menu da linha; sem filtro de período.

**Contas recebedoras** — textos de configuração do provedor (Webhooks, Access Token) em passo a passo recolhido; mensagens só para quem pode configurar.

**Relatórios** — modelos de colunas (Resumo, Prestação de contas, Completo), "Resumo" como padrão; títulos de coluna sem quebra no meio da palavra.

## 7. Tipografia e legibilidade

| Elemento | Hoje | Proposta |
| --- | --- | --- |
| Texto das tabelas | 12 px | 14 px |
| Nome de pessoa/fornecedor, conta, subcategoria (linha secundária) | 10 px, cinza claro `#7c887f` | 13 px, cinza `#5f6f64` (contraste AA) |
| Rótulos e textos de apoio (`f1-kpi small`, `f1-note`, `f1-party small`) | 10–12 px | mínimo 12 px; corpo 14 px |
| Recebimentos digitais (36 ocorrências de 11 px) | 11 px | 13 px |
| Provedores (`finance-providers.css`) | 7–9 px | mínimo 12 px (ou ícone sem texto) |
| Cabeçalho das janelas "FINANCEIRO · VINHA" | 10 px | remover |

Nomes longos de fornecedores/pessoas: quebrar em até duas linhas com reticências, nome completo no detalhe; nunca cortar o valor.

## 8. Paginação e quebra de páginas

- Telas: listas paginadas (30 por página, até 150) em Lançamentos, Contas, Categorias e Conciliação — adequado. Recebimentos digitais usa "Mais recentes/Mais antigos" (cursor); padronizar com o mesmo rodapé ("1–30 de 245 · Anterior · Próxima").
- PDF (`app/lib/finance-export.ts`): já quebra páginas, repete o cabeçalho da tabela e numera "Página X de Y" — correto. Ajustes: relatórios com mais de 8 colunas em **paisagem**; evitar quebrar uma linha entre páginas.
- Impressão pelo navegador (`finance-reports.css`): repete cabeçalho e evita quebrar linhas — correto.

## 9. Plano de execução proposto

| Etapa | Conteúdo | Banco? |
| --- | --- | --- |
| **A. Abrangência e mensagens** | Abrangência com todas as igrejas autorizadas sem mudar o topo (3); mensagens específicas do servidor (4.3); confirmação ao fechar janela com dados (4.4) | Não |
| **B. Formulários** | Validação por campo com destaque e resumo (4.2); padrão de opcionais (4.1); edição com valor formatado e "Tipo" em botões | Não |
| **C. Textos e tipografia** | Textos curtos e vocabulário único (5); escala de fontes (7); remoção de botões duplicados e do período onde não se aplica (6 Geral) | Não |
| **D. Páginas** | Visão geral em painel; Conciliação e Fechamento simplificados; Categorias em árvore; Recebimentos digitais com ação para análise e "A liberar" | Não |
| **E. Lógica** | Totais de Recebimentos digitais do período inteiro (2.2); juros/multa/desconto em categorias próprias na baixa (2.3) | Sim (migração nova, testes de banco, sem reprocessar histórico) |

Cada etapa: testes automatizados, capturas a 1440 px e 390 px, PR e publicação como nas fases anteriores. A etapa E precisa de banco de homologação ou do Docker local para validar a migração antes da produção.
