# Sessões financeiras integradas — 18/10/2026

Executado `scripts/local-ledger-smoke.mjs --local-synthetic` contra servidor em 127.0.0.1:4100 e Supabase fixo em 127.0.0.1:54321. O script recusa outra URL. Credenciais sintéticas ficam somente em memória; não são impressas ou gravadas em arquivos. Não há envio de e-mail.

## Resultado: aprovado

- Login real, criação de ministério sintético e contas financeiras.
- Lançamento HTTP, reenvio com mesmo identificador e apenas um movimento confirmado.
- Estorno preservando o original e saldo final zero.
- Outra conta autenticada, com outro ministério, não consulta nem grava na unidade do primeiro: HTTP 403.
- Seleção explícita do primeiro ministério pela segunda conta também recusada.
- Secretaria com participação ativa não acessa bootstrap, consulta ou lançamento financeiro: HTTP 403.
- As três sessões sintéticas são encerradas ao final do teste bem-sucedido.

Referência local: `piloto-local-23062075-bc3f-4eec-b391-2620728d30ca`. Dados fictícios preservados no Docker; nenhum dado de cliente foi alterado.

## Limites

Teste integrado HTTP, não automação de navegador. Não confirma troca visual entre várias unidades autorizadas, nem falha de rede no navegador. A recuperação controlada está coberta separadamente pelos testes de handler. Nenhuma publicação, migração de produção ou atualização remota de PR neste bloco.
