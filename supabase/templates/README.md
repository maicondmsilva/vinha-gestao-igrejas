# E-mails de autenticação Vinha

Status em 18/10/2026: os 13 modelos do manifesto foram aplicados pelo painel ao projeto Vinha Produção (`aoxibaaydfgffrdqtkva`). O HTML foi conferido após reabrir cada modelo, comparando a prévia persistida com o arquivo local (desconsiderando apenas o estilo inserido pelo editor e espaços). Assuntos foram preenchidos pelo manifesto; alguns aparecem protegidos na leitura automatizada. Os sete avisos de segurança continuam desativados, preservando o estado anterior.

SMTP Hostinger configurado e salvo pelo usuário, remetente `Vinha <notificacoes@vinhaigrejas.com.br>`. O usuário confirmou recebimento na caixa de entrada do primeiro teste, ainda com o antigo modelo inglês. Após aplicar a identidade, o usuário confirmou em 18/10/2026 que a nova recuperação chegou bem formatada. Não houve alteração de senha nem consumo de link de recuperação por este agente. Isso valida recebimento e aparência relatados pelo destinatário, não o retorno completo da redefinição.

Evidência da prévia: `docs/evidencias/email-recuperacao-vinha-2026-10-18.png`. A prévia do painel não substitui conferência em Gmail/mobile. Não foram certificadas entrega de confirmação inicial, convite, OTP ou notificações desativadas. SPF/DKIM/DMARC e retorno completo ao cadastro permanecem sem nova validação nesta rodada.

## Conteúdo

`manifest.json` relaciona os 13 assuntos e arquivos HTML: confirmação, convite, link de acesso, recuperação, mudança de e-mail, reautenticação e sete avisos de segurança. A identidade usa o monograma e nome Vinha, verde institucional e destaque dourado, sem dependência de imagens externas. O remetente e o domínio de envio não são definidos apenas pelo HTML.

Os links preservam `{{ .ConfirmationURL }}` para não quebrar tokens ou os destinos de cadastro, recuperação e convites. `{{ .Token }}` aparece nos modelos aplicáveis. Não substituir esses valores por links fixos, nem habilitar rastreamento de cliques do provedor SMTP.

## Alteração já realizada no projeto Vinha Produção

- Site URL: `https://app.vinhaigrejas.com.br` (antes: `http://localhost:3000`).
- Retornos autorizados: `https://app.vinhaigrejas.com.br/**`, `https://central.vinhaigrejas.com.br/**`, `https://vinhaigrejas.com.br/**`.
- Nenhum domínio de terceiros ou domínio de homologação foi autorizado. A confirmação de e-mail não foi desativada.

## Procedimento de configuração e validações restantes

1. Escolher e verificar um remetente no domínio `vinhaigrejas.com.br` e um provedor SMTP. O endereço deve existir/estar validado; não assumir que uma caixa foi criada apenas por registrar o domínio.
2. Configurar SMTP no Supabase Authentication → Emails → SMTP Settings. Credenciais são inseridas pelo responsável no painel; nunca enviar senha pelo chat nem guardar no GitHub ou em variáveis `NEXT_PUBLIC_*`.
3. Configurar os registros de autenticação do domínio conforme o provedor (SPF/DKIM e política DMARC), preservando os registros existentes de e-mail. Não ativar SMTP incompleto, pois isso pode interromper os envios.
4. Copiar os assuntos e HTML de `manifest.json` para os tipos correspondentes em Emails → Templates. Não ligar/desligar avisos de segurança automaticamente só por mudar o modelo.
5. Fazer o teste real quando o usuário informar um destinatário e realizar a criação da senha/aceite. Verificar chegada, spam, nome/remetente, conteúdo Vinha, clique de uso único, retorno ao cadastro, conta confirmada e criação de um único ministério com 30 dias de teste.
6. Testar separadamente recuperação de senha e convite com uma conta autorizada, sem mexer nas credenciais de usuários existentes.

Não executar `supabase config push` usando o `config.toml` local para aplicar estes modelos em produção: ele contém padrões de desenvolvimento de autenticação e MFA que não devem sobrescrever as configurações remotas.

Referências: [modelos de e-mail](https://supabase.com/docs/guides/auth/auth-email-templates), [SMTP próprio](https://supabase.com/docs/guides/auth/auth-smtp).
