# Migração da Central e ativação para Supabase — 14/10/2026

## Escopo entregue

- Configuração inicial, sessão do painel e seleção de ministério passam a validar o usuário e os vínculos no Supabase. Um tenant explícito sem permissão é recusado, sem substituir silenciosamente pela primeira igreja.
- Onze APIs da Central migradas: cobranças, perfis financeiros, provedores, consolidação, hierarquia, solicitações, suporte, conhecimento, tarefas/regras, notificações e execuções.
- Retorno de pagamento e rotina agendada adaptados para execução no servidor da Vercel. Nenhuma chave privilegiada é enviada ao navegador.
- Convite aceito permite retomar o acesso; convite revogado/expirado não permite ativação. Login, confirmação e MFA preservam o destino do convite. Contas com convite pendente não são enviadas automaticamente para criar um segundo ministério.
- Cadastro e ficha da Central usam tratamento de falha e liberação do estado de carregamento; link de ativação permanece disponível para cópia manual. Erros aparecem também dentro das janelas abertas. Pastor titular informado separadamente do responsável pela conta.
- Navegação interna da Central utiliza links nativos, evitando interceptação de navegação incompatível com a hospedagem atual.
- Hierarquia preserva os dados e exige aprovação das duas organizações. Cobranças mensais e notificações possuem chaves de idempotência.

## Banco e segurança

Três migrações aditivas aplicadas: `20261014230506`, `20261014231035` e `20261014231535`. São 18 novas tabelas operacionais com RLS, funções transacionais e índices. Cadastros existentes não foram apagados. Os nomes dos arquivos anteriores foram alinhados às versões realmente registradas no Supabase, sem alterar seu conteúdo.

A Central exige operador ativo e MFA. Usuários de igreja não consultam cobranças internas da Vinha. Convites são aceitos somente pela conta correspondente. Webhooks verificam credenciais/assinatura ou consultam o pagamento no provedor antes de registrar recebimento, com verificação de valor e repetição segura.

## Verificações realizadas

- Compilação direcionada à Vercel concluída.
- Verificação de qualidade dos arquivos novos e dos principais arquivos alterados concluída; isso não equivale a corrigir todos os avisos históricos do repositório.
- Verificação de controles interativos concluída; o limite legado de 49 controles não aumentou.
- `supabase/tests/central_activation_transaction.sql` executado no banco com resultado `passed` e rollback dos dados de teste: cadastro, renovação/revogação, prévia anônima, bloqueio de e-mail incorreto, convite repetido, isolamento financeiro, etapas obrigatórias, conclusão do onboarding, cobrança idempotente, suporte, artigos, tarefas, histórico de execução, aprovação dupla e bloqueio de ciclo hierárquico. Sequências de numeração podem avançar mesmo com rollback.
- Não foram enviados pagamentos, mensagens ou e-mails reais durante os testes. Não houve teste visual autenticado em navegador nesta execução.

## Configuração externa ainda necessária

No servidor da Vercel, configurar `SUPABASE_SECRET_KEY` (ou a chave legada `SUPABASE_SERVICE_ROLE_KEY`), `PAYMENT_CREDENTIALS_MASTER_KEY` e `CRON_SECRET`. Esses segredos não foram inventados nem copiados para o repositório. As credenciais públicas do Supabase continuam sendo as variáveis `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.

Provedores de pagamento e canais de notificação devem ser configurados e testados pela Central antes de ativar recebimentos e envios. A rotina diária foi definida para 11h UTC (08h em Brasília), mas depende das chaves de servidor. A cobrança não gera links externos sem o processamento seguro de retorno configurado.

## Limite desta entrega

Esta migração cobre os cinco problemas identificados na auditoria da Central/ativação. Não significa que todos os módulos operacionais da igreja já foram migrados: ainda há serviços legados de outros módulos no repositório, que exigem sua própria migração e validação. Nenhum conteúdo histórico existente exclusivamente no banco antigo foi presumido como importado.
