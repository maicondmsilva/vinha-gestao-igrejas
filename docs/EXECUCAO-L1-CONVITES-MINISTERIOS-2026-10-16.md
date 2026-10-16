# L1 — bloco 9: segurança dos convites de ministérios

## Situação

Autorizado especificamente pelo usuário em 16/10/2026. Migração aplicada no Supabase Vinha Igrejas, projeto aoxibaaydfgffrdqtkva, com versão efetiva 20261016222547. Publicação do código em acompanhamento. Este bloco não encerra a L1 nem libera o piloto comercial.

## Mudanças propostas

- Aceitar convites somente com conta válida e e-mail confirmado, conferido no cadastro atual de autenticação, não no e-mail possivelmente antigo do token da sessão.
- Recusar convites expirados, revogados, de ministérios indisponíveis ou emitidos por operador que não possa mais conceder o acesso.
- Impedir que aceitar um convite reative participação suspensa ou promova uma participação existente de papel inferior.
- Vincular o convite aceito à conta que o utilizou. A retomada só funciona com participação ainda ativa e nunca restaura poderes antigos.
- Para convites antigos sem vínculo de conta, permitir apenas a retomada de proprietário já ativo, sem conceder novos poderes.
- Ocultar nome e e-mail do destinatário na consulta pública de convites que não estejam pendentes e válidos.
- Proteger a requisição de ativação contra origem diferente, entradas inválidas, falhas de autenticação e exposição de erros internos; impedir cache das respostas.

Não há remoção de dados, migração de destinatários antigos nem suspensão automática de contas existentes. Convites pendentes incompatíveis com as regras passam a ser recusados.

## Validação

- 62 testes de aplicação aprovados: 44 de segurança, 14 da Central e 4 de preparação para publicação.
- 730 asserções SQL aprovadas em 13 arquivos, incluindo e-mail confirmado/alterado, identidade real versus e-mail do token, expiração, revogação, emissor suspenso, ministério suspenso e retomada sem elevação de poderes.
- Build e 6 cenários concorrentes anteriores de governança aprovados no CI 38971820998, commit 2d4c1d5eeaa801dc2bf7ccde18e101169d82f20c. Prévia Vercel aprovada. O ajuste posterior apenas alinha o nome do arquivo com a versão efetivamente registrada em produção e atualiza este documento; o SQL não foi alterado.
- Teste transacional anterior atualizado para distinguir a identidade real de um e-mail forjado no token.
- O Docker local está inacessível nesta sessão por permissão no canal do mecanismo. Nenhum teste foi redirecionado para produção. A validação SQL foi feita no banco efêmero da integração contínua.
- O arquivo de migração foi criado com a ferramenta oficial; não foi gerado por comparação com o banco local nem por consulta de estrutura em produção. A execução SQL foi comprovada pela integração contínua.
- Conferência em produção: coluna accepted_user_id do tipo uuid, RLS da tabela de convites mantida, validação do e-mail confirmado e bloqueio de acesso revogado presentes, aceitação indisponível a anon e disponível a authenticated, esquema private indisponível a anon. Sem cadastros fictícios em produção.
- Avisos de segurança anteriores continuam pendentes: tabelas com RLS sem política, funções privilegiadas expostas de forma controlada e proteção contra senhas vazadas desativada. Nenhuma regra foi reaberta para ocultar esses avisos.
- Consulta restrita em produção não encontrou convites de ministério existentes no momento da inspeção; isso não substitui os testes isolados nem garante que não surjam novos registros depois.

## Limites e próximos cuidados

- Não foi validada a entrega de e-mail com conta real neste bloco.
- Não foi feita inspeção visual das telas autenticadas nesta etapa.
- Não há nova verificação estrita da existência da sessão em auth.sessions; a verificação usa a identidade autenticada e o cadastro atual da conta.
- A consulta pública de prévia não verifica a situação do emissor; a aceitação a verifica e recusa o acesso quando necessário.
- Os testes concorrentes anteriores continuam relevantes, mas não comprovam todas as combinações de disputa entre emissão, revogação e aceitação de convites.
- Imutabilidade completa do registro de convite, limites contra abuso e interface de sucessão administrativa não fazem parte desta entrega.
- Não há afirmação de aprovação global de TypeScript nem de eliminação das pendências anteriores da plataforma.

## Aplicação e recuperação

Aplicação autorizada e realizada pelo conector Vinha Igrejas; estrutura e permissões conferidas. Publicar somente o código aprovado e verificar a implantação de produção. Em caso de regressão, corrigir seletivamente o fluxo afetado, sem voltar a promover ou reativar participantes por convite.
