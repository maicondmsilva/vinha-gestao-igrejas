# Financeiro F2 — compromissos, baixas e rastreabilidade

## Entrega

Contas a pagar e receber por unidade autorizada, filtros de período/situação/conta/categoria/subcategoria/centro/pessoa, baixa manual total ou parcial, juros, multas, descontos e taxa explícita. O principal liquidado reduz a previsão; a baixa registra o bruto e a taxa gera uma despesa independente. O saldo é líquido. Não executa pagamentos, transferências bancárias, emissão de boleto nem cobranças de cartão.

O lançamento usa **Frequência do lançamento**: **Avulso**, **Repetição programada** e **Em parcelas**. As séries são finitas (2–60 ocorrências, mensais ou semanais). Parcelamento divide o valor total, distribuindo os centavos restantes nas primeiras parcelas. Repetição usa o valor em cada ocorrência. Datas mensais preservam o dia âncora com ajuste ao último dia válido do mês. Não há renovação nem agendamento de débito automático.

Categoria principal e subcategoria são campos separados. Trocar a categoria limpa a subcategoria. A referência contábil continua sendo a classificação mais específica selecionada, vinculada à sua principal imutável. Filtrar a principal inclui filhos; filtrar a subcategoria exige igualdade exata. Nenhum catálogo foi renomeado ou reclassificado automaticamente.

## História e correções

- Consulta por lançamento: autor (nome capturado e ID), instante, campos anteriores/novos, criação, alterações de vencimento, baixas, encargos, taxas e estornos.
- Histórico privado, RLS, sem acesso direto e sem reescrita/exclusão pelos caminhos comuns. Paginação de 100 eventos, com opção para carregar anteriores.
- Para registros anteriores à auditoria detalhada: somente autor/data de criação conhecidos e indicação explícita de que as alterações antigas não foram reconstruídas.
- Estornar uma baixa estorna sua taxa na mesma transação e reabre o principal. O original permanece preservado. Não é possível estornar um movimento vinculado isoladamente pela F1 ou pelo livro antigo.
- Vencimento pode ser reagendado com versão exata e justificativa. Compromissos com baixas ativas não podem ser cancelados: estorne primeiro. Cancelar uma parcela não cancela as outras.
- Movimentos realizados não são editados destrutivamente; a correção continua sendo estorno e novo registro. Alterar cadastro do fornecedor/categoria não reescreve movimentos anteriores.

## Segurança e consistência

Conta confirmada, papel financeiro, unidade real, módulo e contrato revalidados no banco. Organização vem da sessão. Comandos idempotentes, UUID preservado antes do envio, reenvio exato em resultados incertos, versões para concorrência. Taxa e baixa são atômicas: uma classificação inválida desfaz ambas. Valores em centavos inteiros e livro balanceado. Tabelas privadas sem acesso direto. Núcleo anterior revogado dos clientes para impedir contorno.

Leitura consolidada somente entre unidades financeiras autorizadas do mesmo ministério; gravações exigem uma única igreja. Não foram criados usuários, lançamentos ou cobranças fictícias em produção.

## Limites explícitos

Baixa exige bruto positivo; perdão integral sem movimentação deve ter fluxo próprio futuro. Máximo de 200 baixas históricas por compromisso. Taxa de recebimento menor que o bruto; pagamentos podem ter taxa adicional. Juros/multas/descontos são valores manuais, não cálculos legais automáticos. Não há integração bancária ou de provedores, aprovação em múltiplos níveis, transferência entre unidades nem conciliação bancária nesta entrega. As integrações e suas homologações permanecem separadas.

## Verificação

Testes de validação e API: `finance-f2.test.mjs`, `finance-f2-route.test.mjs`. Banco: `finance_f2.sql`, junto da regressão `finance_f1.sql`. Integração HTTP local: `local-finance-f2-smoke.mjs --local-synthetic`, incluindo duplicidade, baixas simultâneas, rollback de taxa inválida, parcial, estorno e parcelas. Todos os testes usam dados fictícios no Docker local; entrega efetiva e recibos de implantação são registrados separadamente.
