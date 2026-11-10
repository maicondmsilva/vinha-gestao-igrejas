# Homologação local Docker — 18/10/2026

## Resultado verificado

- Docker Engine 29.8.2 disponível; WSL2. Supabase local já existia e foi preservado.
- Cópia prévia do banco local em `outputs/local-recovery-20261018/before-migrations.dump` (540709 bytes), ignorada pelo Git. É precaução local sem criptografia externa, não comprovação de backup L3/restauração ou cópia de Storage.
- Simulação com `db push --local --dry-run --skip-vault`, seguida da aplicação explícita das 35 migrações pendentes com `--local --skip-vault --yes`. Sem reset, seed ou acesso ao projeto principal.
- Suíte pgTAP local: 22 arquivos, 1047 testes, PASS. O cadastro local preexistente foi preservado.
- Aplicação iniciada em loopback `http://127.0.0.1:4100`, com URL/chaves do Supabase local em memória e modo piloto habilitado apenas nesse processo. Nenhuma chave gravada em arquivo ou exibida.
- Smoke HTTP real: criação de conta Auth local sintética confirmada, login por senha aleatória, bootstrap de ministério, duas contas, lançamento de 12345 centavos, reenvio do mesmo UUID sem duplicar, estorno e saldo zero. Logout ao finalizar.
- Referência sintética preservada: `piloto-local-af379640-0b0d-426c-b773-675e26840218`. Nenhum pagamento, mensagem ou nota fiscal emitido. Os dados locais não são clientes reais e não foram enviados à produção.
- Navegador abriu a interface local; sessão ausente foi recusada com “Autenticação necessária”. Isso NÃO comprova ainda o fluxo visual autenticado, os botões sob interrupção de rede ou a experiência completa de usuário.

## Reprodução

Docker Desktop deve estar com o motor ativo e o Supabase local atualizado. A partir da pasta do projeto:

1. `node scripts/local-ledger-dev.mjs` — aplicação local, porta 4100, sem publicação. Recusa configuração com API_URL diferente de `http://127.0.0.1:54321`; não altera `.env` nem política de execução do Windows.
2. Em outro terminal, `node scripts/local-ledger-smoke.mjs --local-synthetic` — cria NOVOS dados fictícios em cada execução no banco Docker. Não usar para produção e não esperar limpeza automática. O usuário de teste não recebe e-mail; a senha fica somente na memória e a sessão é encerrada.
3. Encerrar o servidor ao finalizar a sessão de teste. O banco/volumes permanecem.

O leitor de configuração aceita JSON válido do CLI mesmo com saída não zero por serviços opcionais parados. Isso não transforma serviço indisponível em sucesso: Auth/REST/banco são efetivamente exercitados pelo smoke. O serviço opcional de logs vector estava reiniciando; monitoramento L3 não é considerado ativo.

## Limites

Nenhuma mudança em produção, variáveis Vercel ou deploy. A prévia Vercel continua corretamente bloqueada sem ambiente cloud de teste separado. Um banco Docker em loopback não fica acessível a uma função Vercel; não abrir portas/túneis públicos para contornar isso.

Ainda faltam sessão real no navegador, ensaio visual de cadastro/lançamento/reenvio/fechamento, conciliação e dependências L3/L4 já registradas. Não declarar todas as fases concluídas com este teste.
