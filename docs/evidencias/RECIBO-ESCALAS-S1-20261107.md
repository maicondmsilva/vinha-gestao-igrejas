# Escalas S1 — base, equipes e permissões

Nova base privada para equipes locais, funções/vagas, integrantes canônicos de Pessoas, responsáveis, preferências e histórico. Não cria usuários, não altera papéis da plataforma e não concede permissões de outros módulos.

O painel monta somente a nova interface de cadastros. Os endpoints antigos de planejamento, liderança e aplicativo continuam contidos; os próximos fluxos não foram anunciados como disponíveis.

Isolamento por organização/igreja, acesso real à unidade, contrato de Escalas/Pessoas, delegação específica por equipe, identidade vinculada e situação ativa são verificados novamente no banco. Administração do módulo restrita a owner/admin; responsáveis delegados gerenciam somente suas equipes. Atribuir e publicar são capacidades preparadas, sem expor essas operações antes das próximas etapas.

Gravações usam versão, identificador estável de solicitação, bloqueio transacional e recibo idempotente. Histórico anterior/posterior e autoria são preservados; inativação substitui exclusão física. Consultas não criam equipes padrão. Busca de Pessoas entrega somente nome, identificador e existência de conta na igreja autorizada; não expõe CPF, email, telefone ou dados de cuidado Kids.

Equipes têm paginação de 20 registros; integrantes, de 30. Busca de Pessoas limitada a 20 resultados a partir de duas letras. Cada equipe mantém prazo de resposta e antecedência de lembrete como preferências, sem disparar comunicação nesta etapa.

Legado: a inspeção do Supabase de produção encontrou People e memberships atuais, sem as antigas tabelas D1 de equipes/escalas. Os arquivos e endpoints D1 foram preservados. Nenhum dado antigo foi apagado ou presumido importado; uma eventual importação depende de obter e verificar a origem antiga.

Verificação inicial local: 45 testes SQL e seis testes de entrada/contrato. Incluem escopo de equipe, outra igreja/ministério, conta ausente, suspensão, revogação, transferência de pessoa, versões antigas, idempotência, paginação e proteção contratual. Tipos, build, verificação de segredos e botões passaram localmente. Foram aprovados também 32 testes JavaScript de Escalas/acesso/unidades/equipe e quatro de contenção. A validação integral em CI passou na revisão inicial. No navegador, foram verificados criação de equipe e função, busca/vínculo canônico, inativação/reativação e formulário de permissões. Janela revisada em desktop e 390 px, com checkbox de 18 px e sem transbordamento horizontal. Apenas dados fictícios do Docker foram alterados; nenhuma permissão de usuário real foi criada. A liberação de produção aguarda a revisão final.
