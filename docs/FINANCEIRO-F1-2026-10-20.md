# Financeiro F1 — fundação operacional

## Escopo

Dashboard por igreja ou seleção consolidada das unidades financeiras autorizadas, período de até 366 dias, BRL, contas/caixas, saldos iniciais positivos, categorias e subcategorias de dois níveis, centros de custo, fornecedores e lançamentos manuais. Contas são sempre locais. Categorias, centros e fornecedores podem ser compartilhados pelo ministério por proprietário/administrador; financeiros gerenciam cadastros locais. Alterações preservam a identidade, tipo e escopo do cadastro. Arquivamento não apaga históricos. Não há consolidação entre ministérios distintos vinculados comercialmente.

Não reutiliza os valores fictícios de FinancialLedger nem desbloqueia /api/finance/providers e os demais endpoints legados. O painel usa FinanceModule e /api/finance-f1; o núcleo de partidas balanceadas anterior continua por trás da operação. O catálogo comercial do Financeiro permanece piloto e informa os limites, não declara o módulo inteiro pronto.

## Uso

1. Selecione a igreja, cadastre caixa/banco e, se necessário, registre um saldo inicial positivo com data. Abertura tem contrapartida própria e não é arrecadação. Saldo negativo de abertura não é suportado nesta entrega.
2. Cadastre categorias de recebimento/pagamento, subcategorias e centros de custo. Configure fornecedores opcionais. Dados bancários aqui são identificadores cadastrais, não conectam ao banco.
3. Registre entrada ou saída com conta, categoria, valor, competência e vencimento. A data realizada registra a liquidação manual; desmarque “já foi recebido/pago” para previsão.
4. Pesquise membro ou fornecedor por nome. São retornados somente identificador, nome e tipo, não CPF, e-mail, telefone ou informações pastorais dos membros. Selecionar usa o nome canônico e identificador; digitar sem selecionar não cria cadastro. Sem identificação é permitido.
5. Transferências usam duas contas da mesma unidade; não são receitas/despesas. Transferências entre unidades, baixas parciais, aprovações, parcelamentos e baixa posterior de previsões pertencem ao F2/F5, não são simulados como ativos.
6. Correção de movimento realizado exige estorno com motivo/data e novo lançamento. Previsões podem ser canceladas. Não há edição destrutiva de movimentos confirmados.
7. Consulte detalhes e anexe PDF/PNG/JPEG de até 4 MB. Downloads autenticados, privados e como anexo. Sem URL pública/assinada, substituição ou exclusão. A detecção de assinatura de arquivo não equivale a antivírus/CDR; não executamos conteúdo.

## Dashboard e filtros

Saldo das contas até a data final (inclui contas arquivadas); entradas/saídas realizadas por data efetiva, previsões por vencimento e vencidos, fluxo mensal realizado/previsto, agrupamentos por categoria/centro e movimentações paginadas. Aberturas e transferências não integram receitas/despesas. Estornos afetam o fluxo na data do estorno, sem reescrever o período original. Saldo contábil não significa conciliação bancária nem saldo consultado no banco.

Filtros de igreja, período, descrição/pessoa, tipo, situação, tipo de data, conta, categoria e centro. Totais são calculados no banco sobre toda a seleção, não só os 30 registros da página. Os cartões abrem os filtros correspondentes. Consolidação não permite gravações: selecione uma igreja para isso. Nenhuma unidade recusada é omitida silenciosamente do total.

## Segurança e consistência

- Conta confirmada, papéis owner/admin/finance e permissão financeira de gestão da unidade, módulo, estado comercial e operacional revalidados no banco; organização vem da sessão na API.
- Tabelas internas privadas com RLS e sem acesso direto de clientes ou service_role. Escrita somente por comandos validados, sem SQL do navegador. Arquivos revalidam acesso atual.
- Valores em centavos inteiros; totais textuais/BigInt, sem arredondamento por ponto flutuante.
- Comando com UUID preservado antes do envio em sessionStorage segregado por usuário/ministério. Reexecução de lançamento/estorno não duplica. Resultado incerto bloqueia novos pedidos e oferece reenvio do mesmo comando. Fechar a aba pode perder sessionStorage: verificar histórico antes de recriar. O armazenamento local não é um backup nem recuperação entre dispositivos.
- Edição cadastral usa versão exata. Os comandos do F1 serializam por ministério; leitura segura mantém consistência do catálogo/saldo/fluxo contra escritas do F1. Essa serialização privilegia correção e poderá exigir ajuste medido de desempenho para ministérios grandes.
- O antigo comando público de partidas permanece compatível para contas de homologação, mas recusa movimentar/estornar contas e lançamentos vinculados ao F1. A função de postagem interna não é executável por clientes. Fechamento antigo continua protegendo o período.
- Audit logs de cadastro, lançamento e estorno/cancelamento, com autor e unidade; sem credenciais. Sem apagar contas de clientes, privilégios ou movimentos existentes.

## Fora do F1

Cobranças em provedores, criação/conexão de contas recebedoras, arrecadação automática, taxas efetivas, recorrência de cartão, Pix bancário, OFX, aprovação, fechamento por checklist, relatórios fiscais e integração contábil especializada. Nenhuma chave ou provedor é ativado para simular conclusão.

## Verificação

`scripts/finance-f1.test.mjs`: validação monetária, datas, comandos estritos, vínculos, catálogos e escopos.
`supabase/tests/finance_f1.sql`: acesso direto negado, isolamento, classificação, duplicidade, previsões, saldo, transferência, abertura, estorno, concorrência otimista, arquivamento e acesso a anexos; fixtures transacionais revertidas.
`scripts/local-finance-f1-smoke.mjs --local-synthetic`: Auth real e API local, cadastro, recebimentos/despesas/previsões, agrupamentos, arquivos privados, reenvio e contenção da API antiga. Não aceita destino remoto e não envia mensagens/cobranças.

Executar também regressões existentes, build, tipos e testes SQL/concorrentes completos no CI antes de produção. Evidências reais da rodada são registradas separadamente; a existência deste documento não prova implantação.
