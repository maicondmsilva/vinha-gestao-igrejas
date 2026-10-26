# Mídia, abertura e operação das igrejas — 26/10/2026

Entrega integrada ao cadastro de ministério e à igreja local selecionada. Nenhuma alteração de papel, transferência cadastral ou custódia é feita ao assistir, imprimir ou publicar conteúdo.

## Funcionalidades

- Catálogo de vídeos e lives por igreja, com rascunho, publicação, revisão e arquivamento auditados. YouTube e Vimeo usam seus players oficiais; arquivos MP4 e HLS usam players web e Android. O cadastro não cria um servidor de produção/ingestão de vídeo.
- Favoritos e progresso de MP4 pertencem à conta. Vídeos incorporados mantêm os controles do próprio provedor; não há leitura de progresso de YouTube/Vimeo. O indicador de live conta contas autenticadas conectadas nos últimos dois minutos, e não mede audiência total.
- Android: cópias offline de MP4 somente com autorização explícita da igreja, limite de 100 MB e armazenamento separado por ministério/conta. YouTube, Vimeo e HLS não são baixados. Uma cópia já autorizada pode permanecer com o membro mesmo depois do arquivamento da publicação.
- Abertura por ministério: foto ou MP4 sem som, máximo de 15 segundos, pular/encerrar em erro e respeito à redução de movimento. Cores e logo continuam no cadastro oficial. A consulta tem limite de espera de três segundos.
- Eventos: a tela principal usa a agenda canônica existente, inscrições e validação de entrada; configuração de ingresso pago reutiliza o serviço de pagamento. Rotas antigas seguem bloqueadas. Lotes, cupons, assentos e reembolsos automáticos não foram acrescentados.
- Comunicação: avisos públicos por igreja e catálogo de mídia. Conversas privadas, anexos internos de chat e envio externo de WhatsApp/e-mail continuam fora desta entrega.
- Transmissões: links de canais oficiais, programação em horário de Brasília, estado ao vivo/encerrado e reprodução no aplicativo. Não há RTMP, gravação automática nem promessa de transmissão real sem um canal configurado.
- Kids: QR do comprovante, leitura opcional pela câmera compatível e campo manual preservado; impressão A4/80 mm pelo computador, sem criar nova presença. A retirada mantém a conferência de identidade e o código completo. Materiais textuais e links públicos autorizados, resumo de presença por sala e ocorrências/chamados internos restritos. Somente gestão/supervisão conclui ocorrências. Ocorrências não alteram custódia nem enviam notificações externas.

## Segurança e acesso

Tabelas novas privadas, RLS habilitado sem acesso direto. RPCs usam identidade confirmada, ministério, igreja, contrato e papéis existentes. Ocorrências só são lidas por supervisão ou professores autorizados da sala; recepção não recebe os textos restritos. Eventos e publicações não usam identificadores fornecidos pelo navegador para representar outra conta. Revisões simultâneas falham com conflito; atualize antes de repetir.

## Validação

- Suíte local do banco: 54 arquivos, 2.538 verificações, aprovada.
- Testes de mídia: provedores, protocolos, limites e abertura; testes de navegação Android e contenção das rotas antigas.
- Compilação web e verificação TypeScript web/Android.
- Player web MP4 carregado, reproduzido por controle da tela e concluído em 5,055 segundos (amostra pública CC0 MDN, apenas no banco fictício). Evidência: docs/evidencias/midia-player-local-20261026.png.
- Abertura de vídeo configurada pelo formulário local e consumida pelo portal sem bloquear o acesso após o encerramento.
- Live fictícia criada/publicada apenas no banco local de homologação. Nenhuma transmissão, ocorrência ou cadastro fictício é criado na produção pela migração.

## Dependências externas

Não há impressora física disponível para homologação. Câmera exige navegador compatível, contexto seguro e autorização do operador; o código manual permanece disponível. Push em aparelhos reais e publicação em lojas continuam dependendo das contas/projetos já registrados como pendentes. O APK é interno e usa assinatura de teste; não equivale a publicação no Google Play. Homologação de reprodução, impressão e câmera em aparelhos reais deve usar os equipamentos da igreja.
