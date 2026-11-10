# Agenda, inscrições gratuitas, tickets e caixa de entrada

Implementação compartilhada no portal do membro e no Android MPR-Igreja. A igreja acompanhada controla a programação pública e os avisos. O vínculo oficial de membro continua sujeito à aprovação da transferência; a seleção de conteúdo não concede permissão administrativa.

## Operação

Em Configurações → Serviços e segurança, selecionar a igreja da agenda. Criar rascunho com título, descrição, data e horário de Brasília/São Paulo, local público e vagas. Publicar explicitamente. Atualizações usam versão para impedir sobrescrita concorrente; cancelamento é confirmado e não é reversível.

Uma conta confirmada, ativa e vinculada a uma pessoa ativa pode se inscrever gratuitamente antes do início. Uma conta recebe um ticket por evento. Repetição não duplica inscrição; cancelamento antes do início e da entrada libera vaga e invalida o código. Reinscrição gera novo código. A equipe valida o código textual na igreja do evento, entre duas horas antes do início e seis horas após o término. Repetir check-in retorna a entrada existente. Não há leitor de QR nesta entrega.

Notificações incluem publicações da igreja acompanhada, programação alterada, tickets e decisões privadas de cadastro/transferência. Lidas e não lidas são individuais. Atualização ao abrir/retomar ou atualizar manualmente e a cada minuto com a tela ativa. Android interrompe consultas em segundo plano. Não é push; nenhum aviso externo é enviado.

## Segurança e limites

- Tabelas privadas com RLS e sem acesso direto por clientes; funções verificam conta, ministério, unidade e contrato.
- Visitantes veem somente eventos publicados ou cancelados; nomes, inscrições e códigos são privados.
- Administração exige permissão de gestão da unidade e papel de proprietário, administrador ou pastor. Código de entrada revalida a situação da conta e pessoa.
- Mutação serializada impede ultrapassar vagas; check-in e repetição de inscrição são idempotentes. Escritas relevantes registram auditoria.
- Até 100 eventos, tickets recentes e notificações por consulta; inscritos exibidos até 500. Histórico público de eventos cobre um ano, publicações/alterações da igreja até 90 dias.
- Ingressos pagos, cobrança e push fora do aplicativo continuam pendentes de integração. Rotas antigas de eventos permanecem contidas.
- Datas e horários são armazenados com fuso e exibidos/editados em America/Sao_Paulo.

## Validação

39 verificações pgTAP locais aprovadas; teste com conexões concorrentes comprovou uma única inscrição para a última vaga e repetição sem duplicação. Quinze testes de rota e experiência Android aprovados. Fluxo HTTP local com conta fictícia: rascunho, publicação, inscrição, ticket, check-in, leitura e versão conflitante aprovados. Tipagem web/Android, compilação web e varredura de segredos conferidas. Testes operacionais não modificam membros ou eventos reais.

A migração 20261025155022 é aditiva. A publicação e o APK interno devem ser acompanhados pelo recibo da entrega; uma compilação interna não representa publicação no Google Play.
