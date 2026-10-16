# L1 — bloco 11: identidade confirmada no cadastro inicial

Base publicada: 3922262c854a697d1a35c726d24d66f7c44b538c. Em revisão, sem aplicação desta migração em produção. Requer testes isolados e autorização específica antes da implantação. Não encerra L1 nem libera o piloto.

## Problema comprovado

Inspeção somente de leitura no Supabase Vinha Igrejas confirmou que register_organization_trial ainda obtinha o e-mail pelo JWT e bootstrap_organization não verificava confirmação. A API verificava email_confirmed_at, mas isso não protegia uma chamada direta ao banco. A nova proteção de campos do bloco 10 tampouco confirmava a conta ao aceitar INSERT direto.

## Mudanças

- Verificador privado consulta apenas a conta de auth.uid(), sem receber identificador de terceiro, exigindo e-mail atual confirmado, conta existente, não removida, não anônima e sem suspensão vigente na autenticação. Mantém lock de leitura na conta durante a transação.
- O acesso privilegiado existe somente para essa leitura interna de auth.users; não abre a tabela ao cliente nem cria endpoint público. Cadastro e bootstrap continuam SECURITY INVOKER, sujeitos à RLS.
- Bootstrap, cadastro/retomada de demonstração e INSERT direto de organização como authenticated exigem essa identidade. A demonstração e o contato inicial da sede recebem o e-mail atual do banco, não uma cópia antiga da sessão.
- INSERT direto de registro de demonstração não pode gravar e-mail de outra pessoa. As funções internas da Central e de provisionamento continuam com suas autorizações próprias.
- API recusa falha de autenticação mesmo se vier acompanhada de objeto de usuário; não prossegue com falha na consulta de convite; valida destinos e resultados antes de declarar sucesso; retorna respostas privadas e erros sem detalhes internos.

Sem reclassificação, exclusão ou envio automático de mensagens. Contas antigas não são suspensas: contas não confirmadas ou indisponíveis apenas deixam de criar/retomar ambientes por esses caminhos até resolver sua situação.

## Testes e limites

Preparados testes SQL de confirmação, mudança de e-mail, conta suspensa/removida/anônima/inexistente, acesso direto, idempotência e isolamento de identidade; testes da rota real com banco simulado cobrem falhas e respostas privadas. Validar SQL no banco efêmero do CI: Docker local está inacessível por permissão do canal. Migração criada com ferramenta oficial, não por diff local. Não testar gravações em produção.

Isto não valida entrega de e-mail/SMTP com conta real, não altera a configuração de confirmação do Supabase, não substitui revogação de sessões e não adiciona verificação estrita de session_id em auth.sessions. Uma suspensão da autenticação não é o mesmo que a suspensão do contrato do ministério. Outros endpoints e todos os cenários concorrentes continuam exigindo revisão própria. O limite de tamanho da API é conferido após leitura do corpo; limitação de tráfego/abuso e leitura incremental ficam para revisão específica. Não há aprovação global de TypeScript nem nova inspeção visual de telas autenticadas.

## Aplicação e recuperação

Após CI aprovado e autorização específica, aplicar somente pela conexão Vinha Igrejas no projeto aoxibaaydfgffrdqtkva; conferir funções, gatilhos, RLS e grants sem criar clientes fictícios. Alinhar versão registrada e publicar o código aprovado. Em regressão, corrigir seletivamente sem remover a exigência de identidade confirmada nem confiar no e-mail do JWT.

As orientações Supabase levaram a manter as gravações como invoker e restringir o uso de definer à leitura da própria identidade. Referências: [changelog](https://supabase.com/changelog), [usuários anônimos](https://supabase.com/docs/guides/auth/auth-anonymous), [sessões](https://supabase.com/docs/guides/auth/sessions).
