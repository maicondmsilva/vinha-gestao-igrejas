# Contas recebedoras por chave — 23/10/2026

## Mercado Pago

O formulário oferece Access Token obrigatório, Public Key opcional e assinatura secreta do webhook. O checkout atual é hospedado no Mercado Pago e não coleta dados de cartão na Vinha; não usa a Public Key. Seu preenchimento não prova que ela pertence ao mesmo aplicativo do token. O token e a assinatura permanecem criptografados, nunca retornam à tela nem aos registros de auditoria.

Salvar a chave consulta somente `GET https://api.mercadopago.com/users/me`, sem criar pagamentos. São conferidos identificador, site brasileiro, identificação do titular e classificação de conta de teste; respostas incompletas, conta indisponível, divergência de ambiente e redirecionamentos são recusados. A validação conservadora de sandbox exige conta de teste. O prefixo da credencial sozinho não comprova o ambiente. Uma chave de produção salva em Teste não é transferida automaticamente.

“Validar chave salva” usa exclusivamente o segredo do cofre. Uma conta já configurada preserva sua destinação se o titular continuar o mesmo; uma chave nova exige reconfirmação. A janela de revalidação é de 30 dias, não uma garantia de validade fornecida pelo Mercado Pago. Antes do vencimento, o responsável deve usar a revalidação. Se o provedor revogar a credencial antes, a consulta/criação será recusada, sem sucesso fictício.

Após validar:

1. Conferir o titular e escolher a conta financeira, igrejas beneficiárias e métodos.
2. No aplicativo Mercado Pago do próprio titular, cadastrar o webhook de pagamentos exibido no cartão da conexão. Sua URL contém o ID do recebedor e o ambiente, nunca uma credencial.
3. Copiar a assinatura secreta desse aplicativo/ambiente para o campo protegido na Vinha. Ela é diferente do Access Token. Campos adicionais vazios na substituição removem o valor anterior.
4. Confirmar a configuração e usar “Habilitar recebimentos”. O responsável deve confirmar titularidade, destinação e cadastro do webhook; produção envolve dinheiro real. Essa operação habilita o sistema, mas não executa cobrança, saque, pagamento ou devolução.
5. Registrar finalidade e pedido em Arrecadação digital. O checkout administrativo atual é iniciado por proprietário/administrador. Entrega pública de links em todos os fluxos do aplicativo/eventos ainda deve ser homologada no respectivo fluxo; não afirmar que qualquer visitante já dispõe de checkout anônimo.

A habilitação é por igreja/ambiente, não por uma variável global que libera todas as contas. Pix, cartão e boleto seguem a seleção; recorrência não é liberada neste conector. Alterar métodos, conta, beneficiários, titular ou revogar/bloquear a conexão retira a habilitação. A confirmação do usuário de que cadastrou o webhook não equivale a uma entrega externa comprovada.

Notificações usam a assinatura do próprio recebedor, exigem o titular e ambiente correspondentes e consultam o pagamento na API. Valores/status do POST não são prova financeira. Credenciais OAuth antigas podem usar o segredo global anterior, mas não ganham habilitação automática de produção. São preservados os controles de idempotência, taxas, conciliação e período fechado.

## Asaas

API Key é suficiente para a identificação; não se pede Public Key. O código consulta informações comerciais e identificação de conta nos hosts oficiais separados de sandbox/produção. Asaas tem testes internos com respostas fictícias, mas não há conta/chave de teste disponível nesta tarefa para homologação externa de cobrança, webhook, taxa ou liquidação. A consulta cadastral não habilita automaticamente o checkout digital da igreja, que ainda é específico do Mercado Pago.

## Safe2Pay

O usuário informou possuir chave, mas não poder cadastrá-la agora. Ela pode ser guardada no cofre com estado pendente, sem simular validação ou ativação. A documentação atual usa `X-API-KEY` e distingue APIs de pagamento, API geral e serviços; não se deve reutilizar silenciosamente contratos legados de outro conector. Identificação de estabelecimento, checkout, notificações, taxas e liquidação exigem implementação/homologação contra a conta de teste correta antes da liberação.

## Evidências e limitações

Testes locais/CI usam somente credenciais e pessoas fictícias. São cobertos isolamento, função técnica inacessível ao navegador, versões obsoletas, assinatura por recebedor, titular/ambiente divergentes, confirmação explícita e ausência de lançamentos ao configurar. Teste interno não equivale a transação externa liquidada. Nenhuma cobrança real deve ser criada pelo agente para demonstrar funcionamento sem valor/finalidade e confirmação apropriados.

Fontes oficiais consultadas:

- https://www.mercadopago.com.br/developers/pt/docs/checkout-api-orders/resources/credentials?scope=prod
- https://www.mercadopago.com.br/developers/en/reference/online-payments/checkout-api/payment-methods/get
- https://docs.asaas.com/docs/about-webhooks
- https://developers.safe2pay.com.br/reference/autentica%C3%A7%C3%A3o
- https://developers.safe2pay.com.br/reference/arquitetura-da-api
