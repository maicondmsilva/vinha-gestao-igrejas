# Eventos — etapa 3: operação e acompanhamento

A etapa 3 reúne Comunicação, Interessados e Financeiro no detalhe do evento, mantendo a navegação e as cores da Vinha. O endereço público e os tickets da etapa 2 continuam válidos.

## Uso pela igreja

Em **Comunicação**, crie um aviso, escolha o público e o horário e salve o rascunho. A programação exige confirmação separada. Os segmentos incluem inscrições confirmadas, reservas válidas, pagamentos pendentes, entrada registrada, ausência e interessados. O acesso do autor e a situação do participante são conferidos novamente antes da disponibilização e do processamento. Avisos de evento cancelado também podem informar participantes.

A caixa de entrada do membro apresenta os avisos no horário programado. Push depende da configuração do aplicativo. E-mail exige autorização expressa do comprador ou interessado, além do serviço habilitado. Não há autorização retroativa para pedidos antigos. O link de descadastro suprime próximos e-mails de eventos daquele ministério, sem cancelar conta ou ticket.

O processamento automático reaproveita a execução diária existente. Uma pessoa autorizada também pode processar os avisos vencidos do evento. O envio é individual, com reivindicação exclusiva; entregas incertas ficam em conferência e não são reenviadas automaticamente. Aceitação pelo servidor de e-mail não significa entrega garantida na caixa do destinatário.

Em **Interessados**, acompanhe pessoas que marcaram interesse na página pública. Somente a própria conta autenticada registra ou remove seu interesse. Isso não ocupa vaga, cria inscrição ou gera cobrança.

Em **Financeiro**, acompanhe valores informados pelo provedor, devoluções, pedidos a receber e pagamentos em conferência. A consulta respeita as igrejas recebedoras autorizadas. Reserva não é receita. Taxa desconhecida é sinalizada; conciliação e lançamentos continuam no módulo Financeiro. A lista contém os mil pedidos mais recentes e permite busca e exportação; os totais abrangem todos os pedidos autorizados.

## Cancelamento e reembolso

Inscrições gratuitas e reservas sem tentativa financeira podem ser canceladas com justificativa antes do check-in, preservando histórico. Pedidos com tentativa financeira exigem acompanhamento financeiro.

O comprador solicita reembolso pelo próprio pedido, usando sua conta ou o comprovante privado de visitante. A equipe financeira analisa e registra a providência realizada no provedor. Aprovar ou informar uma referência não transfere dinheiro. A solicitação só passa a concluída quando uma prova financeira verificada confirma o valor devolvido. Reembolso parcial, disputa e pagamento tardio continuam sob conferência quando necessário.

## Configuração e segurança

E-mail fica desabilitado até configurar separadamente `EVENT_EMAIL_ENABLED`, `EVENT_SMTP_HOST`, `EVENT_SMTP_PORT`, `EVENT_SMTP_USER` e `EVENT_SMTP_PASSWORD`, conforme a validação em `app/lib/event-email.ts`. Não reutilizar credenciais de autenticação. O remetente permitido é notificacoes@vinhaigrejas.com.br pelo serviço Hostinger, com TLS obrigatório. Segredos permanecem apenas no ambiente do servidor.

Todas as novas tabelas ficam privadas, com RLS e sem acesso direto dos clientes. As rotas validam sessão, origem, escopo do ministério, igreja, propriedade e versões dos registros. Visitante não obtém acesso a pedido de conta cadastrada pelo simples conhecimento do e-mail. Solicitações e alterações administrativas são auditadas.

## Validação

- 564 testes da aplicação e 2.850 verificações de dados em 60 arquivos.
- 102 verificações do fluxo integrado da etapa 3, incluindo regressões de tickets.
- Reivindicações simultâneas de e-mail sem destinatário duplicado; nenhum SMTP real nos testes.
- Tipagem da plataforma e Android, montagem de publicação, segredos e ações da interface.
- Revisão local de Comunicação, Interessados e Financeiro, com rascunho fictício e layout em 390 px.

Esta entrega não distribui novo APK, envia campanhas reais ou executa devoluções. A ativação dos provedores externos permanece dependente das configurações do ministério.
