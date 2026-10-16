# L1 — bloco 7: privilégios estruturais e identidade de acesso

Base: 4e804baec9e6c48c1cb83e50867c061eaac10489. Data: 16/10/2026.
Conexão exclusiva: Supabase Vinha Igrejas, projeto aoxibaaydfgffrdqtkva.

## Escopo e aplicação

A inspeção da governança identificou uma prioridade técnica anterior à sucessão de responsáveis: permissões estruturais desnecessárias ainda concedidas aos papéis de cliente. Após testes isolados e autorização específica do responsável, aplicada a migração `20261016211048_access_identity_privileges.sql` no banco principal. Publicação versionada deve ser comprovada separadamente pelo PR e deployment.

Inventário remoto de leitura encontrou quatro poderes estruturais em 16 tabelas para authenticated, além de profiles para anon: TRUNCATE, REFERENCES, TRIGGER e MAINTAIN. TRUNCATE não obedece a políticas de linha. A presença desses grants não prova que exista um endpoint público capaz de executar SQL arbitrário; removê-los reduz privilégios desnecessários e consequências de outros defeitos. Nenhuma tentativa de esvaziar tabela real foi realizada na produção.

## Proteções implantadas

- Revogados os quatro poderes nas tabelas de public para PUBLIC, anon e authenticated. Não foram concedidos novos poderes CRUD, alteradas políticas de linha nem modificados os papéis de serviço.
- Privilégios padrão de novas tabelas criadas por postgres em public também deixam de conceder esses quatro poderes. Tabelas de outro criador, outros esquemas ou futuros GRANT explícitos exigem revisão própria. Os testes verificam nova tabela local, não apenas o catálogo atual.
- Participação existente não troca id, organização, conta autenticada ou data de criação por UPDATE de authenticated.
- Concessão de unidade existente não troca participação, organização, unidade ou data de criação por UPDATE de authenticated. Para novo destinatário/escopo, revogar a concessão antiga e criar outra pelo fluxo autorizado; não reutilizar sua identidade.
- Gatilhos são SECURITY INVOKER, com search_path vazio e sem execução direta para cliente/visitante. Não utilizam metadados editáveis do usuário para autorizar.
- Alterar unidade padrão, nível/herança de uma concessão e suspender uma participação continuam sujeitos às políticas anteriores. Cadastro inicial do ministério, convite/ativação e fluxos financeiros anteriores passaram na regressão.
- Sem exclusão, backfill, envio de mensagem, pagamento, alteração de preços ou credenciais.

## Verificação

- 663 verificações pgTAP em onze arquivos, com fixtures sintéticas e rollback: 199 anteriores e 464 novas. As novas incluem 440 verificações de grants (55 tabelas × 2 papéis × 4 poderes), 8 sobre uma tabela criada no teste para validar o padrão futuro e 16 casos de comportamento/identidade.
- Os comandos TRUNCATE de teste usam somente dados locais sintéticos e são recusados antes de apagar; não foram executados na produção. Incluídos TRUNCATE CASCADE recusado, troca de conta/id/ministério/data recusada, troca de destinatário/unidade da concessão recusada, atualização legítima de nível/herança/unidade padrão e suspensão administrativa preservadas.
- 54 testes de aplicação aprovados: 36 segurança/integridade, 4 contenção e 14 financeiro.
- Advisor de segurança local no nível warn sem avisos. Migração gerada por comparação do banco isolado e histórico local conferido. ACLs normalizadas do diff foram substituídas por REVOKE específicos, evitando reintroduzir ou ampliar CRUD. Compilação de funções habilitada e limites de lock/execução mantidos.
- Versão local gerada inicialmente 20261016210904; arquivo conciliado com versão principal 20261016211048 após aplicação autorizada. Nenhuma migração anterior foi reescrita.
- Pós-conferência principal: zero grants estruturais restantes para os dois papéis nas tabelas públicas; dois gatilhos habilitados; execução invoker; chamada direta negada; RLS das participações/concessões preservada. Nenhum cadastro de cliente foi alterado para simular testes.
- Avisos remotos anteriores permanecem: [funções públicas privilegiadas para visitantes](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [funções privilegiadas para autenticados](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [eventos internos com RLS sem política](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) e [proteção contra senhas comprometidas desativada](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Não é certificação de segurança integral.

## Limites e próximo bloco

Este é o primeiro recorte da governança, não seu encerramento. Não altera ainda quem pode conceder owner/admin/pastor, não protege o último proprietário do ministério contra suspensão/rebaixamento/exclusão nem valida concorrência entre mudanças desses papéis. As políticas administrativas atuais permitem operações amplas e continuam uma prioridade antes de abrir o piloto.

Gatilhos de identidade restringem gravações executadas como authenticated. Fluxos SECURITY DEFINER e serviço não são bloqueados indiscriminadamente para não quebrar ativação; precisam de revisão própria de autorização, e-mail confirmado/atual, organização suspensa e reativação de contas. A revisão de convites da Central não equivale à revisão completa de convites de ministério.

Também permanecem pendentes auditoria completa das mudanças de acesso, retenção de histórico de concessões revogadas, APIs/telas administrativas de sucessão com retorno confirmado, testes concorrentes e testes visuais com perfis restritos. A versão global TypeScript continua com pendências anteriores; este bloco não a aprova nem libera a Vinha para clientes.

## Publicação e contingência

Aguardar checks do commit final e compilação Vercel antes da integração. Conferir deployment Production do merge SHA e respostas públicas sem simular gravações reais. Registrar a evidência final no PR, preservando os arquivos locais de evidências/templates que já pertenciam ao usuário.

Em incompatibilidade de integração antiga que transfere identidades por UPDATE, reproduzir isoladamente e adaptar para o fluxo explícito autorizado. Não restaurar TRUNCATE/TRIGGER/REFERENCES/MAINTAIN nem remover RLS ou os gatilhos globalmente. Esta migração não exige restauração de dados, pois não os reescreve.

As orientações Supabase/privilégio mínimo motivaram a revisão de grants além das políticas RLS e os testes também de criação futura de tabela: [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [changelog](https://supabase.com/changelog).
