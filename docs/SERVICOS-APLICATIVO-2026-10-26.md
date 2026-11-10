# Serviços do aplicativo — 26/10/2026

Integração ao cadastro oficial, por ministério e igreja local. Novas tabelas privadas usam RLS e não concedem acesso direto aos clientes. As operações validam a identidade confirmada no servidor. A implantação não publica finalidades, não emite carteirinhas reais e não ativa envios ou pagamentos automaticamente.

## Notificações no celular

Registro explícito de instalação, projeto e identificador do aplicativo; ativação/desativação pelo membro; acompanhamento da igreja selecionada; desvinculação no logout. A fila consulta a caixa privada existente, não mantém uma cópia de seu conteúdo. Na tela bloqueada aparece somente um aviso genérico. O toque abre a caixa da conta autenticada.

O processamento reserva mensagens, evita duplicação por aparelho/mensagem, consulta recibos do Expo e desativa tokens DeviceNotRegistered ou sessões revogadas. Falhas ambíguas ficam incertas, sem reenvio cego. Recibo de sucesso representa aceite pelo provedor, sem afirmar leitura pelo usuário.

**Ativação externa pendente:** o titular informou que ainda não possui projetos Firebase e Expo. Criar os projetos, definir identificador Android definitivo, configurar FCM v1/credenciais no Expo e gerar nova instalação com GOOGLE_SERVICES_FILE e EXPO_PROJECT_ID. Os arquivos e credenciais devem permanecer em ambiente protegido. O servidor precisa de configuração correspondente em member_push_apps, MEMBER_PUSH_ENABLED e, se a segurança adicional do Expo estiver habilitada, EXPO_ACCESS_TOKEN. Nunca colocar credenciais administrativas no APK.

O endpoint /api/member-push/run exige CRON_SECRET. O agendamento Vercel incluído é diário e serve apenas como rotina de manutenção; **antes de ativar push operacional, configurar um agendador frequente autorizado** para esse endpoint. A recepção real em aparelho fechado depende dessa configuração e de teste com dispositivo físico; não foi simulada como concluída.

## Contribuições

Finalidades são publicadas por administração em Configurações → Serviços e segurança. Cada finalidade mantém sua classificação contábil e conta recebedora canônicas. O catálogo do membro só mostra recebedor Mercado Pago de produção configurado, confirmado, vigente, com pagamentos e webhook habilitados e conta contábil compatível.

O membro cria pedido em centavos, consulta histórico privado e abre/retoma checkout hospedado. Repetições do mesmo identificador são idempotentes; valor/destino não podem ser alterados por repetição. A rota valida titularidade antes de usar o cofre do servidor e revalida antes de revelar o link. Nenhum dado de cartão é coletado pela Vinha. Provas de pagamento vêm da integração financeira existente, nunca do retorno do navegador.

Esta entrega oferece **contribuições avulsas**. Débito recorrente automático, novos provedores e execução de devoluções pelo aplicativo não estão implementados. Devoluções e pagamentos ambíguos exigem conferência pela equipe financeira/provedor; não há cobrança automática de teste em produção.

## Eventos e Meus Tickets

Preserva eventos gratuitos, inscrições, cancelamento, histórico, código individual e check-in existentes. O preço é configurado enquanto o evento é rascunho, vinculado a finalidade financeira de Eventos. Após publicar não se altera o preço de inscrições em curso.

Ingresso pago reserva uma vaga por 30 minutos e gera pedido financeiro. O ticket só é emitido após prova aprovada com valor suficiente. Duas contas não ocupam a última vaga; atualização da versão comercial do evento impede ultrapassar capacidade em snapshots antigos. Repetição de compra da mesma conta retorna o pedido existente.

Pagamento tardio, ausência de vaga, evento encerrado/cancelado ou identidade revogada não produz ticket válido e exige revisão financeira. Devolução/contestação invalida o ticket e gira seu código. Não existe promessa de devolução automática. A inscrição usa uma pessoa por conta; carrinho com múltiplos participantes e produtos adicionais não integra esta entrega.

## Carteirinhas

Administração emite categoria e validade para pessoa ativa da igreja, sem alterar cargo ou acesso. O titular consulta somente suas emissões, com nome e igreja canônicos. Revogação, vencimento ou mudança da igreja oficial invalidam o código. A verificação é restrita à equipe autorizada do mesmo ministério/igreja.

Portal exporta PDF com QR, marca e cor canônicas; Android apresenta os dados e compartilha texto/código mediante ação do titular. A versão Android não exporta imagem/PDF nativamente nesta entrega. O código é uma referência de conferência, não uma permissão de acesso nem comprovante de identidade fora da igreja.

## Evidências

44 testes SQL locais, testes de concorrência em read committed/repeatable read, testes de centavos/URLs e do transporte push com respostas simuladas. Nenhum push real foi enviado nos testes. Homologação visual local: emissão fictícia e download do PDF na conta titular. APK interno e publicação da plataforma são registrados no recibo da entrega; APK interno não representa publicação no Google Play.

Fontes: https://docs.expo.dev/push-notifications/sending-notifications/ e https://firebase.google.com/pricing.
