# L1 — bloco 10: campos administrativos do ministério

## Estado

Base publicada: 80ade0a2f7bec3d4aea516d6f5cfd23b272fea29. Proposta em revisão, sem aplicação desta migração em produção. Exige testes isolados e autorização específica antes de aplicação/publicação. O bloco não encerra L1 nem libera o piloto comercial.

## Evidência e mudança delimitada

A inspeção somente de leitura confirmou que organizations_update_admin permite UPDATE por proprietário, administrador ou pastor sem limitar colunas. A função de papel verifica a participação ativa, não o estado comercial da organização. Por isso um gestor poderia mudar diretamente o status e contornar uma suspensão do ministério. Também faltava proteção de criador, identidade, endereço digital e data original neste caminho.

A proposta mantém a RLS e acrescenta um gatilho SECURITY INVOKER, sem elevar privilégios:

- Para UPDATE executado como authenticated, permite somente nome, razão social, documento, cor principal, cor secundária, nome do aplicativo e pastor titular. O horário de atualização vem do banco.
- Impede alterar diretamente id, slug, status, bootstrap_user_id, created_at, registration_code e futuras colunas não explicitamente autorizadas. A proteção já existente do código de identificação continua valendo.
- Recusa mudanças de configuração em ministérios suspensos ou cancelados, sem retirar leituras já autorizadas.
- Para INSERT de cliente, exige estado trial, criador igual à conta autenticada e data original do banco. O cadastro legítimo inicial continua criando a sede e o proprietário pelas regras anteriores.
- A Central continua usando suas funções privilegiadas já autorizadas; a sincronização interna de assinatura continua controlando o estado comercial. Não se concede nova permissão a operadores ou a clientes.

Não há alteração automática de registros existentes, exclusão de dados ou mudança de papéis. Gestores que usavam gravação direta de status/endereço/criador precisarão usar um procedimento administrativo legítimo; não reabrir esses campos para contornar a regra.

## Validação e limitações

Testes pgTAP preparados para papéis owner/admin/pastor/viewer, isolamento entre ministérios, campos permitidos e recusados, suspensão, horário do banco, bootstrap legítimo e sincronização interna de assinatura. A suíte existente cobre o cadastro de demonstração e as operações da Central. A execução SQL será comprovada pelo CI antes de pedir autorização.

O Docker local continua inacessível por permissão do canal nesta sessão. Não haverá teste substituto com escrita em produção: usar o banco efêmero do GitHub Actions. Migração criada com a ferramenta oficial, não por comparação local; revisar seu SQL e permissões explicitamente.

Não foi adicionada uma interface de transferência de titularidade/endereço, trilha completa de mudanças de configuração ou prova de todos os cenários concorrentes. A proteção distingue execução direta como authenticated de execução interna como owner da função: ainda é necessário revisar separadamente as funções privilegiadas e credenciais de serviço. Confirmação de e-mail/sessão no cadastro inicial, campos das unidades, arquivos, proteção contra abuso e entrega de e-mail real não são resolvidos por este bloco.

As orientações de privilégio mínimo do Supabase levaram a preservar a RLS e usar um gatilho invoker, em vez de ampliar acesso ou converter a gravação em SECURITY DEFINER. Referências consultadas: [changelog](https://supabase.com/changelog), [gatilhos](https://supabase.com/docs/guides/database/postgres/triggers) e [controle de colunas](https://supabase.com/docs/guides/database/postgres/column-level-security).

## Aplicação e recuperação

Somente após testes e autorização específica: aplicar no projeto aoxibaaydfgffrdqtkva pela conexão Vinha Igrejas, confirmar gatilho, função invoker e acessos; conciliar o nome da migração com a versão real e publicar o código/histórico aprovado. Em regressão, reproduzir isoladamente e corrigir a operação legítima afetada, sem permitir reativação comercial por atualização direta do cliente. Permanecem as demais pendências do plano de lançamento.
