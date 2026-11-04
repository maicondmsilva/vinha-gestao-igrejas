# Recebimentos e meios de pagamento dos eventos

Contas recebedoras apresenta titular, destino, igrejas atendidas e Pix, cartão e boleto, com informações técnicas e histórico recolhidos. Datas e navegação duplicada foram retiradas desta página. Os campos de seleção mantêm o texto alinhado e os formulários funcionam em telas pequenas.

Cada igreja pode indicar uma conta principal por ambiente. A alteração exige proprietário/administrador, versão atual e uma conexão habilitada. A escolha é auditada e substitui a anterior atomicamente. Troca de chave, alteração que suspende a ativação e revogação removem a preferência; não habilitam pagamentos. A preferência é sugerida somente para um evento ainda sem configuração quando há uma única finalidade válida da conta principal na própria igreja. Finalidades e pedidos existentes mantêm o destino explícito.

O evento seleciona Pix, cartão e/ou boleto entre os meios habilitados da finalidade recebedora. O servidor rejeita métodos indisponíveis, duplicados e seleção vazia. Cada novo pedido pago ou reserva conserva os meios vigentes na criação. A entrega do checkout verifica a seleção contra os meios atuais da conta e falha com segurança se algum foi retirado. Pedidos anteriores à migração conservam o comportamento de herdar os meios do recebedor. Nunca se repete uma tentativa externa de resultado incerto.

Não foram inseridas credenciais, habilitados provedores, escolhidas contas reais nem executados pagamentos. As opções dependem da autorização e disponibilidade do provedor; conectores ainda não homologados continuam com recebimentos desabilitados.

Validação: testes de regras e API, pgTAP com autorização, unicidade da conta principal, troca auditada, preservação dos pedidos, restrição de métodos e revogação; compilação e revisão visual local de desktop e celular. Evidências e resultado de publicação ficam no recibo da entrega.
