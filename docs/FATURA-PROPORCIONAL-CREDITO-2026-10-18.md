# Documentos proporcionais e consumo de crédito — homologação local

## Entrega

Migração aditiva `20261018152708_proration_documents_credit_application_pilot.sql`, dependente do núcleo de alteração de plano anterior. Não aplicada de forma persistente em banco local nem produção: testada dentro de transação revertida no Docker fixo.

1. Cada ajuste positivo novo cria um documento interno `additional_invoice`; ajuste negativo cria documento `credit`. Ambos preservam o snapshot e têm vínculo único ao ajuste. Ajuste zero não gera documento financeiro. Não houve backfill dos ajustes históricos.
2. A função `issue_proration_cycle_invoice_pilot` bloqueia contrato/ciclo, exige gestor da Central com MFA/e-mail confirmado e deriva valores/pagador do estado validado. Cria uma nova fatura mensal em `saas_invoices` e aplica créditos compatíveis com contrato/pagador antes do commit. Não edita faturas antigas.
3. Cada consumo é registrado em `saas_proration_credit_uses`, com documento, fatura e centavos. O saldo disponível é valor original menos consumos. Não há marcação genérica de crédito gasto sem vínculo à fatura.
4. Uma repetição do mesmo pedido/conteúdo devolve o snapshot original. Outro pedido não pode emitir novamente o mesmo contrato/período. Crédito aplicado não pode exceder o valor novo; saldo não utilizado permanece no documento. Fatura líquida zero fica quitada sem chamada ao provedor.
5. Faturas emitidas por esse piloto não permitem alterar valor, identidade, pagador ou período; cancelamento pelo fluxo comum é recusado até existir reversão auditada do crédito. Pagamento e dados de checkout continuam sujeitos aos fluxos já existentes.
6. RLS e privilégios bloqueiam gravações diretas dos novos documentos/consumos por visitantes, contas autenticadas e chave de serviço; gestores autorizados podem consultar. Funções privilegiadas validam o acesso antes de escrever. O gatilho de proteção da fatura tem leitura privilegiada estritamente para não quebrar atualizações comuns de webhook por falta de SELECT nas tabelas novas.

## Rotas e limites

POST `/api/platform/contracts/cycle-invoice`: aceita somente pedido, contrato e referência mensal. Não aceita valor ou pagador do navegador. Exige `VINHA_PLAN_PRORATION_PILOT=true` e o gate de ambiente isolado; produção recusada por padrão. Nenhuma tela foi conectada nesta entrega.

**Documento adicional interno não é cobrança publicada no provedor.** Ele permanece fora da carteira normal de faturas e do checkout até a integração específica. A nova fatura mensal com crédito também não foi enviada ao provedor, e não foi habilitada na geração automática comum. A rota existe apenas como piloto.

O período aceito é o mês do fim do ciclo validado. Não se presume um calendário novo a partir do vencimento do cadastro. A referência sem ciclo validado é recusada. Não há rotina de rollover para ciclos seguintes nem transferência de crédito entre pagadores. Créditos de outro pagador não são aplicados automaticamente.

## Verificações executadas

- **40 testes SQL** no Docker, com rollback integral: MFA, autorização, criação dos documentos, histórico, preservação de fatura, reenvio, consumo único e proteção do valor emitido.
- Caso sintético: crédito de 3.000 centavos abate nova fatura de 10.000, produzindo 7.000 centavos. Repetição não cria novo consumo/fatura.
- Falha forçada na auditoria reverte fatura, vínculo de consumo e registro de idempotência juntos; a nova tentativa funciona após remover o gatilho temporário da massa de teste.
- **133 testes de aplicação**, checagem TypeScript restrita e varredura estática de segredos: aprovados.
- Não foi executado ensaio real com duas sessões concorrentes neste bloco. Há bloqueios e restrições no código, mas isso não substitui esse ensaio. Também não houve download/tela de cliente ou homologação externa.

## Próximos itens

1. Ensaiar duas sessões independentes de emissão e alteração, incluindo colisão com o gerador mensal antigo; confirmar que o perdedor não consome crédito.
2. Tratar rollover, crédito maior que uma mensalidade em ciclos sucessivos e mudança de pagador, sem perder histórico.
3. Bloquear/revisar mudanças de contrato após emissão antecipada da próxima fatura; hoje o piloto não deve antecipar produção comercial.
4. Conectar a tela de confirmação e a carteira de documentos adicionais, preservando UUID nas tentativas.
5. Implementar reversão auditada de consumo para cancelamento legítimo, depois geração automática/checkout e homologação sandbox.

Não declarar L4 concluída. Nenhuma migração de produção, cobrança, nota fiscal, mensagem ou atualização remota de PR foi executada.
