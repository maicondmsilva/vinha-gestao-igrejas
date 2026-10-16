# L1 — bloco 4: permissões diretas e validação autenticada

Data: 16/10/2026. Base: 8e76b1af029af0052135d2fc20095457910dc0d6.

## Escopo

Somente conexão Supabase Vinha Igrejas, projeto aoxibaaydfgffrdqtkva. Migração aplicada e confirmada: 20261016073147_member_direct_access. Revisão de people, person_addresses, emergency_contacts, person_consents, pastoral_notes, user_access_preferences e audit_logs. Não é auditoria concluída das demais tabelas, funções privilegiadas, contratos por unidade, sessões ou endpoints públicos.

- Identificador, organização, vínculo Auth, papel do aplicativo e data original da pessoa não podem ser reescritos pelo papel authenticated. Inserção comum não pode vincular conta nem atribuir papel privilegiado. Fluxos futuros de vinculação precisam de verificação própria, não exceção no formulário.
- Leitura/escrita administrativa de pessoas exige papel adequado, participação e organização ativas e escopo de unidade. Financeiro, observador e membro não ganham acesso ao diretório por uma concessão genérica de unidade; permanece a leitura do próprio cadastro quando vinculado e autorizado.
- Consentimentos e notas deixam de permitir UPDATE/DELETE a authenticated. Exclusão física de pessoa também é negada para evitar apagar o histórico por cascata. Retenção, anonimização e exclusão legal precisam de fluxo privilegiado próprio, ainda não entregue.
- Preferências inseridas diretamente recebem ator/data/origem reais do banco e nunca aceite verificado inventado. Este caminho aceita apenas privacy/image/messages, sem fabricar termo, assinatura, IP ou representante. Preferência do próprio membro é self_reported_preference. Termos de menores/aplicativo continuam dependendo de implementação específica.
- Notas pastorais não podem ser lidas/inseridas com ministério suspenso. Papel pastoral e autor autenticado continuam obrigatórios.
- Preferências de navegação rejeitam organização/unidade não autorizada. Preferência revogada pode ser limpa sem recuperar autorização.
- Nas sete tabelas foram removidos poderes estruturais TRUNCATE, TRIGGER, REFERENCES e MAINTAIN para clientes. Auditoria mantém SELECT/INSERT, sem UPDATE/DELETE; preferências mantêm SELECT/INSERT/UPDATE.

## Testes e limites

126 verificações pgTAP em oito arquivos aprovadas em banco isolado. 47 testes de aplicação (29 segurança, 4 contenção, 14 financeiro) e build Vercel aprovados localmente. Advisors locais sem avisos no nível warn. CI repete migrações em instalação limpa. Não significa que os advisors remotos não tenham pendências anteriores nem que o TypeScript global tenha passado (baseline anterior: 313 diagnósticos).

Validação com a sessão fornecida pelo usuário: membresia abre, modal abre, dados pessoais/endereço avançam e unidades reais aparecem. A conta disponível é proprietária; papéis restritos e segundo navegador ainda não foram homologados visualmente.

Foi identificado envio antecipado ao clicar Continuar na etapa 3: React reaproveitava o botão como submit durante a mesma interação. A correção cancela o evento nativo antes de avançar, usa chaves distintas e exige etapa final para submit. Regressão do handler incluída; PR de correção separado. Antes da correção, o comportamento criou um cadastro sintético em produção. O usuário autorizou remover exclusivamente esse teste; um cadastro, um endereço e três preferências foram removidos e uma auditoria preservada. Nenhuma pessoa real foi excluída. Não repetir testes de escrita em produção; homologação de gravação deve ocorrer em ambiente separado.

## Publicação e reversão

A revisão automática inicialmente recusou a migração de permissões. Após explicação do risco, o usuário autorizou explicitamente a aplicação em produção. A migração não remove dados existentes, não altera credenciais e não libera novos acessos. Confirmar a aplicação e o número final pelo histórico do banco; PR/deploy comprovam separadamente a versão da aplicação.

Pós-verificação remota confirmou bloqueio de exclusão física, UPDATE de consentimentos, DELETE de notas e execução direta dos gatilhos internos; guard de identidade é SECURITY INVOKER. Os advisors remotos mantêm avisos anteriores: [duas tabelas de eventos sem políticas, negadas por padrão](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [duas funções privilegiadas de convite/chat expostas a visitantes](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [dez funções privilegiadas expostas a autenticados](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) e [proteção contra senhas comprometidas desativada](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Não foram ocultados nem declarados resolvidos.

Plano de contingência: se um fluxo legítimo falhar, suspender apenas a ação afetada, capturar código de erro sem dados pessoais e reproduzir em banco isolado. Fazer correção seletiva da política/gatilho incompatível, com teste que demonstre o caso autorizado e o negado, e aplicar migração aditiva revisada. Definições anteriores estão versionadas nas migrações de membresia e isolamento; não executar reversão global de grants, não remover RLS e não reabrir a exclusão em cascata como atalho. Não há backfill ou transformação de dados a desfazer. Privileged service/DB owners não estão impedidos de modificar históricos; não se trata de armazenamento inviolável.

## Próximo bloco

Auditar individualmente funções SECURITY DEFINER e permissões de participação/concessão; cobrir alterações concorrentes e revogação durante a operação. Completar validação autenticada em homologação com proprietário, secretaria, líder, financeiro e acesso revogado, incluindo gravação/edição/recarga e segundo navegador. Revisar filtros e alertas ainda demonstrativos. Manter piloto fechado e módulos não liberados contidos até os critérios do plano serem observados.
