# Mercado Pago — preparação local

## Estado

E-mail de recuperação Vinha recebido com a nova formatação, confirmado pelo usuário. Próximo bloco: Mercado Pago. Nenhum deploy, configuração remota, cobrança ou conta externa foi criado nesta rodada.

## Alterações locais

- Preparação do Checkout Pro valida centavos inteiros positivos, limites, pagador, referência e expiração antes da chamada.
- Retornos usam HTTPS, sem credenciais/fragmentos, no mesmo domínio da operação. Essa validação não é uma certificação de resolução DNS; o servidor continua responsável pelos endereços usados.
- Resposta deve conter identificador e `init_point` no domínio brasileiro oficial e apontar para a mesma preferência. Não há fallback para `sandbox_init_point`, nem identificador inventado.
- Chamada do Checkout Pro tem limite de tempo e não segue redirecionamentos HTTP.
- Fluxo genérico marcado sandbox fica bloqueado **antes de enviar**. Marcar sandbox no cadastro não comprova conta vendedora de teste. O bloqueio também exige revisar a futura ativação e os callbacks, não apenas trocar esse campo para produção.
- Sete testes novos, incluindo zero chamadas externas no caminho de teste bloqueado; regressões dos adaptadores existentes executadas separadamente. Recorrência Mercado Pago ainda não foi implementada nem homologada por estas alterações.

## Próxima dependência

### Avanço confirmado no painel

Aplicação `Vinha — Assinaturas`, ID `4450309494413763`, criada pelo usuário. Ativação das credenciais de teste confirmada no painel; contas com papéis Comprador e Vendedor disponíveis. Nenhum token foi copiado pelo agente. Ativar as credenciais não conecta a Vinha nem comprova um pagamento.

### Preparação de assinaturas e entrada segura

`app/api/payments/mercado-pago-subscription.ts` prepara rascunhos mensais BRL pendentes, com comprador `@testuser.com`, data futura canônica e retorno exclusivo de homologação. É uma função sem transporte: não há endpoint de criação, não salva assinatura e não habilita o domínio de teste. O retorno previsto ainda precisa de implantação isolada. Validação de respostas recusa divergências e exige modo teste explícito; `authorized` nunca retorna pagamento confirmado. A compatibilidade real dos campos deve ser conferida na homologação, sem retirar validações para simular sucesso.

O responsável pode executar no terminal do projeto:

```powershell
node scripts/mercado-pago-readonly-credential.mjs --test-readonly
```

O programa pede o Access Token de teste com entrada oculta. Não usar transcrição/gravação de terminal, não passar token como argumento nem colar na conversa. O único pedido é GET fixo para `https://api.mercadopago.com/users/me`, com tempo limitado e sem seguir redirecionamentos. Não cria nem cancela nada e não persiste a chave. Não foi executado com uma credencial real nesta rodada.

Atualização de 19/10/2026: os diagnósticos de leitura aceitam `TEST-` e `APP_USR-`. O prefixo não prova isolamento: o resultado distingue credencial aceita de identidade de teste comprovada pela tag retornada. Nenhuma permissão de pagamento passou a aceitar um token por essa alteração. Se a comprovação não existir, o envio permanece bloqueado. Isso não substitui homologar uma assinatura.

Alternativa ao PowerShell bloqueado e à entrada raw do Node: `node scripts/mercado-pago-credential-form.mjs --test-form`. Abre servidor somente em 127.0.0.1, porta aleatória e caminho imprevisível, válido por dez minutos. Campo password sem persistência; GET externo fixo ao Mercado Pago apenas após o responsável enviar. Proteções de Host, Origin, CSRF, tamanho, tempo e uso único; respostas não contêm credenciais nem dados pessoais da conta. Nenhuma mudança de política de execução do Windows. O usuário deve substituir a credencial anteriormente compartilhada antes de usar o formulário. Não registrar token em argumentos, chat, arquivos ou capturas. Novo conjunto: **194 testes aprovados**, incluindo concorrência, recusa de origem/CSRF e ausência do token na resposta. A primeira tentativa de testes HTTP foi impedida pelo sandbox (EACCES); reexecução com autorização de rede local passou. Consulta com credencial real continua dependente da ação do usuário no campo.

Referência oficial de testes de assinaturas: https://www.mercadopago.com.br/developers/pt/news/2023/11/16/Questions-on-how-to-test-your-integration-- — uso de conta de teste vendedora; jamais inferir modo pelo prefixo isoladamente.

Oito testes novos de assinaturas/consulta adicionados: conjunto da aplicação agora com **190 testes aprovados**. Tipos do módulo e varredura estática de segredos aprovados. Nenhuma migração, publicação ou chamada externa financeira feita.

No Mercado Pago Developers: criar/selecionar aplicação da Vinha; localizar contas de teste vendedor/comprador e credenciais correspondentes; configurar credencial somente em armazenamento seguro, nunca chat/Git. Conferir o produto escolhido (Checkout Pro não é API de assinaturas). Depois preparar verificação da conta de teste, endpoint isolado de retornos e bloqueio de valores/modo real antes de liberar pedidos externos.

Faltam: autenticação de webhooks e consulta autoritativa com checagem de modo de teste, idempotência durável do envio e dos retornos, conciliação de resultados incertos, recorrência e cancelamento. Um HTTP de criação de preferência não é pagamento; um retorno do navegador não quita fatura. Não usar dados de clientes nem cartão real em homologação.

Referências consultadas: https://www.mercadopago.com.br/developers/pt/docs/checkout-pro-preferences/test-accounts e https://www.mercadopago.com.br/developers/pt/docs/checkout-pro-preferences/integration-test/test-purchases . O teste deve usar conta compradora distinta da vendedora. A preferência deve seguir o fluxo atual de `init_point`; não pressupor que prefixo de token ou nome sandbox isole transações.
