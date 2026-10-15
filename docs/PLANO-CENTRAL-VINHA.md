# Central Vinha — operação e próximos blocos

Atualizado em 15/10/2026. Guia consultável na aplicação: `/admin-vinha/guia`.

## Bloco em validação

- Atendimento: setores extensíveis, diretório público somente com nome/id, vínculo de operadores, fila com isolamento por setor, transferência auditada e alertas enquanto a Central estiver aberta.
- Contratos: pacote por unidade; rascunho, ativo e suspenso; módulos por pacote com liberações/bloqueios explícitos; solicitações da igreja sujeitas à Central.
- Cobrança: pagador por unidade ou sede, vencimento do pagador entre 1 e 28, prevenção de duplicidade de competência e separação entre contrato global e unitário.
- Cadastro financeiro: estilos responsivos e preferências explícitas de e-mail/WhatsApp.
- Avisos: fila idempotente de vencimento próximo, vencido e pagamento confirmado; canais desativados por padrão; envio precisa de configuração e autorização.
- Guia pesquisável de operação dentro da Central.

## Dependências para operação financeira externa

1. Configurar/testar credenciais do provedor financeiro e retorno autenticado. Não emitir cobrança real para testes sem autorização específica do responsável pelo pagamento.
2. Validar remetente de e-mail e domínio. Para avisos financeiros, configurar o canal Resend em Automações → Notificações. Isso é separado do SMTP de autenticação.
3. No canal WhatsApp, informar número/credencial e modelos aprovados em `provider_config.billingTemplates`: `upcoming`, `overdue`, `paid`; idioma em `billingLanguage` e versão de API em `apiVersion`. Cada modelo deve receber quatro parâmetros de corpo: referência, valor, vencimento e link/orientação. Configurar primeiro no provedor e testar com destinatário autorizado.
4. Habilitar `BILLING_NOTIFICATIONS_ENABLED=true` apenas depois de validar remetente, destinos e autorização. A rotina diária já prevista na Vercel processa a fila; a Central também oferece processamento manual. Não há envio instantâneo garantido após pagamento: depende da execução da rotina.
5. Status `submitted` significa aceito pela API, não entregue/lido. Falhas e envios de estado incerto devem ser conciliados no provedor antes de reenvio. Retornos de entrega ainda são próximo bloco.
6. Finalizar cartão recorrente com checkout hospedado, autorização, identificador de assinatura, retornos autenticados e cancelamento. A opção atual registra apenas interesse, não ativa débito.
7. Consolidar faturas unitárias em uma só cobrança da sede: ainda pendente. O pagador pode ser comum, mas os links permanecem separados. A fila nova não processa faturas já incluídas na consolidação antiga.
8. Auditar todos os pontos de acesso e RLS de cada módulo. O bloqueio do contrato foi conectado aos guardas comuns do servidor; rotas legadas e acesso direto aos dados precisam de cobertura completa antes de declarar enforcement integral.
9. Migrar a consulta antiga `/api/tenant` para Supabase: o resumo antigo da assinatura ainda depende do banco anterior. A nova área `/minha-assinatura` usa Supabase e fica acessível diretamente no início de Configurações, independentemente desse resumo.

## Novo bloco planejado: Dados da Vinha e fiscal

### Dados da empresa fornecedora

Área na Central para razão social, nome fantasia, CNPJ, inscrições aplicáveis, endereço, contatos, logotipo, responsáveis e dados fiscais. Separar dados da Vinha dos dados de cada igreja e do tomador. Restringir edição a administradores autorizados; versionar e auditar alterações. Certificados, chaves e senhas ficam somente em armazenamento seguro no servidor/provedor.

### Emissão de notas fiscais

- Validar com a contabilidade tipo de documento, regras aplicáveis, dados exigidos, provedor e momento de emissão. Não presumir regras tributárias ou emissão automática no pagamento sem essa definição.
- Relacionar nota, fatura, contrato, itens e tomador responsável. Na cobrança centralizada, validar qual CNPJ é o tomador e como os serviços por unidade devem constar.
- Impedir emissão duplicada, inclusive em novas tentativas e retornos repetidos do provedor.
- Acompanhar rascunho, solicitação, autorização, rejeição, cancelamento e substituição; manter protocolo e histórico.
- Disponibilizar documentos fiscais oficiais fornecidos pelo emissor. Não chamar recibo ou boleto de nota fiscal.
- Enviar aos e-mails dos responsáveis financeiros cadastrados/autorizados; registrar destinatários, envio, falha, confirmação de entrega quando fornecida e reenvio auditado.
- Homologar com o provedor antes de ativar emissão real. Nenhuma emissão ou envio fiscal foi realizado neste bloco.

## Referências técnicas

- [Segurança por linha no Supabase](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Checkout recorrente Asaas](https://docs.asaas.com/docs/checkout-com-assinatura-recorrente)
- [Modelos WhatsApp — referência Meta](https://whatsapp.github.io/WhatsApp-Nodejs-SDK/api-reference/types/TemplateObject/)

## Critérios de aceite antes de produção

Compilação, teste transacional com reversão, permissões negativas por setor e por igreja, validação visual responsiva, faturas repetidas sem duplicidade, teste de pagador/vencimento, auditoria de chaves e controle de acesso. Homologar notificações e recorrência separadamente, com autorização e provedores disponíveis. Não afirmar que uma funcionalidade está ativa apenas por existir sua tela.
