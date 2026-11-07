# Escalas — análise e plano de desenvolvimento

Análise do código disponível em 07/11/2026. Não houve alteração de operações nem publicação nesta análise. Telas antigas e definições de tabelas não comprovam funcionamento em produção.

## Situação encontrada

- `app/ScaleOperations.tsx`: cadastro de escala, vínculo opcional com evento, chegada da equipe, posições por ministério, voluntários, vagas e indicadores de confirmação/conflito. Não recebe a unidade selecionada no painel e consulta `/api/scales` sem esse contexto explícito.
- `app/api/scales/route.ts`: implementação antiga em Cloudflare/D1, com consulta que também cria ministérios padrão. Os métodos exportados estão bloqueados por `withLegacyContainment`.
- `app/VolunteerScaleApp.tsx` e `app/api/app/scales/route.ts`: confirmação/recusa, indisponibilidade e pedido de substituição. Dependem da sessão e dos cadastros antigos; endpoint e página direta contidos.
- `app/api/scales/leadership/route.ts`: atribuições, análise de trocas e inclusão de lembretes na fila, também contido. Registrar na fila não comprova entrega.
- `app/escalas/layout.tsx`, `app/app-voluntario/layout.tsx`, `app/lib/release-availability.ts`: o módulo permanece em desenvolvimento e as páginas antigas não são montadas para uso real.
- `drizzle/0028_schedule_operations.sql`, `0029_volunteer_schedule_responses.sql`, `0030_schedule_leadership.sql`: desenho anterior de equipes, funções, posições, indisponibilidades, substituições e lembretes. Não equivale a migração operacional para a base atual.
- Não foram encontrados arquivos de testes específicos de Escalas nas pastas `scripts` e `supabase/tests`; existem testes gerais de contenção.

## Problemas que o desenvolvimento deve resolver

1. Migrar os fluxos para a autenticação, Pessoas, eventos e igrejas atuais, sem apenas retirar os bloqueios das rotas antigas.
2. Distinguir o ministério contratante da Vinha das equipes de serviço: Louvor, Recepção, Mídia, Kids etc. Equipes pertencem a uma igreja; abrangência em outras igrejas exige autorização explícita.
3. Restringir consultas e alterações por igreja, equipe, função e usuário. O líder não deve receber a lista irrestrita de todos os membros, nem administrar equipes fora de seu escopo.
4. Substituir a proximidade fixa de três horas pela interseção real entre chegada/início/fim, incluindo ensaios e eventual intervalo de deslocamento configurado. A troca aprovada deve repetir essas verificações dentro da mesma transação.
5. Separar vaga, convite pendente, confirmação, recusa, pedido de troca e presença no serviço. Conflito é uma condição adicional; não deve apagar a resposta da pessoa.
6. Garantir que respostas do voluntário pertençam a uma escala publicada e à sua própria identidade vinculada. A preferência de igreja para conteúdo no aplicativo não concede acesso a escalas de outra igreja.
7. Distinguir confirmação pessoal de registro pela liderança, com responsável, data e motivo. Não confirmar silenciosamente em nome da pessoa.
8. Oferecer edição, cancelamento, duplicação e recorrência com tratamento explícito das ocorrências e preservação de respostas/histórico. Publicação não pode disparar convites duplicados.
9. Trocar listas completas por busca e paginação; tratar falha, carregamento e ausência de dados separadamente. Remover ações sem operação, como o botão de reticências sem menu implementado.
10. Reutilizar notificações reais da Vinha. Não criar chat automático como dependência da publicação: o chat antigo não remove participantes substituídos e exige tratamento próprio de acesso e retenção.

## Plano em cinco etapas

### 1. Base, equipes e permissões

Criar a estrutura atual no Supabase para equipes de serviço, funções, integrantes, responsáveis e preferências. Vincular integrantes ao cadastro de Pessoas e, quando existente, à conta de usuário. Um membro sem conta pode ser escalado pela secretaria, mas não recebe acesso ao painel por esse vínculo. Permissões distintas para administrar o módulo, gerenciar equipes determinadas, publicar, atribuir pessoas, acompanhar e responder às próprias escalas. Usar permissões atuais da plataforma; não criar autenticação separada.

Incluir histórico, controle de versão, operações repetidas sem duplicação e proteção de acessos por ministério contratante e igreja. Avaliar a existência de dados antigos antes de decidir importação; não presumir que estão disponíveis ou podem ser descartados.

**Aceite:** equipes e integrantes persistem; líder de uma igreja/equipe não consulta ou altera outra; perda de permissão é respeitada; nenhuma atribuição amplia automaticamente o acesso administrativo.

### 2. Planejamento e nova experiência visual

Menu Escalas com Visão geral, Calendário e escalas, Equipes e funções, Pendências e trocas, Relatórios. Preferências dentro do próprio módulo, sem submenu excessivo. Manter a expansão lateral somente no módulo em navegação.

Calendário mensal/semanal e lista, filtros por período, igreja, equipe e situação. Cadastro com igreja, título, evento opcional, local, chegada, início e término, coordenador e observações. Equipes/funções com quantidade necessária, integrantes e vagas em aberto. Vincular eventos existentes sem duplicá-los ou tornar obrigatório criar um evento.

Permitir salvar rascunho, editar, duplicar e gerar recorrências com prévia das datas. Ao editar série, escolher ocorrência atual, próximas ou série inteira; avisar sobre ocorrências já confirmadas e nunca sobrescrever silenciosamente. Exibir confirmação de impacto antes de publicar alterações relevantes de uma escala já publicada.

**Layout:** verde institucional, fundo claro, tipografia e espaçamento da Vinha. Título e ação principal no cabeçalho; indicadores compactos; área central de trabalho sem pilhas de cards. Detalhe da escala com Resumo, Equipes, Respostas e Histórico. Campos com rótulos persistentes, caixas de seleção alinhadas, foco visível, nomes longos com quebra adequada e adaptação móvel. Situação descrita em texto, além da cor.

**Aceite:** escala completa pode ser montada sem trocar de módulo; calendário e lista mantêm filtros; navegação e formulário funcionam em celular e teclado.

### 3. Operação, conflitos e aplicativo

Publicar convites individuais; confirmar/recusar pelo aplicativo com a mesma conta. Mostrar horário de chegada, serviço, equipe, função, local e instruções pertinentes. Disponibilidade recorrente e indisponibilidades por período, com edição/cancelamento e recálculo dos conflitos. Motivos pessoais não ficam expostos para toda a equipe.

Detectar sobreposição real, dupla atribuição incompatível, indisponibilidade e função não habilitada. Sugestões consideram habilitação, disponibilidade e carga recente, com escolha humana. Definir funções que podem coexistir no mesmo serviço; exceções justificadas somente por responsáveis autorizados.

Pedido de substituição com sugestão opcional entre pessoas aptas e autorizadas. Aprovação verifica novamente conflito e disponibilidade; novo voluntário recebe convite pendente, não confirmação automática. Registrar presença e ausência separadamente da confirmação, além de cancelamento e encerramento do serviço.

**Aceite:** duas alterações simultâneas não sobrescrevem respostas; voluntário responde apenas ao próprio convite; troca não mantém acesso indevido à equipe anterior; presença não é inferida a partir do aceite.

### 4. Comunicação, integrações e relatórios

Central de pendências por prazo, vagas e trocas. Avisos no aplicativo, lembretes e comunicação de mudanças/cancelamento, com prevenção de duplicidade e limites de reenvio. E-mail e push somente quando configurados e homologados; estados distintos para programado, processando, enviado, entregue quando comprovado e falha. Sem Firebase/Expo configurado e teste em aparelho, push permanece pendente.

Integrações com Agenda/Eventos, equipes Kids e Louvor usando os cadastros existentes. Estar escalado no Kids não concede acesso a informações sensíveis das crianças. Exportação PDF/planilha e calendário pessoal opcional com link privado revogável; não prometer sincronização bidirecional com Google Agenda sem desenvolvimento e validação próprios. Chat de equipe é evolução independente, com autorização dinâmica e remoção de acessos após substituição.

Relatórios por período, igreja, equipe e função: cobertura de vagas, convites pendentes, confirmação/recusa, tempo de resposta, trocas, presença/ausência e distribuição de serviços. Definir denominadores: presença sobre pessoas efetivamente atribuídas ao serviço, confirmação sobre convites válidos, cobertura sobre vagas exigidas. Cancelamentos não contam como ausência. Motivos pessoais ficam fora de exportações gerais.

**Aceite:** totais conferem com os registros; exportações respeitam o mesmo acesso da tela; avisos têm resultado verificável e falhas não aparecem como entrega.

### 5. Homologação e liberação

Testes de isolamento entre ministérios e igrejas, escopo do líder, vínculo usuário/membro, data/fuso, virada de dia, recorrências, conflitos, idempotência, alterações simultâneas, trocas e cancelamentos. Revisão visual em desktop/celular, busca, paginação, mensagens de erro e acessibilidade. Validar migração em ambiente isolado e possibilidade de reversão da liberação sem apagar histórico.

Homologar com uma igreja e equipes reais autorizadas, incluindo pessoa sem conta, convite aceito/recusado, indisponibilidade posterior, substituição, mudança de horário e encerramento. Liberar somente os novos fluxos aprovados. Os endpoints antigos continuam bloqueados até sua substituição validada; não habilitar o módulo inteiro apenas mudando o catálogo de disponibilidade.

**Concluído quando:** a igreja monta e publica uma escala, o voluntário recebe e responde, o líder resolve a troca, a presença é registrada e os relatórios conferem, sem vazamento entre igrejas ou confirmação fictícia de entrega.

## Progresso da execução — S3

Em 07/11/2026, a operação S3 foi implementada: convites e respostas individuais, disponibilidade, habilitações e conflitos, substituições revalidadas e presença independente. A comunicação externa e os relatórios avançados permanecem no escopo S4. Evidências e limites em `evidencias/RECIBO-ESCALAS-S3-20261107.md`.
