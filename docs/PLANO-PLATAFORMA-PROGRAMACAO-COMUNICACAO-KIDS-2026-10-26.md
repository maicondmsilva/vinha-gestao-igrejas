# Plano de evolução da plataforma Vinha

Data: 26/10/2026. Situação: proposta para a próxima entrega; não representa funcionalidades já publicadas. O aplicativo Android fica fora desta etapa.

## 1. Referências e diagnóstico

Referências: duas imagens administrativas enviadas pelo usuário (Conteúdo/Pregações e Programação/Agenda), capturas anteriores do aplicativo inChurch e código atual da Vinha. As imagens evidenciam navegação, listagens e calendário; não comprovam o funcionamento interno, integrações ou regras comerciais da inChurch. Não foram recebidas nesta mensagem telas administrativas detalhadas de Kids ou de configuração de eventos; propostas nessas áreas partem da Vinha e das necessidades já discutidas.

As referências organizam o trabalho em módulo, submenu e página. Oferecem título e ações em uma barra, listagens com capa, situação, autoria e paginação, além de calendário com seleção de dia. A Vinha deve adotar essa clareza preservando sua identidade visual.

No código atual, o menu principal é plano para Eventos, Comunicação e Transmissões. A agenda está incorporada ao cadastro de eventos; Comunicação reúne avisos e vídeos; abertura aparece no administrador de mídia. Isso dificulta localizar tarefas e torna formulários longos. O cabeçalho contém busca sem fluxo de resultados e um contador fixo de notificações: deverão ser funcionais ou removidos até sua implementação.

| Área | Base encontrada | Evolução necessária |
| --- | --- | --- |
| Agenda e eventos | Rascunho, publicação, cancelamento, vagas, inscrições, tickets, entrada e serviço de preço | Calendário dedicado, filtros, páginas por situação, editor organizado e operação financeira contextual |
| Comunicação | Avisos públicos e mídia por igreja | Separar avisos, catálogo e notificações; busca, categorias, paginação e ciclo editorial |
| Ao vivo | Links YouTube/Vimeo/MP4/HLS, horários e estados de publicação | Canais próprios, programação, operação de transmissão e encerramento com eventual vídeo associado |
| Kids | Cadastros integrados a Pessoas, responsáveis, salas, turmas, equipe, sessões, entrada/retirada, exceções, ocorrências e materiais | Navegação por tarefa, estação de recepção, melhor apresentação de presença e homologação de impressão/câmera |
| Layout | Componentes e estilos existentes, mas com padrões diferentes | Estrutura comum de páginas, tabelas, filtros, formulários, estados e ações |

## 2. Menu lateral proposto

Uma barra lateral, com grupos expansíveis e até três níveis quando necessário. Desktop: rótulos visíveis, modo compacto opcional. Celular/tablet: gaveta com identificação da igreja. Evitar uma segunda barra fixa larga que reduza a área útil.

```text
Início
Pessoas
Famílias e termos
Células
Escalas
Louvor
Programação
  Agenda da igreja
  Eventos
    Próximos
    Encerrados
    Todos e rascunhos
  Categorias de eventos
  Ao vivo
    Canais
    Transmissões
Comunicação
  Visão geral
  Avisos e notícias
  Conteúdos
    Vídeos e pregações
    Categorias
  Notificações
    Campanhas push
    Histórico de envios
  Banners e atalhos
  Arquivos e downloads
Área Kids
  Visão geral
  Recepção: entrada e retirada
  Crianças e responsáveis
  Sessões
  Turmas e salas
  Equipe
  Ocorrências e chamados
  Materiais
  Presenças e histórico
Financeiro
Relatórios
Aplicativo do membro
Configurações
```

As páginas ainda não implementadas não devem aparecer como recursos ativos. Rádio, chat e envio externo não entram automaticamente por existirem na referência. Jornadas e planos de leitura existentes continuam na administração atual até sua navegação ser avaliada; não duplicar cadastros.

Configurações mantém identidade, igrejas/unidades, usuários/permissões e integrações. Aplicativo do membro mantém personalização, abertura e organização da experiência. Logo, dados cadastrais e cores usam a fonte oficial existente; cada igreja conserva seu cadastro próprio. Os atalhos antigos continuam abrindo os destinos equivalentes, preservando ministério e unidade.

## 3. Padrão visual e de navegação

- Cabeçalho com logo oficial, ministério e igreja selecionada; o contexto acompanha todas as páginas e operações.
- Caminho de navegação, título, descrição curta e uma ação principal: Novo evento, Publicar aviso ou Nova transmissão.
- Busca da página, filtros e ações secundárias em barra consistente. Filtros ativos visíveis e opção Limpar.
- Listagens com ordenação, paginação no servidor e estados de carregamento, vazio, erro e acesso insuficiente.
- Tabelas com cabeçalho legível, capas pequenas quando úteis, situação por texto e cor, menu de ações por linha e confirmação contextual para ações relevantes.
- Edição em página ou painel lateral; formulários extensos divididos em seções claras, sem empilhar cadastros independentes na mesma página.
- Resumos somente com dados reais, incluindo data da consulta. Não exibir números fictícios nem apresentar ausência de dados como falha.
- Tipografia, cores Vinha, espaçamento, bordas, ícones e botões padronizados; contraste, foco, teclado e nomes acessíveis.
- Em telas pequenas, filtros recolhíveis e tabelas adaptadas. Não depender de rolagem horizontal para a ação principal.
- A busca global só será exibida quando houver resultados autorizados e navegação funcional. Contador de notificações somente a partir da caixa real da conta.

## 4. Agenda e eventos

Agenda: visualizações mensal, semanal, diária e lista; Hoje, anterior/próximo, mini calendário e seleção do dia. Indicadores de dias com programação, filtro por categoria, tipo, situação e igreja autorizada. Datas no fuso da igreja, começando pelo fuso já utilizado. Distinguir horário do evento, período de inscrição e publicação.

A agenda será uma visualização da mesma base de eventos, não outro cadastro. Cultos recorrentes precisam de série com ocorrências próprias, exceções e edição de uma ocorrência ou das futuras. Integração de sessões Kids e transmissões será por vínculo explícito; não criar nem abrir sessões automaticamente.

Eventos: páginas Próximos, Encerrados e Todos/rascunhos, com busca e totais reais. Editor com informações, capa, categoria, local, período, visibilidade, capacidade e inscrições. Inscritos, tickets, pagamento e check-in ficam dentro do evento. Trazer a configuração de preço para esse contexto, reutilizando o serviço financeiro existente.

Ampliações comerciais posteriores: modalidades de ingresso, lotes com período/quantidade, formulários adicionais, lista de espera, cupons e política operacional de cancelamento/reembolso. Dependem de desenho transacional e compatibilidade com o provedor; não expor tela sem validação completa. Mapa de assentos fica fora da entrega inicial.

Aceite: editar um evento atualiza calendário e listagens; lotação não pode ser excedida em solicitações simultâneas; ticket cancelado/reutilizado não libera nova entrada; pagamento só é confirmado pelo fluxo verificado; mudança de igreja não mistura inscrições.

## 5. Comunicação e conteúdo

Separar o catálogo de vídeos das notícias. Lista de conteúdos com capa, título, categoria, igreja destinatária, autor, publicação e situação. Busca, filtros, paginação e edição sem abrir todos os formulários simultaneamente.

Notícias e avisos: rascunho, revisão/publicação conforme permissão, agendamento, expiração opcional, prévia e histórico. Banners e atalhos: imagem, ordem, destino permitido, período e igreja. Arquivos: categorias/pastas, tipo/tamanho, acesso autorizado e arquivamento. Reutilizar o que já existir após inventário, sem segundo catálogo paralelo.

Push: campanhas com público explícito, prévia, agendamento, autorização, fila, repetição segura e histórico. Firebase/Expo ainda dependem de configuração; mostrar estado de integração e impedir falso envio. Diferenciar aviso público de mensagem privada e não presumir WhatsApp/e-mail disponíveis.

Métricas com definição: reproduções, usuários únicos e permanência não são equivalentes. Não usar a contagem atual de contas conectadas como audiência total. Só apresentar métricas efetivamente instrumentadas e com período/fonte identificados.

Aceite: rascunho não aparece ao público; agendamento respeita fuso e cancelamento; público não recebe dados restritos; repetição de tarefa não duplica campanha; erro do provedor não vira sucesso na tela.

## 6. Ao vivo

Cadastro de canais por igreja: nome, provedor, endereço/identificador, imagem e situação. Transmissão referencia canal e pode ter link específico, título, capa, descrição, início/fim, visibilidade e evento associado.

Listas de programadas, em andamento e encerradas; prévia antes da publicação; ações explícitas de publicar, iniciar estado ao vivo, encerrar e arquivar. Deixar claro quando o estado é manual; verificar provedor somente com integração real. Encerramento pode associar uma gravação autorizada ao catálogo sem duplicar mídia.

Monitorar disponibilidade e falhas de reprodução, distinguindo resultado do teste de link de garantia de transmissão. RTMP, encoder, gravação automática, rádio e infraestrutura própria de streaming exigem projeto separado.

Aceite: programação por igreja, estados coerentes, link inválido identificado, gravação associada uma vez e audiência descrita corretamente.

## 7. Kids

Preservar as regras de proteção já implementadas. Melhorar o acesso às tarefas, separando recepção, supervisão, cadastros e preparação de sessões. Indicadores de presença, capacidade e equipe por sala precisam mostrar última atualização e respeitar permissões.

Estação de recepção com sessão visível, busca rápida, responsável autorizado, confirmação de entrada, comprovante e fluxo de retirada. QR/código auxilia a conferência; nunca substitui a autorização e a identidade do adulto. Tela da equipe restrita às suas salas; cuidados e ocorrências não aparecem em listagens públicas.

Impressão: prévia, reimpressão auditada e modelos compatíveis com A4/80 mm; criar modelo de etiqueta após escolha do equipamento. Etiqueta de identificação visível deve ser distinta do comprovante secreto de retirada. Homologar câmera, cancelamento de permissão e alternativa manual. Impressora ainda não disponível.

Ocorrências/chamados: lista própria, filtros por sessão/situação, detalhe restrito e resolução pela supervisão. Materiais com lista e editor próprios. Relatórios de frequência, ocupação e equipe com filtros e exportação somente dos dados permitidos.

Aceite: entrada/retirada simultânea segura, autorização revogada respeitada, proteção e transferência preservadas, impressão não cria presença, reimpressão não divulga segredo recuperável, recepção não vê ocorrências restritas e falha de conexão não informa retirada confirmada.

## 8. Ordem de execução e dependências

1. Consolidar inventário de páginas, rotas, permissões e cadastros existentes; definir componentes visuais e protótipo navegável de Programação/Comunicação/Kids.
2. Implementar menu e estrutura comum; migrar rotas com compatibilidade; corrigir cabeçalho e manter seleção da unidade em navegação/recarregamento.
3. Entregar Agenda e reorganização de Eventos reutilizando a base canônica; em seguida recorrência e ampliações de inscrição aprovadas.
4. Separar Comunicação, catálogo e Ao vivo; implementar categorias, listagens e canais; mover abertura ao local adequado mantendo fonte oficial.
5. Reorganizar a operação Kids e relatórios; homologar recepção e impressão com alternativa manual preservada.
6. Integrar publicações agendadas e campanhas push após configuração; ampliar inscrições comerciais conforme suporte do provedor.
7. Validar ponta a ponta, acessibilidade, tela pequena, segregação de igrejas e concorrência; publicar com migrações compatíveis, acompanhamento de erros e possibilidade de retorno da interface.

As etapas definem dependências do trabalho; o resultado esperado é uma experiência integrada, não telas isoladas. Não há prazo fechado antes do inventário e do desenho dos fluxos comerciais.

## 9. Critério de conclusão da entrega

Menu coerente e sem destinos vazios; Agenda ligada aos mesmos eventos; editor e listagens uniformes; conteúdo e lives separados; Kids operável por função; dados reais por igreja; permissões conferidas no servidor e não só no menu; testes de gravação/consulta/edição/cancelamento, concorrência e acesso negado; migrações verificadas e publicação confirmada. Integrações ou equipamentos pendentes são registrados como pendentes, sem simular disponibilidade.

## 10. Base consultada

- app/DashboardApp.tsx: menu, rotas, cabeçalho e encaminhamento dos módulos.
- app/EventsWorkspace.tsx e app/MemberAgendaAdmin.tsx: agenda, edição, inscrições e entrada.
- app/CommunicationWorkspace.tsx e app/MinistryMediaAdmin.tsx: avisos, mídia, lives e abertura.
- app/KidsOperations.tsx, app/KidsFoundation.tsx, app/KidsNotes.tsx e app/KidsResources.tsx: operação e regras Kids.
- docs/MIDIA-ABERTURA-OPERACOES-2026-10-26.md e docs/KIDS-K2-OPERACAO-PRESENCIAL-2026-10-24.md: entregas e limites. O documento de mídia mais recente atualiza as pendências antigas de QR, materiais e ocorrências do guia K2.
