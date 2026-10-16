# L1 — bloco 6: contrato da unidade real nas gravações

Base: df52ace1230975daecf81051ff72193acbdeb9d7. Data: 16/10/2026.
Conexão exclusiva: Supabase Vinha Igrejas, projeto aoxibaaydfgffrdqtkva.

## Situação

Implementado e validado no banco isolado. Após autorização específica do responsável, aplicado ao Supabase principal em 16/10/2026, versão 20261016094706. A publicação e a aplicação da migração são etapas separadas: acompanhar a conclusão pelo PR 24 e pelo deployment correspondente. Este bloco não libera clientes nem encerra L1.

## Problema confirmado

A consulta antiga `unit_module_enabled` verificava contrato da preferência/unidade padrão. Assim, selecionar sede liberada podia satisfazer a verificação inicial de uma gravação destinada a outra unidade bloqueada. A função também não validava o estado da organização/unidade selecionada nem sua concessão atual. `request_unit_modules` conferia papel da organização, mas não seu estado e o da unidade.

Consulta remota somente de leitura confirmou as definições e dois contratos ativos. Contagens de compatibilidade: zero pessoas sem unidade, zero contratos com decisão de módulo de tipo diferente de booleano e zero contratos em unidade inativa. Nenhum cadastro real foi alterado durante a investigação.

## Alterações delimitadas

- Nova consulta privada recebe organização, unidade real e módulo. Exige identidade, organização ativa/em teste, unidade ativa da mesma organização e acesso atual à unidade, pela regra existente `can_access_unit`. Módulo desconhecido é recusado.
- Contrato suspenso bloqueia; decisão explícita booleana prevalece sobre o plano; sem decisão, consulta inclusão no plano. Decisão malformada não vira autorização nem erro de conversão.
- Mantida deliberadamente a compatibilidade antiga: sem contrato ou com contrato em rascunho, o módulo conhecido continua liberado para usuário autorizado da unidade. Isso NÃO é implantação completa de cobrança/licenciamento; qualquer mudança desse padrão exige decisão comercial e análise dos clientes.
- A consulta da unidade selecionada passa pela mesma verificação. Preferência/default revogado ou suspenso não recai silenciosamente em outra unidade mais permissiva.
- Gatilho de INSERT/UPDATE em `people` valida contrato da unidade de destino, e também da origem na edição, para o papel `authenticated`. Abrange o RPC atômico existente e escrita direta pela Data API. Fluxos internos de serviço continuam fora deste gatilho de cliente e exigem controle próprio.
- `can_manage_person` passa a exigir contrato da unidade real e acesso de gestão. Isso também restringe as escritas complementares que já dependem dessa função: endereço, contato, registro administrativo de preferências e nota pastoral. Papéis de autorização existentes não foram ampliados.
- Pedido de alteração de módulos/vencimento continua pendente: não concede módulo. Agora exige unidade/organização ativas e autorizadas, além de proprietário/administrador.
- Nenhuma exclusão, backfill, alteração de preço, emissão, pagamento, disparo ou mudança de credencial.

## Limites intencionais

- A leitura histórica já autorizada por `can_view_person` permanece. Este bloco bloqueia gravações; não estabelece uma nova política comercial de ocultar dados históricos por módulo contratado. Preferências próprias do membro também não são convertidas em aceite contratual nem bloqueadas indiscriminadamente.
- API/RPC conservam a verificação inicial da unidade selecionada. Seleção bloqueada pode negar a operação mesmo que o destino seja liberado; é necessário selecionar uma unidade liberada. O destino precisa ser permitido também. Não houve ampliação de acesso para contornar essa negativa conservadora.
- Registros legados sem unidade não podem ser editados administrativamente por esta regra; contagem principal atual é zero. Se surgirem por importação interna, corrigir pelo fluxo administrativo autorizado, não desativar a regra globalmente.
- Não garante aplicação do contrato da unidade real a todos os outros módulos; vários seguem contidos. Governança de participações/proprietários, demais funções de convite/hierarquia, revogação concorrente e testes visuais com perfis restritos continuam pendentes.
- Desativar um módulo no catálogo comercial não revoga automaticamente contratos vigentes: a decisão comercial não foi alterada neste bloco.

## Verificação

- 199 verificações pgTAP em dez arquivos: 31 novas, com dados sintéticos e rollback. Exercitam sede permitida/filha bloqueada, RPC, escrita direta, transferência recusada, complemento bloqueado, plano, decisão explícita/malformada, contrato suspenso, rascunho/ausente, módulo inexistente, unidade estrangeira/sem concessão e suspensão.
- Dois testes anteriores passaram a esperar a negativa antecipada `42501: target_unit_module_not_enabled`, em vez da negativa posterior por RLS/FK; as operações continuam proibidas.
- 54 testes de aplicação aprovados: 36 segurança, 4 contenção e 14 financeiro.
- Advisor de segurança local no nível warn: sem avisos. Isso não elimina os avisos remotos anteriores nem constitui certificação de segurança integral.
- Migração gerada por comparação do banco isolado, inicialmente 20261016093851; arquivo conciliado com a versão registrada na produção: `20261016094706_unit_contract_write_scope.sql`. Revisada ordem de criação (dependência primeiro), compilação habilitada, limites de espera/execução e grants mínimos. Excluídas do diff as normalizações antigas de ACL de operadores, que não pertencem a este bloco.
- Histórico local conferido. Aplicação principal via migração transacional autorizada, sem alteração dos registros de clientes e sem testes sintéticos em produção. Pós-verificação confirmou gatilho habilitado, RLS preservada, helper negado a anônimos, gatilho sem execução direta pelo cliente e verificações de unidade-alvo presentes nas funções de módulo/gestão de pessoas e de escopo no pedido de contrato.
- CI e compilação Vercel aprovados para a revisão inicial 89a4200. Depois da conciliação do arquivo/histórico, aguardar novamente as verificações do novo commit antes da integração.
- Advisors principais mantêm avisos prévios: [funções públicas privilegiadas para visitantes](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [funções privilegiadas para autenticados](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [eventos internos com RLS sem política, negados por padrão](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) e [proteção contra senhas comprometidas desativada](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Não remover controles para silenciar avisos nem declarar segurança integral.

## Implantação e contingência

Aplicação autorizada concluída no projeto correto e definições/grants/gatilho/histórico conferidos. Nome do arquivo conciliado com a versão registrada. Aguardar a revisão automatizada do PR antes de integrar na branch de produção. Não testar cadastro fictício no banco principal. Evidência de publicação será o merge SHA e seu deployment de produção, consultáveis no PR 24.

Em regressão, identificar unidade, contrato e concessão efetivos; reproduzir isoladamente e corrigir apenas a regra incompatível, mantendo casos permitido/negado. Não remover RLS, reabrir contratos suspensos ou restaurar a validação baseada somente na preferência. Nenhum dado existente precisa ser restaurado, pois esta migração não o altera.

Orientações utilizadas: [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [changelog](https://supabase.com/changelog) e habilidades Supabase/privilégios mínimos. A revisão orientou testes no banco isolado e proteção também da Data API, em vez de depender apenas da interface.
