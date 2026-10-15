# Validação do bloco da Central — 15/10/2026

## Publicação

- Revisão [PR #11](https://github.com/maicondmsilva/vinha-gestao-igrejas/pull/11), commit de produção `71b7a2b6d78b5d26731817bab4470fe5a354f232`.
- Compilação padrão e empacotamento Vercel concluídos. O empacotamento Vercel no Windows precisou de execução fora da restrição de gravação inicial. O artefato de produção foi gerado pela Vercel em seu próprio ambiente, não enviado do Windows.
- Verificações GitHub e implantação Vercel aprovadas.
- Migração confirmada pelo Supabase: `20261015085439_central_departments_unit_contracts.sql`. O arquivo local foi alinhado à versão efetivamente registrada pelo serviço.

## Testes

- `npm run test:central`: cinco testes aprovados (janela de três dias, atraso, quitação, cancelamento e não envio de recibos antigos).
- Teste transacional `central_sectors_contracts_transaction.sql`: aprovado, com reversão dos registros. Cobre leitura por setor, transferência e perda de acesso ao setor anterior, acesso anônimo negado às tabelas, diretório restrito, visibilidade de unidades na Central, geração idempotente, vencimento do pagador, ausência de faturamento global e unitário duplicados, baixa de fatura unitária, bloqueio de módulo, solicitação do cliente sem alteração do contrato e bloqueio de alteração comercial por cliente.
- Regressão `trial_and_support_chat_transaction.sql`: aprovada com a nova estrutura, em transação revertida.
- Compilação de tipos completa ainda não passa por dívida anterior no repositório; não declarar o projeto inteiro livre de erros de TypeScript. Os novos arquivos foram revisados e compilados pelo build da aplicação.
- `check:buttons`: dentro do limite existente, mas ainda identifica 49 controles legados sem ação explícita. Isso não equivale a certificar todos os botões de todos os módulos.
- Arquivos de código/banco conferidos sem bytes nulos após recuperação das edições interrompidas.

## Salvaguardas de operação

Após a migração, o banco manteve uma fatura preexistente; nenhum contrato unitário foi ativado e nenhum aviso financeiro foi criado. Foram criados apenas os três setores iniciais: Comercial, Suporte e Financeiro. Os testes não chamaram provedores externos nem enviaram mensagens, e-mails ou cobranças reais. Códigos sequenciais podem ter lacunas decorrentes de transações revertidas, comportamento normal de sequências do PostgreSQL.

Cartão recorrente registra interesse, sem débito ativo. Emissão fiscal e área Dados da Vinha estão documentadas no plano e no guia, não implementadas como serviços ativos. SMTP de autenticação continua pendente, sem mudança de credenciais.

## Segurança

RLS habilitado nas novas tabelas e autorizações verificadas em testes negativos. A implementação privilegiada fica no schema privado; os wrappers públicos têm grants restritos e verificam identidade, função, setor ou organização. A leitura pública de setores retorna apenas identificador e nome ativos. Diretório de operadores não retorna e-mail ou credenciais.

O verificador Supabase mantém avisos sobre funções privilegiadas expostas de forma intencional (convites, chat e wrappers autenticados). Conferir continuamente seus controles internos; não remover a autorização apenas para silenciar o verificador. Referências: [funções públicas](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [funções autenticadas](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Permanece um aviso anterior: proteção contra senhas vazadas desabilitada. Nenhuma proteção foi desligada por este bloco. [Orientação oficial](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

O bloqueio contratual foi conectado aos guardas comuns do servidor. A auditoria completa de rotas legadas, seleção de unidade, menus e acesso direto a dados por módulo permanece necessária; não afirmar enforcement integral em todos os módulos.
