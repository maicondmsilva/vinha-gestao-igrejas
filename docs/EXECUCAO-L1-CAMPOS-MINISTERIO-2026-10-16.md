# L1 — bloco 10: campos administrativos do ministério

## Estado

Base publicada: 80ade0a2f7bec3d4aea516d6f5cfd23b272fea29. Autorização específica recebida em 16/10/2026. Aplicada a migração 20261016225141 no Supabase Vinha Igrejas, projeto aoxibaaydfgffrdqtkva, sem exclusão ou reclassificação de dados existentes. Publicação do registro em acompanhamento no PR 28. O bloco não encerra L1 nem libera o piloto comercial.

## Evidência e mudança delimitada

A inspeção somente de leitura confirmou que organizations_update_admin permite UPDATE por proprietário, administrador ou pastor sem limitar colunas. A função de papel verifica a participação ativa, não o estado comercial da organização. Por isso um gestor poderia mudar diretamente o status e contornar uma suspensão do ministério. Também faltava proteção de criador, identidade, endereço digital e data original neste caminho.

A proposta mantém a RLS e acrescenta um gatilho SECURITY INVOKER, sem elevar privilégios:

- Para UPDATE executado como authenticated, permite somente nome, razão social, documento, cor principal, cor secundária, nome do aplicativo e pastor titular. O horário de atualização vem do banco.
- Impede alterar diretamente id, slug, status, bootstrap_user_id, created_at, registration_code e futuras colunas não explicitamente autorizadas. A proteção já existente do código de identificação continua valendo.
- Recusa mudanças de configuração em ministérios suspensos ou cancelados, sem retirar leituras já autorizadas.
- Para INSERT de cliente, exige estado trial, criador igual à conta autenticada e data original do banco. O cadastro legítimo inicial continua criando a sede e o proprietário pelas regras anteriores.
- A Central continua usando suas funções privilegiadas já autorizadas; a sincronização interna de assinatura continua controlando o estado comercial. Não se concede nova permissão a operadores ou a clientes.

Não há alteração automática de registros existentes, exclusão de dados ou mudança de papéis. Gestores que usavam gravação direta de status/endereço/criador precisarão usar um procedimento administrativo legítimo; não reabrir esses campos para contornar a regra.

## Validação e limitações

757 asserções pgTAP aprovadas em 14 arquivos, incluindo 27 novas para papéis owner/admin/pastor/viewer, isolamento entre ministérios, campos permitidos e recusados, suspensão, horário do banco, bootstrap legítimo e sincronização interna de assinatura. A suíte existente cobre o cadastro de demonstração e as operações da Central. Build, 62 testes de aplicação e 6 cenários concorrentes anteriores de governança aprovados no CI 38977701617, commit afd1ac1c945951cd5fe18f75780293978ac32680; prévia Vercel aprovada. Os cenários concorrentes não comprovam todas as disputas de configuração/contrato.

Conferência somente de leitura em produção: gatilho habilitado, função invoker, validações administrativa/suspensão/bootstrap presentes, RLS mantida e execução direta negada a anon, authenticated e service_role. Sem testes de escrita em clientes reais. O nome do arquivo foi conciliado com a versão efetivamente registrada pelo Supabase, sem mudar o SQL aprovado.

Permanecem avisos anteriores do advisor: [RLS sem política](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [funções privilegiadas acessíveis a visitantes](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [funções privilegiadas acessíveis a autenticados](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) e [proteção contra senhas vazadas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Não foram reabertas permissões nem removidas APIs necessárias para silenciar esses avisos.

O Docker local continua inacessível por permissão do canal nesta sessão. Não haverá teste substituto com escrita em produção: usar o banco efêmero do GitHub Actions. Migração criada com a ferramenta oficial, não por comparação local; revisar seu SQL e permissões explicitamente.

Não foi adicionada uma interface de transferência de titularidade/endereço, trilha completa de mudanças de configuração ou prova de todos os cenários concorrentes. A proteção distingue execução direta como authenticated de execução interna como owner da função: ainda é necessário revisar separadamente as funções privilegiadas e credenciais de serviço. Confirmação de e-mail/sessão no cadastro inicial, campos das unidades, arquivos, proteção contra abuso e entrega de e-mail real não são resolvidos por este bloco.

As orientações de privilégio mínimo do Supabase levaram a preservar a RLS e usar um gatilho invoker, em vez de ampliar acesso ou converter a gravação em SECURITY DEFINER. Referências consultadas: [changelog](https://supabase.com/changelog), [gatilhos](https://supabase.com/docs/guides/database/postgres/triggers) e [controle de colunas](https://supabase.com/docs/guides/database/postgres/column-level-security).

## Aplicação e recuperação

Aplicação autorizada e realizada pela conexão Vinha Igrejas; gatilho, função invoker e acessos conferidos. Publicar o histórico aprovado e confirmar a implantação de produção pelo SHA correspondente. Em regressão, reproduzir isoladamente e corrigir a operação legítima afetada, sem permitir reativação comercial por atualização direta do cliente. Permanecem as demais pendências do plano de lançamento.
