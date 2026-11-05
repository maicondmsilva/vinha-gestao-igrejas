# Eventos e vendas — correções integradas — 05/11/2026

- Cards identificam Local/Local de retirada; eventos recebem número sequencial por ministério, mantendo as referências internas e links anteriores.
- Retirada pode começar antes do encerramento dos pedidos. Validação indica o campo que precisa de correção; datas de tickets e produtos usam horário de Brasília.
- Produtos/tickets sem aquisição podem ser editados e excluídos. Com histórico, somente ativação/desativação, preservando pedidos e cupons.
- Equipe organizadora busca membros ativos com conta confirmada e vínculo aprovado. Designações antigas continuam visíveis para revisão.
- Revisão cadastral compara cada campo atual/enviado e identifica correspondência por e-mail/CPF normalizado; não vincula automaticamente nem concede papel administrativo. Conteúdo público do aplicativo continua disponível durante revisão.
- Conferência financeira consulta o Mercado Pago somente com GET e recupera apenas uma preferência existente com titular, valor, referência e prazo verificados. Não confirma pagamento nem cria segunda cobrança.
- Recusas explícitas do provedor são diferentes de falhas ambíguas. Respostas e credenciais do provedor não são exibidas.

## Validação

594 testes Node aprovados; tipos, build, controles e verificação estática de segredos aprovados. 65 arquivos SQL, 2.988 verificações aprovadas. Homologação visual local confirmou o exemplo: pedidos até 08/11/2026 19h, retirada até 08/11/2026 21h, retirada a partir de 05/11/2026 20h. Dados fictícios somente.

## Limites da homologação real

Pedido de R$ 10 preparado anteriormente, sem pagamento confirmado, reteve tentativa sem link. Não houve pagamento/devolução real. A conta recebedora está configurada com Pix, cartão e boleto; a conferência deve identificar o impedimento efetivo antes de nova tentativa. SMTP de eventos e Firebase/Expo não estão configurados; entrega real de e-mail/push permanece pendente.
