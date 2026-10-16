# L1 — bloco 9: segurança dos convites de ministérios

## Situação

Em revisão, sem aplicação no Supabase de produção e sem publicação. A aplicação em produção depende de autorização específica e da aprovação dos testes. Este bloco não encerra a L1 nem libera o piloto comercial.

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
- Testes SQL adicionais preparados para e-mail confirmado/alterado, identidade real versus e-mail do token, expiração, revogação, emissor suspenso, ministério suspenso e retomada sem elevação de poderes.
- Teste transacional anterior atualizado para distinguir a identidade real de um e-mail forjado no token.
- O Docker local está inacessível nesta sessão por permissão no canal do mecanismo. Nenhum teste foi redirecionado para produção. A validação SQL será feita no banco efêmero da integração contínua.
- O arquivo de migração foi criado com a ferramenta oficial; não foi gerado por comparação com o banco local nem por consulta de estrutura em produção. A execução SQL ainda precisa ser comprovada pela integração contínua.
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

Depois dos testes e de autorização específica, aplicar somente a migração deste bloco pelo conector Vinha Igrejas, conferir estrutura/permissões e publicar o código aprovado. Em caso de regressão, corrigir seletivamente o fluxo afetado, sem voltar a promover ou reativar participantes por convite.
