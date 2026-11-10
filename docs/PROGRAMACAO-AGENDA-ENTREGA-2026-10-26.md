# Layout, navegação, Agenda e Eventos

Entrega de 26/10/2026. Usa a mesma base de eventos, inscrições e tickets da Vinha. Não altera o aplicativo Android, não cria cadastro paralelo e não amplia papéis de acesso.

## Navegação e interface

- Programação: Agenda da igreja, Eventos próximos, Encerrados, Todos e rascunhos, Categorias e Ao vivo/Transmissões.
- Comunicação: avisos e vídeos em páginas separadas, reutilizando os recursos já publicados. Demais ampliações editoriais permanecem na próxima entrega.
- Cabeçalho sem busca global inoperante nem contador fictício. Igreja selecionada e identidade oficial preservadas.
- Tipografia, espaçamento, campos, botões, tabelas, avisos, confirmações, foco e navegação móvel padronizados nas novas páginas. A recepção Kids e os demais módulos conservam seus fluxos.
- Configurações aponta para a agenda canônica em Programação. Endereços antigos de Eventos e Transmissões continuam válidos.

## Agenda e eventos

- Calendário mensal com contagem real por dia, consulta semanal e diária em lista, Hoje, navegação de período e seleção direta de data. Eventos que atravessam meia-noite aparecem nos dias correspondentes; contagens não dependem da página da lista.
- Busca, categoria, tipo, situação, ordenação e paginação no servidor. Mais de cem eventos podem ser consultados; não se carrega somente a lista legada limitada.
- Categorias por igreja com cor, versão e arquivamento sem apagar histórico.
- Editor com informações, capa HTTPS, categoria, data/local, capacidade e repetição diária/semanal/mensal. Até 52 encontros, em rascunho e dentro do horizonte de dois anos permitido pela base canônica. Meses curtos usam o último dia disponível, ancorado no dia original.
- Cada ocorrência tem suas próprias vagas, preço, inscrições e tickets. Alteração isolada ou das ocorrências futuras não canceladas; no segundo caso desloca os horários pela mesma diferença e aplica os demais campos do editor ao conjunto.
- Publicação/cancelamento isolado ou futuro exige confirmação e comparação das versões do conjunto. Qualquer falha reverte a operação inteira. Versão antiga exige atualização.
- Criação com recibo por tentativa/conta/igreja impede duplicação por reenvio. Alterar o conteúdo da mesma tentativa após resposta incerta é recusado: consulte a lista antes de abrir outro cadastro.
- Detalhe com informações, inscritos/check-in paginados e preço do próprio evento. Preço reutiliza o serviço financeiro existente, exige rascunho e condições do provedor; alteração de preço invalida a revisão antiga do detalhe. Redução de capacidade considera também reservas pagas pendentes ainda vigentes.
- Nenhum envio externo, cobrança real, reembolso ou sessão Kids é criado pela migração. O cancelamento invalida a entrada dos tickets, sem executar reembolso automático.

## Segurança e verificação

Novas tabelas privadas com RLS, sem acesso direto de anon/authenticated/service_role. RPC pública invocadora chama a função privada com identidade confirmada, vínculo ativo, igreja autorizada, contrato e papéis canônicos. Histórico de eventos reutiliza a auditoria existente; categorias também são auditadas. Regras de inscrição, pagamento e entrada permanecem nas funções canônicas. Fontes de referência para funções e privilégios: https://supabase.com/docs/guides/database/functions.

Testes: calendário, meses curtos e bissextos, payloads adulterados, API sem sucesso falso, segregação de ministérios/unidades, paginação acima de cem, categorias, repetição segura, versões e preço. Teste com conexões concorrentes comprova uma série/um recibo para duas tentativas e apenas uma publicação com a mesma revisão. A suíte SQL completa e a compilação são critérios de publicação; resultado final consta no recibo de evidências.

Conferência visual local: categoria criada pela tela; série semanal de quatro cultos fictícios criada/publicada; calendário consultado; ingresso gratuito atualizado no detalhe; menu e layout móvel conferidos em 390 × 844. Evidências em docs/evidencias/programacao-agenda-local-20261026.png e programacao-mobile-20261026.png. Dados exclusivamente fictícios no banco local.

## Limites desta entrega

Não inclui lotes, cupons, mapa de assentos, lista de espera, formulários adicionais de inscrição, reembolso automático, produção RTMP nem novas integrações push. A gestão existente continua restrita aos papéis canônicos de administração/pastorado; esconder ou mostrar o menu não concede acesso. O painel de Ao vivo foi reposicionado no menu; sua ampliação funcional e a operação Kids continuam nas entregas próprias do plano.
