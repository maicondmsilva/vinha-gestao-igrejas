# Autenticação real com MFA no ambiente local

Executor: `node scripts/local-platform-mfa-smoke.mjs --local-synthetic`.

## Achado e correção

A primeira tentativa falhou no cadastro TOTP: `mfa_totp_enroll_not_enabled`. O arquivo `supabase/config.toml` tinha cadastro e verificação TOTP desabilitados. Habilitadas as duas opções; reiniciado exclusivamente o projeto local `vinha` por stop/start, sem `--no-backup`, sem reset e preservando volumes. Produção não foi acessada.

## Resultado da reexecução

- Conta confirmada e operador admin criados exclusivamente para esta execução local.
- Login real por senha no Auth local.
- Identidade da Central recusada em aal1.
- Cadastro e desafio/verificação TOTP reais aceitos pelo Auth local.
- `verifiedPlatformIdentity` aceitou a conta correta em aal2, consultando o contexto real de operador no banco.
- Sessão encerrada; conta criada nesta execução e fator MFA removidos. Nenhuma conta preexistente foi excluída.
- Senha, segredo TOTP e tokens mantidos na memória e não gravados em arquivos ou logs.

O gerador TOTP de teste passou nos vetores SHA1 da RFC 6238. É utilitário de homologação para contas fictícias, não interface de autenticador para clientes.

## Limites

O executor usa Auth/RPC reais no serviço local e a função de verificação de identidade da aplicação; não chama as rotas HTTP de prévia e confirmação nem automatiza o navegador. As quatro candidatas proporcionais continuam não aplicadas persistentemente ao banco usado pelo navegador. É necessário preparar um destino local explícito para essas candidatas antes da homologação HTTP/UI. O botão de confirmação permanece bloqueado.

Documentação consultada: https://supabase.com/docs/reference/javascript/auth-mfa-enroll ; https://supabase.com/docs/reference/javascript/auth-mfa-challengeandverify ; https://supabase.com/docs/guides/local-development/cli/config . O índice changelog.md não pôde ser lido pelo navegador por tipo de conteúdo; nenhum SDK foi atualizado.
