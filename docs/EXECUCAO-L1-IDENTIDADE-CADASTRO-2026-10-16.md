# L1 — bloco 11: identidade confirmada no cadastro inicial

Base publicada: 3922262c854a697d1a35c726d24d66f7c44b538c. Autorização específica recebida em 16/10/2026. Migração 20261016232219 aplicada pela conexão Supabase Vinha Igrejas, projeto aoxibaaydfgffrdqtkva, sem reclassificação/exclusão de contas ou envio de mensagens. Publicação do código em acompanhamento no PR 29. Não encerra L1 nem libera o piloto.

## Problema comprovado

Inspeção somente de leitura no Supabase Vinha Igrejas confirmou que register_organization_trial ainda obtinha o e-mail pelo JWT e bootstrap_organization não verificava confirmação. A API verificava email_confirmed_at, mas isso não protegia uma chamada direta ao banco. A nova proteção de campos do bloco 10 tampouco confirmava a conta ao aceitar INSERT direto.

## Mudanças

- Verificador privado consulta apenas a conta de auth.uid(), sem receber identificador de terceiro, exigindo e-mail atual confirmado, conta existente, não removida, não anônima e sem suspensão vigente na autenticação. Mantém lock de leitura na conta durante a transação.
- O acesso privilegiado existe somente para essa leitura interna de auth.users; não abre a tabela ao cliente nem cria endpoint público. Cadastro e bootstrap continuam SECURITY INVOKER, sujeitos à RLS.
- Bootstrap, cadastro/retomada de demonstração e INSERT direto de organização como authenticated exigem essa identidade. A demonstração e o contato inicial da sede recebem o e-mail atual do banco, não uma cópia antiga da sessão.
- INSERT direto de registro de demonstração não pode gravar e-mail de outra pessoa. As funções internas da Central e de provisionamento continuam com suas autorizações próprias.
- API recusa falha de autenticação mesmo se vier acompanhada de objeto de usuário; não prossegue com falha na consulta de convite; valida destinos e resultados antes de declarar sucesso; retorna respostas privadas e erros sem detalhes internos.

Sem reclassificação, exclusão ou envio automático de mensagens. Contas antigas não são suspensas: contas não confirmadas ou indisponíveis apenas deixam de criar/retomar ambientes por esses caminhos até resolver sua situação.

## Testes e limites

787 asserções SQL aprovadas em 15 arquivos, incluindo 30 novas de confirmação, mudança de e-mail, conta suspensa/removida/anônima/inexistente, acesso direto, idempotência e isolamento de identidade. 74 testes de aplicação aprovados, incluindo 12 novos da rota real com banco simulado. Build e 6 cenários concorrentes anteriores de governança aprovados no CI 38979186737, commit 0f4560623315693aa734195fb5651b5204fe394f; prévia Vercel aprovada. Esses cenários concorrentes não comprovam todas as disputas de identidade/cadastro.

SQL executado no banco efêmero do CI: Docker local está inacessível por permissão do canal. Migração criada com ferramenta oficial, não por diff local. Conferência em produção somente de leitura, sem gravações fictícias em clientes.

Pós-verificação principal: bootstrap e demonstração continuam invoker; verificação da identidade de auth.uid() e de e-mail confirmado presentes; demonstração não usa mais auth.jwt(); helper negado a anon, sem wrapper público e sem abrir SELECT de auth.users a authenticated; gatilho de identidade da demonstração habilitado; RLS das organizações e demonstrações mantida. Arquivo conciliado com a versão efetivamente registrada, sem alteração do SQL aprovado.

Permanecem avisos anteriores do advisor: [RLS sem política](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [funções privilegiadas acessíveis a visitantes](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [funções privilegiadas acessíveis a autenticados](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) e [proteção contra senhas vazadas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Não alterar permissões apenas para ocultar os avisos.

Isto não valida entrega de e-mail/SMTP com conta real, não altera a configuração de confirmação do Supabase, não substitui revogação de sessões e não adiciona verificação estrita de session_id em auth.sessions. Uma suspensão da autenticação não é o mesmo que a suspensão do contrato do ministério. Outros endpoints e todos os cenários concorrentes continuam exigindo revisão própria. O limite de tamanho da API é conferido após leitura do corpo; limitação de tráfego/abuso e leitura incremental ficam para revisão específica. Não há aprovação global de TypeScript nem nova inspeção visual de telas autenticadas.

## Aplicação e recuperação

Aplicação autorizada e realizada; funções, gatilhos, RLS e grants conferidos sem criar clientes fictícios. Publicar o código aprovado e confirmar a implantação correspondente. Em regressão, corrigir seletivamente sem remover a exigência de identidade confirmada nem confiar no e-mail do JWT.

As orientações Supabase levaram a manter as gravações como invoker e restringir o uso de definer à leitura da própria identidade. Referências: [changelog](https://supabase.com/changelog), [usuários anônimos](https://supabase.com/docs/guides/auth/auth-anonymous), [sessões](https://supabase.com/docs/guides/auth/sessions).
