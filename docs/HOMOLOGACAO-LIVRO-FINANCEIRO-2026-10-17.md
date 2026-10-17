# Livro financeiro — interface de homologação

Data: 17/10/2026. Continuação da PR 33; depende das migrações L1/L2 e do núcleo financeiro dessa revisão. Nenhuma migração ou implantação em produção faz parte deste passo.

## Acesso e bloqueios

Página `/financeiro-piloto?tenant=<endereco-do-ministerio>`, API `/api/church-ledger`. Não adicionar essa tela ao catálogo comercial nem retirar a contenção do módulo financeiro atual. A página é uma interface de teste; os dados e operações exigem sessão válida na API.

A API fica desativada por padrão (503 antes de autenticar, ler corpo ou chamar o banco). Exige `VINHA_LEDGER_PILOT=true` no servidor e:

- Nuvem: `NEXT_PUBLIC_VINHA_ENV=test` com projeto separado e URL exata conforme `assertDeploymentIsolation`.
- Local: `NODE_ENV=development` ou `test`, sem `VERCEL_ENV`, `NEXT_PUBLIC_VINHA_ENV=local`, URL exata `http://127.0.0.1:54321`.

`VERCEL_ENV=production` é sempre recusado. Não configurar essas variáveis para contornar a falta de homologação; o banco principal é recusado. A produção atual não é alterada. O build Preview continua dependendo da configuração isolada anterior, ainda indisponível.

Somente proprietário, administrador ou financeiro, com participação/unidade autorizadas, podem usar a API. A organização vem da sessão verificada, nunca do corpo. A autorização final de papel, contrato, unidade e estado ocorre no banco, inclusive para chamadas diretas às funções. A rota não usa chave de serviço nem banco legado.

## Fluxos implementados

1. Selecionar unidade e data de corte. Carregar contas/saldos e 25 movimentos por página, ordenados; saldos usam texto em centavos, sem conversão imprecisa em Number.
2. Criar conta de ativo (banco/caixa), receita ou despesa. Não configurar número de conta bancária ou credencial do provedor nessa tela.
3. Registrar duas partidas balanceadas: conta debitada, creditada, valor positivo e descrição. Transferência usa duas contas de ativo. Sinais contábeis não são uma demonstração gerencial de lucro/prejuízo.
4. Estornar escolhendo o movimento original e motivo. A API não envia valores arbitrários no estorno; o banco gera o inverso das partidas originais. Estorno duplicado é recusado.
5. Fechar até data anterior ao dia corrente, após confirmação explícita. Não há ação de reabertura nesta versão. Fechamento não declara conciliação com extrato.

## Reexecução e falhas

Lançamento/estorno usa UUID de pedido. A interface guarda o comando em memória ANTES de enviar; erro de conexão, resposta ilegível ou resultado incerto não permite criar outro movimento enquanto o pedido estiver pendente. “Reenviar o mesmo pedido” preserva UUID, valores, data e contas. O banco só repete o mesmo conteúdo; conteúdo divergente é recusado. O retorno deve confirmar o mesmo UUID enviado.

Esse estado não persiste ao recarregar/fechar a página. Se isso ocorrer, consultar o histórico pelo ID antes de qualquer novo lançamento; não há promessa de recuperação automática entre dispositivos. Criar conta depende de nome único por unidade; fechamento tem bloqueio progressivo. Em resultado incerto dessas operações, atualizar a consulta antes de tentar novamente. Não apresentar erro como sucesso nem apagar registros para corrigir duplicação.

## Testes e limites

Testes de unidade exercitam bloqueio em produção, valores inválidos/centavos fracionados, datas, papéis, unidade cruzada, organização forjada, estorno, erro de banco, confirmação de ID e manutenção do pedido pendente. Os testes reais SQL/concorrentes do núcleo permanecem no CI. Checagem de tipos separada inclui API, validação e tela; strict continua ativo.

Falta homologação visual/autenticada, ensaio completo com sessão real, testes de navegador para interrupção/reenvio, conciliação, centros de custo, anexos financeiros e exportação contábil. Sem backup/monitoramento ativos, conta sandbox ou contador, já confirmados ausentes pelo usuário. Não liberar para clientes com dados reais nem anunciar L4 concluída.
