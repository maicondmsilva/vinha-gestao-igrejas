# L1 — bloco 12: governança das unidades

Base publicada: eb90f5769ddc0e8b6f0fe5c25ae142397b1b6934. Autorização específica recebida em 17/10/2026. Migração 20261017041013_unit_client_governance aplicada na produção pela conexão Vinha Igrejas. Código em publicação na PR 30; o resultado da implantação será registrado na PR. Não encerra L1 nem libera o piloto.

## Evidência

A inspeção somente de leitura confirmou políticas INSERT/UPDATE/DELETE de unidades por papel de gestor sem conferir o estado do ministério na escrita. O gatilho anterior já impedia transferir organization_id e formar ciclos, e o código de identificação já era protegido, mas não havia proteção equivalente para id, slug, created_at ou classificação da sede. O tipo headquarters influencia consultas de contrato e provisionamento: não deve ser trocado como simples rótulo de cadastro.

A contagem agregada principal não encontrou ministérios com mais de uma sede nem sedes com unidade superior no momento da inspeção. Isso não prova ausência de outros problemas e não substitui os testes. Nenhum cadastro real foi alterado.

## Mudanças delimitadas

- Revoga DELETE de organization_units para PUBLIC, anon e authenticated. Fluxos internos de serviço permanecem separados; não é criada API de purga.
- Gatilho invoker mantém a RLS, exige ministério ativo/em demonstração e bloqueia sua linha durante a decisão. Impede trocar identidade, ministério, slug, data original e código por escrita comum, mantendo a mensagem anterior para transferência entre ministérios. Novas colunas são negadas por padrão até revisão.
- Impede converter unidade em sede ou sede em outro tipo, subordinar sede e criar segunda sede por escrita de cliente. A primeira sede do cadastro legítimo continua permitida.
- Preserva nome, dados legais, responsável, contato, endereço, autonomias operacionais, tipos não sede, hierarquia autorizada e estado operacional da unidade. Reativar uma unidade não reativa o contrato, cujas regras anteriores continuam independentes.
- Horário de atualização é atribuído pelo banco; INSERT de cliente não fabrica data antiga.
- A API traduz somente recusas conhecidas em mensagens compreensíveis e não registra sucesso/auditoria positiva quando o banco recusa a gravação. Quando uma edição omite o tipo, preserva o existente, sem tentar converter uma sede em campus.

Sem exclusão, migração ou reclassificação de registros existentes. A troca legítima de sede exigirá procedimento administrativo auditado separado, não atualização direta do tipo. Não foi implementada nova tela de arquivamento/restauração: o estado operacional existente é preservado, mas DELETE deixa de ser uma opção de cliente.

## Validação e limites

78 testes de aplicação aprovados: 60 de segurança, 14 da Central e 4 de preparação de publicação. CI 38996161652 no SHA d93e1e022ef433517c44284b31d08ec900cef820 aprovado: 817 verificações SQL em 16 arquivos, incluindo os 30 novos casos, seis cenários concorrentes anteriores e build. Os testes SQL usaram banco efêmero. O Docker local continua inacessível por permissão do canal. Migração criada com a ferramenta oficial e renomeada para a versão efetivamente registrada no Supabase, sem modificar o SQL aprovado.

Os testes concorrentes anteriores de governança não provam todos os interleavings de hierarquia/classificação/contrato. O lock da organização não é apresentado como solução integral de concorrência, sucessão ou governança de credenciais de serviço. Não houve nova validação visual de telas autenticadas nem aprovação global de TypeScript. E-mail real, sessões, importação, armazenamento e os demais itens do plano continuam abertos.

Na primeira execução SQL, os 30 novos casos passaram, mas a regressão de ciclo existente recebeu a nova recusa de sede (42501) antes do erro de hierarquia esperado (23514). Ajustada a ordem dos gatilhos para preservar o verificador anterior antes da nova proteção, sem enfraquecer nenhuma regra. A suíte completa passou no SHA final antes da autorização e aplicação; a execução inicial não foi usada como aprovação.

As orientações de Supabase levaram a preservar RLS, usar gatilho invoker e retirar o privilégio de exclusão física, sem elevar o acesso de cliente. Referências: [changelog](https://supabase.com/changelog), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) e [privilégios](https://supabase.com/blog/postgres-roles-and-privileges).

## Aplicação e recuperação

Aplicado somente no projeto aoxibaaydfgffrdqtkva pela conexão Vinha Igrejas, após testes e autorização específica. Conferência de leitura confirmou função invoker, EXECUTE negado a anon/authenticated/service_role, DELETE negado a anon/authenticated, RLS ativa nas duas tabelas e gatilhos de hierarquia/proteção habilitados na ordem prevista. Nenhuma escrita fictícia em produção.

O diagnóstico permanece com as categorias anteriores: [RLS sem política](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), funções definer executáveis por [anon](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable) e [authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), e [proteção de senhas vazadas desativada](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Essas pendências não foram removidas nem declaradas resolvidas neste bloco.

Em regressão, reproduzir isoladamente e corrigir seletivamente sem restaurar exclusão física irrestrita ou mudança de sede por cliente. O registro da publicação e seu SHA final ficam na PR 30.
