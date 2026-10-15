# Integrações financeiras — desenvolvimento e homologação

## Entrega deste bloco

- Dados da Vinha: CNPJ validado, contato, município, inscrição, logotipo, serviço e configuração tributária revisada. Edição administrativa com MFA; versão otimista evita sobreposição entre operadores. Histórico no registro de auditoria. Sem certificados ou credenciais no formulário.
- Cartão recorrente: construção e envio de checkout mensal hospedado **somente em sandbox Asaas**, mediante solicitação no contrato, cadastro do pagador e confirmação do operador. Primeiro ciclo depois da competência da fatura selecionada. Identificadores, trava de envio, acompanhamento autenticado e estados separados de confirmação.
- Fiscal: preparação, agendamento sandbox, consulta e retornos autenticados, vinculados a uma cobrança Asaas paga e identificada. Checkout não é pagamento fiscal. Valor e referência são conferidos no provedor antes de enviar; documento somente autorizado por confirmação oficial. PDF/XML vêm do provedor, não são PDFs gerados como se fossem NFS-e.
- Avisos: identidade visual Vinha, logotipo opcional; validação do domínio Resend e dos três modelos utilitários Meta, idioma, vínculo do número à conta e quatro parâmetros de corpo. As consultas não enviam mensagens. Verificação vence em sete dias e mudanças invalidam sua assinatura interna.
- Entrega: callbacks assinados, idempotentes e registrados; confirmação não é perdida se chegar antes da resposta de envio. E-mail entregue e WhatsApp lido não são inferidos do simples aceite da API. Não há confirmação de leitura de e-mail.
- Assinatura: `/api/tenant` usa Supabase, não o D1. Nenhuma assinatura é criada/alterada por GET. Consulta de outro ministério é recusada. Contagens são filtradas por organização e pelas políticas de acesso do próprio usuário.

## Verificações executadas

- 14 testes automatizados: regras de aviso, payload recorrente/fiscal, calendário, CNPJ, sanitização de HTML e URLs, assinatura oficial de exemplo Svix, adulteração/expiração, assinatura Meta, transporte restrito ao sandbox e falhas HTTP.
- Teste SQL transacional com rollback: versão concorrente, tentativa de edição direta sem auditoria, acesso cruzado, alteração de dados da Vinha por igreja, falsa entrega, dados financeiros protegidos, retorno antecipado, idempotência e não regressão de status. Sem criação persistente de usuários/ministérios/faturas de teste.
- Verificação de controles: 49 controles legados, sem aumento. Isso não certifica todos os controles do produto.
- Compilação para Vercel concluída; empacotamento Windows exigiu permissão para vínculos locais. Não publicar o pacote nativo Windows na Vercel; o serviço deve compilar no Linux pelo repositório.
- Lint das novas áreas/APIs/helpers aprovado. Checagem completa de tipos ainda encontra dívida técnica anterior; não declarar TypeScript global limpo.
- Nenhuma chamada financeira externa de criação, cobrança recorrente, emissão fiscal, e-mail ou WhatsApp foi executada na validação. Provedores de cobrança não estavam configurados; e-mail/WhatsApp estavam inativos e sem remetente.

## Ativação ainda pendente

Migração aplicada como `20261015093256_financial_integrations_tenant_summary.sql`. Confirmado após aplicação: zero operações financeiras, zero perfis da Vinha, zero eventos de entrega e zero avisos novos. As massas dos testes foram revertidas.

O verificador de segurança sinaliza as duas tabelas de eventos com RLS sem políticas: é intencional, pois clientes não recebem grants nem políticas e somente o servidor privilegiado processa esses eventos. [Explicação do aviso](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy). Avisos anteriores de funções privilegiadas devem seguir auditados; nenhuma autorização foi removida para silenciá-los. Permanece a pendência anterior de [proteção contra senhas vazadas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Índices novos ainda sem uso são esperados nas tabelas vazias; não foram removidos por esse motivo. Os índices de chaves estrangeiras ausentes apontados pelo verificador são de tabelas anteriores a este bloco e continuam no backlog de desempenho.

1. Confirmar contas/provedores e conta emissora da Vinha, com a contabilidade. O cadastro local não configura a prefeitura nem substitui a configuração fiscal do provedor.
2. Homologar Asaas com dados de teste autorizados. A chave do ambiente deve ser sandbox e testada; `FINANCIAL_SANDBOX_ENABLED=true` habilita apenas envio ao sandbox. Não trocar a conta real de um provedor em uso para fazer testes. Como as configurações atuais têm uma linha por provedor, isolamento simultâneo de credenciais sandbox/produção é um requisito antes do uso real.
3. Configurar webhook Asaas `/api/webhooks/saas-billing/asaas`, token forte e eventos de checkout, assinatura e fiscal. A associação de assinatura só ocorre com referência exata; se o checkout não propagar `externalReference`, exige conciliação explícita ainda a implementar, nunca associação por nome/valor.
4. Completar cancelamento de assinatura no provedor, conciliação dos pagamentos mensais, atualização de preço/pagador/vencimento, recuperação de falhas e prevenção de duplicidade com geração mensal interna. Até isso ser homologado, **não habilitar produção**. O cancelamento do checkout não equivale ao cancelamento de uma assinatura já criada.
5. Fiscal real: confirmar tributos/deduções, dados completos do tomador, regime/regras municipais e momento de emissão. Falta cancelamento/substituição, envio da nota aos responsáveis com rastreamento e conciliação de resultado incerto. O protótipo sandbox usa deduções zero; não presumir esse valor na emissão real.
6. Resend: domínio verificado, remetente e credencial segura; consultar domínio em Integrações financeiras. SMTP de autenticação Supabase continua separado e não foi alterado.
7. Meta: conta WhatsApp, número, credencial e três modelos utilitários aprovados. Credenciais em Alertas; modelos e validação em Integrações financeiras. Consulta limitada aos primeiros 100 números/modelos; contas maiores exigem paginação antes da operação real.
8. Retornos de entrega: `/api/webhooks/billing-delivery/email` com `BILLING_RESEND_WEBHOOK_SECRET`; `/api/webhooks/billing-delivery/whatsapp` com `BILLING_META_APP_SECRET` e `BILLING_WHATSAPP_VERIFY_TOKEN`. Validar os endpoints no provedor. Nunca colocar essas chaves em variáveis públicas ou no chat.
9. Solicitar destinatário real autorizado (usuário adiou informar). Testar entrega e retorno antes de `BILLING_NOTIFICATIONS_ENABLED=true`; não fazer envio em massa durante teste. Revalidar canais a cada sete dias. Os envios antigos de alertas operacionais têm fluxo diferente e ainda precisam unificar seus estados com os novos callbacks.
10. Cadastros aprovados, consentimentos e canais habilitados continuam obrigatórios. Crons diários não garantem envio imediato. Notas de homologação não são enviadas automaticamente aos clientes.

## Inventário de banco legado

Após remover `/api/tenant`, 55 arquivos em `app/api` ainda contêm `env.DB`. Há caminho Supabase explícito em `_auth.ts`, `people/route.ts` e `units/route.ts`; isso não prova cobertura integral dos helpers. Os outros 52 arquivos precisam de revisão/migração.

- Alta prioridade: segurança/usuários/convites da igreja; financeiro e retornos de pagamentos; Eventos públicos e inscrições.
- Próximo: termos/consentimentos/documentos e Kids/responsáveis/check-in; são dados sensíveis, não podem ser migrados apenas trocando nome de tabela.
- Depois: células, escalas, chat interno, arquivos e notificações do aplicativo; preservar permissões por unidade e hierarquia.
- `app/api/platform` já não referencia D1; serviços financeiros desta entrega e nova consulta usam Supabase. A Central não é o painel das igrejas.

Referências: [recorrência Asaas](https://docs.asaas.com/docs/checkout-com-assinatura-recorrente), [NFS-e Asaas](https://docs.asaas.com/reference/agendar-nota-fiscal), [validação de retornos Resend](https://resend.com/docs/webhooks/verify-webhooks-requests), [assinatura Svix](https://docs.svix.com/receiving/verifying-payloads/how-manual).
