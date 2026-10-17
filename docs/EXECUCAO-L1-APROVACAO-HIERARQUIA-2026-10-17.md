# L1 — bloco 13: estado atual na aprovação de hierarquia

Base publicada: 1fff477e93c161f7f0fecea2e2721484427d6e18. Autorização específica recebida em 17/10/2026. Migração 20261017100325_hierarchy_approval_state_guard aplicada em produção pela conexão Supabase Vinha Igrejas, projeto aoxibaaydfgffrdqtkva. Código em publicação na PR 31; resultado da implantação registrado na PR. Não encerra L1 nem libera piloto.

## Achado confirmado e correção delimitada

A inspeção de leitura do corpo remoto de approve_organization_hierarchy confirmou que o fluxo privilegiado não confere os estados dos dois ministérios antes de registrar aceite, rejeição ou vínculo/pagador. Também usa NOT IN sem rejeitar NULL explicitamente; em PL/pgSQL uma condição NULL não aciona o IF e uma decisão ausente pode seguir o ramo de aceite.

A revisão exige decisão explícita approve/reject e identificadores presentes; em solicitações pendentes, trava as duas organizações em ordem de ID e exige ambas active/trial. Depois trava e revalida a participação atual de quem responde. Preserva a matriz existente owner/admin/pastor, as respostas, a serialização de hierarquia, a aprovação pelos dois lados, a idempotência de estados terminais e os bloqueios anteriores de ciclos/filha já vinculada. Pagamento individual ou centralizado mantém o comportamento anterior, somente após o aceite duplo.

Nenhum backfill, exclusão ou alteração automática de solicitação, vínculo ou cobrança existente. Rejeitar uma solicitação pendente com uma das organizações suspensa/cancelada também será recusado até revisão administrativa ou regularização. Não muda o preço, plano ou contrato e não executa pagamento externo.

## Testes e limites

Suíte completa aprovada no [CI 39003458170](https://github.com/maicondmsilva/vinha-gestao-igrejas/actions/runs/39003458170), SHA 23fd1d15976077d7338eb9511a4325a28e72359d: 852 verificações SQL em 17 arquivos (35 novas), 78 testes da aplicação (60 de segurança, 14 da Central, 4 de publicação), seis cenários concorrentes anteriores de governança e build. Banco temporário com contas sintéticas e rollback, sem escrita em produção. Cobertos autorização, NULL, decisão inválida, suspensão de sede/cancelamento da filha, efeitos parciais, idempotência, ciclos, papéis e pagador. Docker local inacessível por permissão do canal, não interpretado como prova de engine desligado. A alteração posterior é somente este registro documental; conferir seus checks antes de publicar.

O diagnóstico de leitura do banco principal, reconferido após aplicação, mantém as categorias anteriores: [RLS sem política](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), funções definer executáveis por [anon](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable) e [authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), e [proteção de senhas vazadas desativada](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Não foram silenciadas nem declaradas resolvidas.

Escopo limitado ao RPC de resposta. A criação/edição direta das solicitações pela Central, retenção/consulta, identidade de autores de aceites antigos e revalidação desses autores no segundo aceite ainda exigem revisão própria. O modelo atual guarda horários, não os dois autores: esta revisão não afirma resolver revogação do primeiro aprovador entre os aceites. Não houve teste específico de concorrência de hierarquia nem nova validação visual autenticada. Testes anteriores de governança não provam todos os interleavings desse fluxo. Não afirmar segurança integral ou conclusão da migração de toda a plataforma.

As orientações de Supabase levaram a manter a autorização explícita no RPC privilegiado existente, search_path vazio e grants restritos, sem conceder acesso geral às tabelas nem usar metadados editáveis do usuário. A consulta ao changelog markdown não foi suportada pelo navegador; usado o índice HTML oficial e a documentação atual de RLS. Referências: [changelog](https://supabase.com/changelog), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [privilégios](https://supabase.com/blog/postgres-roles-and-privileges).

## Aplicação e recuperação

Aplicada após CI aprovado e autorização específica, somente no banco principal Vinha Igrejas. O [CI final anterior à aplicação 39003725194](https://github.com/maicondmsilva/vinha-gestao-igrejas/actions/runs/39003725194), no SHA ca9c64f2ae853a51e37e62084ea6f81890665f37, confirmou novamente as 852 verificações SQL, 78 testes da aplicação, seis cenários concorrentes anteriores e build. SQL aplicado idêntico ao aprovado; arquivo renomeado somente para conciliar a versão efetivamente registrada no Supabase.

Pós-verificação de leitura confirmou decisão explícita, verificação de estado, lock do respondente, proteção contra ciclo/vínculo duplicado, search_path vazio, EXECUTE negado a anon e permitido a authenticated, e RLS ativa nas quatro tabelas envolvidas. Nenhuma solicitação real criada para testar; nenhum vínculo ou pagador existente foi reclassificado, apagado ou alterado.

Se houver regressão, reproduzir em ambiente isolado e corrigir seletivamente; não restaurar decisão implícita nem contornar a verificação de estado. E-mail real, backup/restauração, sessões e os demais itens do plano continuam pendentes. O SHA final e a implantação ficam registrados na PR 31.
