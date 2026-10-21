# F4 — Recebimentos automáticos e taxas

## Estado real

Implementação em revisão na branch `feat/financeiro-f4-2026-10-21`. Não representa homologação externa nem liberação de dinheiro real. A F3 continua sem cofre/OAuth homologados; o responsável informou em 21/10 que ainda não possui contas Asaas/Safe2Pay de teste. Não reutilizar credenciais SaaS como autorização das igrejas.

## Entregue nesta revisão

- Financeiro → Arrecadação digital, navegação por igreja e período. Finalidades: dízimos, ofertas, doações, campanhas, eventos e outras personalizáveis. Categoria e subcategoria separadas, centro e conta de destino, categorias para taxas/devoluções/créditos de taxas.
- Pedidos idempotentes vinculados à finalidade, conta recebedora, unidade, valor e referência. Pessoa opcional pelo identificador de membro autorizado ou nome livre, sem cadastrar/vincular automaticamente por semelhança. Classificação imutável por pedido; edição posterior da finalidade não reclassifica pagamentos antigos.
- Leitura Mercado Pago no servidor com o token específico da conta recebedora. Verifica transação, collector, moeda, ambiente, referência interna e valor. Não confia nos dados financeiros enviados pelo navegador ou webhook.
- Webhook Mercado Pago assinado, request ID/ID/timestamp vinculados, validade de cinco minutos, segredo por ambiente e consulta independente à API oficial. Endpoint `/api/finance-digital/webhook/<receiver>?environment=sandbox` ou `production`; o provedor acrescenta `data.id` e `type`.
- Bruto preservado como contribuição; taxa é despesa vinculada. Taxa de financiamento paga pelo contribuinte não é debitada da igreja. Pagador da taxa ausente é desconhecido, não zero. Líquido informado precisa coincidir antes da primeira contabilização.
- Valores em centavos inteiros; nenhuma multiplicação binária para dinheiro. Campos ausentes não são estimados como zero. Cupom e total pago preservados quando informados; diferenças no líquido exigem revisão.
- Pendência/aprovação sem disponibilidade não aumenta saldo. Conta de teste não lança no livro real. Data de liberação usa America/Sao_Paulo; período fechado exige revisão, sem deslocamento silencioso para hoje.
- Devoluções confirmadas cumulativas e créditos de taxa geram novos ajustes vinculados. Devolução anterior à primeira liquidação, contestação sem prova de débito, divergências e classificação indisponível permanecem na revisão, sem inventar movimentos.
- Identidade transação/conta e pedido únicos; eventos fora de ordem ignorados, versões iguais divergentes recusadas. Locks ministério → unidade → conexão/recebimento. Quatro notificações simultâneas geram somente uma contribuição e uma despesa de taxa.
- Histórico imutável dos eventos verificados e dos ajustes. Lançamentos digitais não são editados ou estornados pelo fluxo manual F1/F2. Tabelas privadas com RLS restritiva; só o serviço pode importar uma prova. Clientes não podem mandar um status aprovado arbitrário.
- Revogação, bloqueio, expiração e mudança de autorização revalidados antes da ingestão. O serviço não cria sessão fictícia de usuário, não altera claims para contornar regras e não usa o papel financeiro para autorizar credenciais no lugar do titular.

## O que esta revisão NÃO entrega (não chamar F4 completa)

1. Checkout público integrado no aplicativo/site de eventos, autorização recorrente e conclusão externa de Pix/boleto/cartão. O botão “Registrar pedido” somente registra a referência. O checkout de validação descrito abaixo já possui código, mas não foi homologado externamente nem publicado.
2. Migração das inscrições/pagamentos de eventos e do aplicativo do membro para o banco principal. Seus endpoints antigos permanecem contidos; não foram religados ao banco antigo. A referência textual de evento/campanha não é apresentada como uma inscrição validada.
3. Sincronização real Asaas/Safe2Pay, aprovação de métodos ou homologação financeira externa. Consulta de transação atualmente aceita Mercado Pago apenas. Não inferir identidade, conta ou ambiente de um prefixo de chave.
4. Detalhamento externo de taxas de antecipação não fornecidas pelo endpoint, comprovantes, ajustes de juros/multa/desconto e débito de chargeback com evidência. A fila não transforma falta de prova em pagamento ou devolução automática.
5. Agendador de recuperação/reprocessamento, alertas de falha e fechamento de divergências com decisão administrativa auditada. O reenvio do webhook pelo provedor e a reavaliação manual estão preparados; não constituem monitoramento operacional completo.
6. Relatórios consolidados/exportações da arrecadação e conciliação bancária F5/F6. “Disponível” no provedor não é conciliação com extrato bancário.

## Configuração futura, sem segredos no repositório

- Cofre e OAuth F3 separados por ambiente, além de `FINANCE_MP_TEST_WEBHOOK_SECRET` e `FINANCE_MP_LIVE_WEBHOOK_SECRET` no servidor. Nunca usar nomes NEXT_PUBLIC para segredos.
- Concluir homologação F3, cadastrar destino correto no provedor e configurar a URL oficial do webhook. Não habilitar métodos por uma opção visual nem fazer transação real sem autorização específica do titular.
- Enviar `external_reference` igual ao UUID do pedido registrado quando a criação de checkout estiver implementada. Webhooks de transações desconhecidas são recusados, não classificados por heurística.

## Complemento de checkout e destinação — 21/10, ainda em revisão

- Modal “Preparar checkout” no pedido sem transação observada; rota autenticada `/api/finance-digital/checkout`, restrita a proprietário/administrador nesta validação. Preço e recebedor vêm do pedido imutável; e-mail vem da conta confirmada, não do navegador. Não constitui checkout público do aplicativo/eventos.
- Reserva durável por pedido antes da chamada externa. Somente uma reivindicação permite um POST de preferência. Timeout, queda do processo e falha de persistência não permitem outro POST automático. Uma preferência incerta exige conferência; não existe botão que apaga o bloqueio e cria cobrança duplicada.
- POST oficial de preferências usa o token específico do recebedor e referência interna. Resposta valida collector, referência, item, moeda, quantidade, preço e domínio do link. Usa `init_point`, não fallback legado `sandbox_init_point`. Transporte simulado nos testes: nenhuma chamada de criação real foi executada.
- Origem fixa `FINANCE_CHECKOUT_ORIGIN`, restrita a `app.vinhaigrejas.com.br` ou `teste.vinhaigrejas.com.br`; não aceita Host/Forwarded nem URLs arbitrárias do cliente. Checkout real permanece bloqueado por `FINANCE_MP_LIVE_CHECKOUT_ENABLED=false`, além de depender do cofre/OAuth/webhook.
- Página `/pagamento/retorno` não declara pagamento aprovado a partir dos parâmetros de retorno. Recebimentos continuam dependendo da consulta independente ao provedor e das regras contábeis existentes.
- Nova destinação interna permite vincular o líquido integral de um recebimento confirmado a uma beneficiária autorizada na mesma organização. Exige responsável com acesso às duas unidades, versão otimista e auditoria da alteração. Visão das últimas 100 destinações, sem filtro de período, declarada na interface. Devoluções/taxas contabilizadas ajustam o líquido consultado.
- A destinação não executa split, repasse, quitação ou transferência bancária; não lança receita/saída duplicada nem cria saldo na filial. Ainda não há rateio percentual, baixa de repasses ou recepção direta de pedido do aplicativo/evento pela filial usando conta bancária da sede. A finalidade/pedido continua pertencendo à unidade recebedora.
- Migrações `20261021103532_finance_f4_checkout_reservations.sql` e `20261021104459_finance_f4_beneficiary_destinations.sql`: preparadas e testadas localmente, não aplicadas ao Supabase principal.
- Mercado Pago exige revalidação pelo aplicativo do titular. Em 21/10 o responsável escolheu **configurar mais tarde**. Asaas e Safe2Pay continuam sem contas de teste informadas. Não registrar esses testes como homologação externa concluída.

Contrato oficial de checkout: [Criar preferência Mercado Pago](https://www.mercadopago.com.br/developers/pt/reference/online-payments/checkout-pro-preferences/create-preference/post).

## Evidências

Testes `scripts/finance-f4*.test.mjs`; SQL transacional `supabase/tests/finance_f4.sql`; concorrência com conexões independentes `scripts/finance-f4-concurrency.mjs --local-synthetic`; HTTP com sessão local `scripts/local-finance-f4-smoke.mjs --local-synthetic`. Esses testes usam exclusivamente Docker/fixtures locais ou transporte simulado e não comprovam aceitação externa dos provedores.

Referências: [Mercado Pago Webhooks](https://www.mercadopago.com.br/developers/pt/docs/your-integrations/notifications/webhooks), [exemplo oficial de taxas por pagador](https://www.mercadopago.com.br/developers/en/docs/resources-pci-compliant-merchants/unified-post), [Supabase functions](https://supabase.com/docs/guides/database/functions), [Asaas consulta de cobrança](https://docs.asaas.com/reference/recuperar-uma-unica-cobranca).
