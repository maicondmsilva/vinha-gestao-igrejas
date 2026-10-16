# L1 — bloco 2: continuação, isolamento por unidade e publicação

Data local: 16/10/2026. Base: 398f15838570cbffccdcc794707194569c1e5b0f.

## Escopo e situação

Conexão Supabase Vinha Igrejas selecionada explicitamente, sem usar FERTICALC.
Projeto Vinha Produção: aoxibaaydfgffrdqtkva. As 27 migrações anteriores foram conferidas.

Aplicadas e confirmadas no banco principal:

- 20261016032036_unit_scope_integrity
- 20261016032241_revoke_anonymous_tenancy_grants

Código da aplicação preparado para publicação GitHub/Vercel. O estado efetivo de publicação deve ser confirmado pelos registros do PR/deploy, não por esta preparação.

Não libera o piloto nem conclui toda a L1. Não houve uso de dados de clientes em testes de escrita, remoção de contas, envio de e-mail/WhatsApp, chamada a provedor financeiro ou emissão fiscal real.

## Alterações do banco

- membership_unit_access recebe organization_id preenchido a partir do vínculo existente e chaves compostas para garantir que participação e unidade sejam do mesmo ministério. Trigger mantém compatibilidade de inserções antigas sem informar organização.
- Contexto de acesso e seleção de unidade validam concessões efetivas; preferência/default não concede acesso.
- Proprietário, pastor e administrador mantêm acesso organizacional. Secretaria e líder passam a depender de concessão por unidade; read não concede escrita. include_children controla herança.
- Pessoas e unidades de organização suspensa não são retornadas por estes controles. Identidade ligada à pessoa sem participação ativa não recupera acesso administrativo ou consentimentos.
- Recursão de ancestrais usa UNION com deduplicação em vez de UNION ALL, evitando repetição infinita em ciclo.
- Trigger de hierarquia rejeita autoparentesco e ciclos, mantém organização da unidade imutável e serializa edições da árvore por ministério com advisory lock. Concorrência entre sessões e níveis de isolamento alternativos ainda precisam de testes específicos; não considerar a suíte sequencial prova de ausência de toda corrida.
- Visitantes anônimos perdem privilégios diretos em organizations, organization_units, organization_memberships, membership_unit_access e user_access_preferences. Convites e chat público continuam passando pelas funções específicas, cobertas nos testes.
- Alterações de política, chaves e privilégios executadas em migrações com limites de espera/execução na alteração estrutural principal.

Pré-verificação remota: zero concessões entre organizações, zero ciclos detectados e nenhum vínculo ativo restrito que perderia acesso nesta alteração (somente owner ativo).
Pós-verificação remota: RLS habilitada, três restrições validadas, dois triggers ativos, zero concessões inconsistentes, access_context inacessível a anon e privilégios anônimos de leitura removidos nas cinco tabelas.

## Aplicação

Inclui as correções locais do registro anterior: sem retorno a D1 em people/units; unidade inválida não cai na padrão; edição verifica linhas efetivamente retornadas antes de auditoria/endereço; consultas complementares filtram organização; notas pastorais limitadas.

A seleção de acesso deixa de usar o caminho antigo /api/access/context e descarta preferências/defaults de unidade não autorizados. A listagem de unidades da igreja também cruza os identificadores do contexto, inclusive quando o usuário tem poderes separados como operador da Central.

## Testes reproduzíveis

Dois bancos locais separados, sem reset do ambiente original:

- vinha-rls-b348af76: desenvolvimento da proposta e cenários RLS;
- vinha-rls-replay-20261015: aplicação da migração sobre concessões sintéticas preexistentes.

As quatro suítes antigas que exigiam contas reais/existentes agora criam identidades sintéticas confirmadas, operador e ministério de teste dentro da transação e revertem tudo ao final. Identificadores das fixtures impedem selecionar contas de clientes. Acrescentado invólucro pgTAP para execução padronizada.

Corrigido pressuposto de teste de convite: dois convites pendentes para o mesmo e-mail são válidos; a consulta pode retornar qualquer um deles quando os timestamps coincidem. O teste não exige arbitrariamente o convite da sede.

Validação final:

- 38 testes de aplicação aprovados (20 segurança/integridade, 4 contenção, 14 faturamento);
- seis arquivos SQL, 47 verificações pgTAP aprovadas;
- build Vercel aprovado antes do pequeno ajuste de tipagem/escape da URL de convite; o CI e a publicação devem recompilar a versão final;
- adicionada execução de banco local ao CI, com CLI oficial 2.120.0 e ação fixada por SHA;
- checagem global TypeScript ainda não aprovada: havia 316 diagnósticos antes do ajuste de três erros de tipagem da tela de acesso. Recontar no fechamento; não anunciar aprovação global.

## Alertas remotos ainda em revisão

Os advisors retornam alertas que não foram ocultados nem considerados automaticamente resolvidos:

- Duas tabelas de eventos com RLS e nenhuma política (negação por padrão, acesso de serviço precisa continuar controlado). [Referência](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
- Duas funções SECURITY DEFINER acessíveis a visitantes, usadas por convite/chat, e dez acessíveis a autenticados. Sua exposição exige revisão de cada corpo/autorização; revogar todas cegamente quebraria jornadas legítimas. [Visitantes](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [autenticados](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
- Proteção contra senhas comprometidas desativada; verificar disponibilidade no plano e ativação de Auth separadamente. [Referência](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Não é uma declaração de segurança integral.

## Próximos critérios antes do piloto

1. Tornar gravação de membro/endereço/contatos/consentimentos atômica e evitar apagar campos omitidos em PATCH.
2. Ampliar testes de concorrência de hierarquia e alterações de permissões durante a operação.
3. Revisar todas as funções privilegiadas, campos sensíveis, preferências gravadas diretamente, sessões/MFA, endpoints públicos e limitação de requisições.
4. Validar interface autenticada, inclusive responsável com múltiplas igrejas, secretaria, líder e acesso revogado; não foi realizada nesta entrega.
5. Homologar confirmação/recuperação de e-mail com remetente e conta real autorizada, sem alegar entrega antes de verificá-la.
6. Reduzir erros TypeScript e revisar alertas de dependências.
7. Manter módulos ainda não liberados contidos e faturamento externo em sandbox.
