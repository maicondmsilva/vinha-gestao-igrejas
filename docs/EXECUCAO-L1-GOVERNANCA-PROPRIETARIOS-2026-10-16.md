# L1 — bloco 8: concessão de papéis e último proprietário

Base: e61ec4d1c7733e38ee31608413f1ad2e63142860. Data: 16/10/2026.
Conexão exclusiva: Supabase Vinha Igrejas, projeto aoxibaaydfgffrdqtkva.

## Entrega e autorização

Após autorização específica do responsável, aplicada a migração `20261016212749_membership_governance.sql` no Supabase principal. Nenhuma conta existente foi reclassificada, suspensa ou excluída. Não há backfill de histórico. Publicação do código/histórico de migração deve ser comprovada pelo PR e deployment de produção correspondentes.

A análise remota confirmou uma participação ativa de proprietário e nenhum ministério com participações sem proprietário ativo. A regra anterior de escrita aceitava owner/pastor/admin sem limitar o papel concedido, permitindo elevar poderes pela alteração/inserção de uma participação. A matriz abaixo é uma nova restrição aprovada, não uma descrição da regra antiga.

## Matriz implantada nas escritas de cliente

| Gestor atual | Pode conceder/alterar | Não pode |
|---|---|---|
| Proprietário | Todos os papéis do próprio ministério | Remover/rebaixar/suspender/revogar o último proprietário ativo |
| Administrador | Pastor, secretaria, financeiro, líder, membro e leitor | Criar/alterar/remover proprietário ou outro administrador; elevar o próprio papel |
| Pastor | Secretaria, financeiro, líder, membro e leitor | Criar/alterar/remover proprietário, administrador ou outro pastor; elevar o próprio papel |
| Demais papéis | Sem gestão de participações por este fluxo | Promover a própria conta ou terceiros |

Administrador/pastor mantêm a possibilidade de mudar sua unidade padrão sem mudar seu papel/status. As outras regras de identidade e integridade por ministério continuam valendo. A primeira participação de proprietário no cadastro inicial continua restrita ao criador legítimo do ministério não reivindicado, conforme o fluxo anterior.

## Proteção e concorrência

- Gatilho invoker aplica a governança a INSERT/UPDATE/DELETE executados como authenticated em organization_memberships, incluindo Data API e fluxos invoker.
- Verificador privado, não exposto como RPC público, valida identidade e papel por dados do banco, recusa ministério suspenso/cancelado e serializa a governança pelo registro da organização.
- Também bloqueia as linhas do ator e dos proprietários ativos antes da decisão. Isso permite revalidar autorização depois da espera em READ COMMITTED e obter falha de serialização quando uma linha relevante mudou em snapshots antigos de REPEATABLE READ/SERIALIZABLE.
- Exclusão, suspensão, revogação ou rebaixamento do último proprietário ativo é recusado. Para uma sucessão legítima: nomear outro proprietário ativo primeiro; só depois alterar a participação anterior.
- Operações simultâneas podem receber 42501 (acesso recusado), 40001 (serialização) ou 40P01 (deadlock). Não repetir automaticamente uma concessão: recarregar o estado, confirmar autorização e refazer a transação completa se ainda legítima. As interfaces futuras precisam apresentar essa orientação; não há nova tela de sucessão nesta entrega.
- A exclusão física de ministério via cliente também pode ser impedida pela proteção em cascata. Cancelamento comercial e procedimentos internos de retenção/purga são fluxos separados; não remover o último dono por SQL de cliente para contornar a regra.

## Histórico protegido

Nova tabela organization_membership_events registra inserção/alteração/exclusão de participação, ator obtido de auth.uid(), conta afetada, estado anterior/posterior (papel, status, unidade padrão), contexto de execução e horário do banco. Não copia nome, CPF ou e-mail.

O gatilho de auditoria é definer interno e não executável diretamente pelo cliente. Cliente não insere, altera, exclui ou esvazia eventos; proprietário/administrador do mesmo ministério ativo podem lê-los pela RLS. Pastor, outra organização e visitantes não ganham leitura irrestrita. Service role recebe somente SELECT na nova tabela; o gatilho/owner do banco faz a inserção. Falha na auditoria reverte a mudança de acesso na mesma transação.

Identificadores de participação não são FK em cascata, preservando seu histórico após remover a participação. Exclusão física administrativa de toda a organização apaga seus eventos por cascata; o gatilho reconhece essa purga interna para não tentar recriar evento órfão. Portanto, não se trata de arquivo externo imutável/WORM ou política completa de retenção. Interface e exportação desse histórico ainda não foram construídas.

## Verificação

- 708 verificações pgTAP em doze arquivos: 663 anteriores, 8 adicionais do teste estrutural pela nova tabela e 37 específicas de governança. Incluem recusa do último proprietário, sucessão válida, matriz por INSERT/UPDATE, isolamento entre ministérios, imutabilidade do histórico, bootstrap, suspensão e rollback quando a auditoria falha.
- Seis testes com duas conexões reais ao Postgres isolado: saídas concorrentes de proprietários e revogação de gestor versus concessão, nos níveis READ COMMITTED, REPEATABLE READ e SERIALIZABLE. O script confirma que as sessões se sobrepõem antes do primeiro commit. Em cada disputa, mantém proprietário ativo e rejeita escrita sem autorização atual. São cenários determinísticos, não prova de todos os interleavings/cargas.
- Testes concorrentes adicionados ao CI depois do pgTAP, nunca ao banco remoto. Não aceitam URL de banco/token; usam somente container local próprio ou o container efêmero do GitHub Actions. Fixtures recebem UUIDs aleatórios e são removidas em finally por id e marcador exatos. Não há uso de contas reais, envio de mensagens ou pagamentos.
- 54 testes anteriores de aplicação aprovados: 36 segurança/integridade, 4 contenção, 14 financeiro. Advisor local de segurança no nível warn sem avisos. Nenhuma aprovação global de TypeScript é alegada.
- Migração gerada por diff local, inicialmente 20261016212552; versão conciliada com o histórico principal 20261016212749. Revisados ordem de dependências, compilação, lock_timeout/statement_timeout e grants. Removida normalização desnecessária de poderes do owner; service role foi limitado a leitura do histórico.
- Pós-verificação principal somente de leitura confirmou os dois gatilhos habilitados, regra de último dono presente, trigger de proteção invoker, chamada direta negada, RLS do histórico ativa, escrita/reescrita/exclusão de eventos negadas a authenticated, leitura anônima negada e zero privilégios estruturais de cliente nas tabelas públicas. Não foram testadas alterações de contas reais.
- Permanecem avisos anteriores do advisor principal: [funções privilegiadas públicas para visitantes](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [funções privilegiadas para autenticados](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [eventos internos com RLS sem política](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) e [proteção contra senhas comprometidas desativada](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

## Limites e continuidade

Esta matriz não é aplicada indiscriminadamente a SECURITY DEFINER/serviço: ativação por convite da Central já é um fluxo privilegiado que concede proprietário, e precisa de autorização própria. Suas alterações são auditadas, mas o gatilho invoker não substitui a revisão dessas funções. Próxima prioridade: aceite/retomada de convite de ministério com e-mail atual/confirmado, estado da organização, revogação e reativação de participação, além de testar a matriz visualmente com perfis restritos. Não anunciar que todos os caminhos privilegiados já estão protegidos.

Também falta revisar quem pode alterar campos administrativos/comerciais da organização diretamente, integrar o histórico e a sucessão às telas/APIs, retenção/exportação, carga/stress e governança dos acessos de serviço. Não houve revisão retroativa de todas as participações existentes. Este bloco não encerra L1 nem autoriza piloto ou abertura comercial.

## Implantação e contingência

Conferir checks do SHA final antes de integrar e confirmar deployment Production do merge correspondente. Registrar os resultados e os HTTP smokes no PR. Os arquivos anteriores de evidências/templates do usuário devem permanecer fora do commit.

Em regressão, reproduzir a operação com papel anterior/novo, ator e isolamento em ambiente isolado. Corrigir seletivamente sem restaurar a promoção irrestrita nem permitir remover o último proprietário. Não tratar mensagem de serialização/deadlock como sucesso. Se o ministério não tiver proprietário ativo por operação interna, usar procedimento administrativo auditado de recuperação, não permitir autorreivindicação por qualquer usuário. Não é necessário restaurar dados por esta migração, que não os reclassifica nem apaga.

As orientações Supabase/privilégio mínimo e a [documentação de isolamento do Postgres](https://www.postgresql.org/docs/current/transaction-iso.html) orientaram os locks e a verificação com snapshots antigos; o [changelog Supabase](https://supabase.com/changelog) e as [regras RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) foram consultados antes da implementação.
