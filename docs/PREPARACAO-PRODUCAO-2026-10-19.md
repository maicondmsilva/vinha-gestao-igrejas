# Preparação da publicação — 19/10/2026

## Solicitação atual

O responsável autorizou preparar e publicar as atualizações e deseja que as próximas melhorias sejam entregues em produção. Essa solicitação substitui a preferência anterior de trabalho exclusivamente local, mas não comprova prontidão técnica de recursos incompletos.

## Resultado desta conferência

- Checkout na branch `develop`, com alterações rastreadas e numerosos arquivos novos; não há pacote de lançamento fechado.
- A compilação Vercel foi aprovada na rodada imediatamente anterior. Nenhuma mudança de aplicação foi realizada nesta conferência.
- Verificação estática de segredos, tipos do escopo principal e oito testes de contenção/operação aprovados nesta rodada.
- Nenhum commit, push, deploy, alteração de contrato ou migração de produção executado nesta rodada.

## Impedimentos à liberação integral

O catálogo `app/lib/release-availability.ts` mantém Famílias, Aplicativo, Kids, Eventos, Células, Escalas, Louvor, Comunicação, Transmissões, Financeiro e Relatórios em desenvolvimento. Há caminhos legados intencionalmente contidos. Mudar o catálogo não migra seus dados nem implementa suas funções.

As migrações candidatas de proporcionalidade, créditos, ciclos, cancelamento e pagadores exigem reconciliação com o histórico efetivamente aplicado no banco principal antes de qualquer execução. Não aplicar indiscriminadamente todos os arquivos SQL.

Mercado Pago: credencial de uma conta de teste validada, mas não armazenada; ensaio de transporte com respostas fictícias aprovado. Retorno implementado localmente. Ainda não existe evidência de assinatura externa, recorrência, cancelamento, webhook e conciliação completos. Fiscal e WhatsApp ainda dependem de configuração e homologação próprias.

## Ordem de entrega necessária

1. Fechar inventário do diff e classificar alterações por dependência de schema, exposição pública e reversibilidade.
2. Conferir migrações aplicadas na conexão Vinha Igrejas, backup recuperável e estratégia de reversão; não usar outro projeto.
3. Executar a bateria completa de regressão no candidato fechado e a validação visual autenticada dos fluxos afetados.
4. Publicar somente o conjunto compatível, preservando contenção, MFA, isolamento por ministério/unidade e restrições comerciais.
5. Conferir implantação e fluxos essenciais na URL pública; só então registrar versão como entregue.
6. Liberar cada módulo remanescente após migração e testes ponta a ponta; cobrança real, fiscal e mensagens não devem ser ativados como simulação de conclusão.

## Política de próximas melhorias

Preparar alteração, testar, conferir impacto de banco, publicar, verificar e registrar resultado. Mudanças financeiras ou de acesso precisam de avaliação específica; autorização de publicação não elimina proteções nem autoriza efeitos externos inesperados.

## Conciliação realizada

- Pacote enviado no PR 34. Histórico de `main` integrado na branch de preparação.
- Conflito de unidades era exclusivamente CRLF/LF (conteúdo normalizado idêntico); preservado integralmente. Scripts de teste locais mais completos preservados no package.json.
- 200 testes passaram novamente; tipos principais e varredura estática de segredos aprovados.
- Consulta somente leitura à conexão Supabase **Vinha Igrejas** confirmou histórico até `20261017100325`. As 12 candidatas locais posteriores ainda não constam como aplicadas.
- Log da implantação Vercel `BdvuYEuhfmSQobwoeJs8B3Jod7Q2` confirmou: `Preview exige ambiente público test.` A validação de isolamento foi mantida. É necessário ambiente de homologação com projeto separado; não reutilizar o banco principal para contornar o erro.
- Produção não promovida. Próximas dependências: destino isolado de homologação e conferência/backup/validação das 12 migrações antes de aplicá-las ao principal. Nenhum dado de cliente foi alterado nesta conciliação.

## Execução autorizada posterior

- As 12 candidatas foram compiladas na estrutura real em transação desfeita e depois aplicadas atomicamente com `release_consolidated_sources_20261019`, versão efetiva `20261019033241`. As versões originais foram registradas na mesma transação, preservando compatibilidade do histórico local/remoto. O arquivo de recibo não repete DDL.
- Recuperação seletiva: definições de funções, ACLs, índices e políticas capturados em arquivo ignorado `outputs/recovery-production-schema-2026-10-19.json`; não é backup integral de dados. Não houve execução dos novos fluxos sobre clientes.
- Verificadas oito tabelas representativas: RLS habilitada, leitura anônima negada e INSERT direto autenticado negado. Bucket member-private confirmado privado. Bypass direto da confirmação proporcional negado.
- Bateria local: 12/13 suites passaram de primeira; a suite HTTP/MFA falhou por inicialização e passou na repetição isolada, com aal1 recusado e aal2 aceito. Compilação aprovada. CI remoto Build da aplicação aprovado antes do recibo.
- A prévia Vercel continua recusando ambiente sem homologação isolada. Essa proteção foi preservada; o candidato foi validado em banco local isolado. A implantação de produção será verificada separadamente, sem usar o principal em Preview.
