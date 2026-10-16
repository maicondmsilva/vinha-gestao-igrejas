# L1 — bloco 5: funções privilegiadas, convites e operadores

Base: 9cb27618df35e9805c8b001d4193fc7379ea5aa2. Data: 16/10/2026.
Conexão: somente Supabase Vinha Igrejas, projeto aoxibaaydfgffrdqtkva. Não usar FERTICALC.

## Entrega delimitada

Inventariadas as funções SECURITY DEFINER de public/private e comparados os corpos remotos de aceite de operador/proteção de operador com o código versionado. Todas as funções inventariadas têm search_path vazio. Isso não prova que todas sejam seguras.

Corrigida inconsistência observada na política de convites: INSERT recusava proprietário para administrador, mas UPDATE permitia mudar um convite existente para owner. O aceite privilegiado confiava no papel armazenado. A migração fecha essa cadeia sem ampliar acessos.

- Convite novo começa pendente, com prazo máximo de sete dias; cliente não marca aceite por conta própria.
- Após criado, e-mail, papel, token, emissor, identificador e datas originais não são reescritos por authenticated. Para mudar a concessão, cancelar e criar outro convite. Revogação recebe horário do banco e não é desfeita pelo cliente.
- Somente proprietário atua em convite de proprietário; administrador só atua nos demais, com MFA. Convites aceitos/revogados não são alterados pela tela administrativa.
- Aceite exige e-mail confirmado e atual em auth.users, não apenas a informação antiga do JWT. Verifica expiração, revogação e permissão atual do emissor. Emissor suspenso ou rebaixado não continua concedendo poderes que perdeu.
- Aceite trava o convite e serializa por conta. Repetição de convite já aceito retoma somente a conta correspondente ainda ativa; não reativa operador suspenso e não promove um operador existente por outro convite.
- Identidade, e-mail e data original do operador são imutáveis neste fluxo. Permanecem a proteção contra autosuspensão e contra remover o último proprietário ativo. Lock adicional serializa a decisão do último proprietário em isolamento padrão; concorrência real entre duas conexões e outros níveis de isolamento ainda não foram homologados.
- Papel do convite não dispensa o segundo fator para usar a Central. O aceite ocorre antes da configuração de MFA para não impedir o ingresso; funções/políticas administrativas continuam exigindo aal2.
- Revogados poderes estruturais e acesso anônimo direto nas três tabelas de operadores, convites e eventos; auditoria continua somente leitura para o cliente autorizado.
- A tela confirma uma linha retornada antes de informar alteração/cancelamento. Falha ou zero linhas não vira sucesso. Busy é liberado em finally. Convite expirado ainda pendente pode ser cancelado para emitir outro, respeitando o índice de unicidade existente.

## Inventário das dez entradas públicas privilegiadas

| Entrada | Autorização observada / evidência local | Limites restantes |
|---|---|---|
| organization_invite_preview | Token UUID; teste de token inexistente; resposta pública limitada | Revisar retenção de dados em convite revogado e proteção contra abuso |
| accept_organization_invite | Token, e-mail, estado e lock; suíte transacional de ativação e teste negativo | Revisar e-mail atual/confirmado e estado do ministério neste outro fluxo |
| pending_organization_invitation | auth.uid e e-mail; teste sem convite correspondente | Revisar confirmação/mudança de e-mail |
| approve_organization_hierarchy | Papel de gestor e organização participante; cenários positivos anteriores e teste de estranho | Estado suspenso e concorrência entre aprovações |
| organization_hierarchy_requests | Papel de gestor; teste de não participante | Revisão do conjunto de campos retornados e ministério suspenso |
| chat_operator_directory | Operador ativo e MFA; teste de não operador sem retorno | Testes visuais da matriz completa |
| support_chat | Segredo de visitante ou dono autenticado; testes anteriores de segredo errado e outro usuário | Limitação de abuso, retenção e carga |
| transfer_platform_chat | Setor, papel e MFA; teste anterior de setor não autorizado e teste negativo | Corridas entre transferência, envio e revogação |
| request_unit_modules | Papel owner/admin da organização; teste negativo | Estado ativo, escopo e auditoria da solicitação |
| unit_module_enabled | Participação ativa e contrato; teste sem vínculo | Garantia do contrato da unidade-alvo, não somente preferência/default |

Estas entradas públicas não foram convertidas indiscriminadamente para INVOKER: algumas chamam implementações privadas sem grants de cliente e outras precisam executar uma operação inicial estritamente validada. Revogar todas quebraria convites/chat. Permanecem no inventário de revisão; os avisos do advisor não são um selo de aprovação nem devem ser ocultados.

## Testes e verificação

- 168 verificações pgTAP em nove arquivos: 42 novas nesta entrega, com identidades sintéticas e rollback local. Não foram criados operadores/convites de teste no banco principal.
- 54 testes de aplicação: 36 segurança/integridade, 4 contenção e 14 financeiro. Incluem os handlers reais da tela com banco simulado, zero linhas, falha de rede e sucesso confirmado.
- Build Vercel local aprovado antes do pequeno ajuste final de botão de convite expirado; CI deve recompilar o estado final.
- TypeScript global continua com 313 diagnósticos; não anunciar aprovação global.
- Advisor local sem avisos no nível warn. As permissões geradas pelo diff foram revisadas para excluir normalizações do bloco anterior e retirar grants anônimos herdados, sem conceder novos acessos.
- Após autorização específica do responsável, migração 20261016091915_operator_invite_security aplicada no Supabase principal em 16/10/2026. A primeira solicitação expirou sem registrar migração; a repetição ocorreu somente depois de conferir a ausência no histórico. A publicação de código é comprovada separadamente pelo PR/deploy.
- Pós-verificação remota: gatilho ativo, sem execução direta por authenticated, leitura anônima e TRUNCATE bloqueados nos convites, auditoria sem INSERT de cliente, validação de e-mail confirmado presente e política de proprietário atualizada. Não foram feitas chamadas de aceite com contas reais para simular testes.
- Advisors remotos mantêm avisos anteriores: [funções privilegiadas públicas para visitantes](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [funções privilegiadas para autenticados](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [tabelas de eventos com RLS sem política, negadas por padrão](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) e [proteção contra senhas comprometidas desativada](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Não declarar segurança integral nem remover regras apenas para silenciar avisos.

## Contingência e continuidade

Nenhum backfill ou remoção de registros existentes é necessário. Se um convite antigo legítimo deixar de funcionar por emissor sem poderes, emitir novo convite por proprietário autorizado; não reativar emissor nem alterar papel/token em SQL para contornar a regra. Em regressão técnica, reproduzir isoladamente e corrigir somente a validação incompatível, com os casos permitido/negado no teste. Não restaurar globalmente a política vulnerável nem remover MFA/RLS. Base anterior está versionada; não há dados a restaurar por esta migração.

Este bloco não encerra L1 nem libera piloto. Falta aprofundar governança de proprietários/participações por ministério, estado suspenso nas outras funções, contratos por unidade-alvo, revogação concorrente e validação visual com perfis restritos em homologação. Proteger senhas comprometidas, confirmar remetente real, reduzir erros TypeScript, testar backup/restauração e manter os demais módulos contidos continuam nos critérios do plano.
