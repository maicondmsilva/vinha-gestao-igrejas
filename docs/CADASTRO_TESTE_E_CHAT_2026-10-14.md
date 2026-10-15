# Cadastro de teste e atendimento Vinha

## Fluxo do responsável

1. Os botões de demonstração no site direcionam a `https://app.vinhaigrejas.com.br/cadastro`.
2. O responsável informa nome, e-mail, senha, telefone, ministério, sede, pastor titular, cidade, UF e quantidade estimada de unidades. Não há cartão nem aceite de publicidade obrigatório.
3. O responsável confirma seu e-mail no Supabase. Um cadastro pendente de confirmação não libera o ministério. A confirmação não foi desativada para encurtar o fluxo.
4. Após autenticar e aceitar as condições, uma operação transacional cria organização, proprietário, sede, plano inicial com 30 dias de teste, progresso de configuração concluído e registro comercial com a versão do aceite. As demais unidades são uma estimativa e não são criadas automaticamente com dados fictícios.
5. Repetir a submissão retoma o ministério já provisionado, sem renovar o prazo nem criar outro. Contas que já participam de outro ministério são orientadas a entrar no acesso existente.
6. O aplicativo nas lojas e as integrações externas não são publicados nem ativados automaticamente durante o teste.

## Acompanhamento na Central

- Organizações mostra responsável e origem do cadastro pelo site, sem fingir que existe convite pendente. O e-mail de uma conta já autenticada não é trocado por edição de convite.
- Demonstrações apresenta contato, localização, estimativa de unidades, prazo e configuração. A ficha do ministério pode ser aberta a partir da lista.
- A regra `trial_ending` existente define a antecedência do alerta; a Central calcula prazos ao consultar os dados e atualiza o indicador a cada minuto com a página aberta. Não depende de cron para exibir o alerta interno.
- Testes terminando e vencidos recebem indicação separada. A continuidade é acompanhada pelos operadores; esta entrega não acrescenta cobrança automática ou cancelamento de dados.
- A rotina de automações existente continua disponível. Envios externos por e-mail, push ou WhatsApp dependem das credenciais e da configuração dos canais e do agendador da Vercel.

## Chat comercial e suporte

- Widget disponível no site público e nas telas de usuários. É independente do chat entre membros da igreja, cujas rotas foram preservadas.
- Visitantes informam nome, e-mail, mensagem e aceite de uso dos dados para o atendimento. O e-mail de visitante é identificado como não verificado.
- Uma chave aleatória de 256 bits fica em cookie HttpOnly, Secure em HTTPS e SameSite=Lax. O banco armazena apenas seu hash. A chave não é exposta em URLs ou no histórico da conversa.
- Para clientes autenticados a conversa pertence à conta; uma conta diferente é recusada mesmo conhecendo o identificador. O ministério é validado pela associação ativa, não por dados editáveis do perfil.
- A equipe com MFA vê a fila, não lidas, dados do contato, histórico e responsável. Operadores owner/admin/support respondem e encerram/reabrem atendimentos. Consulta não permite resposta.
- Atualização por consulta a cada 5 segundos enquanto a página está ativa. Não é WebSocket, notificação push nem promessa de atendimento 24 horas. O indicador global da Central consulta não lidas a cada 20 segundos.
- O visitante retoma a conversa pelo mesmo navegador por até 30 dias. Apagar cookies ou trocar de navegador pode exigir nova conversa. Não existe exclusão automática de histórico nesta entrega.
- Controles iniciais contra abuso: origem em escritas HTTP, campo-isca, tamanhos máximos, limite global de 100 novas conversas por hora, até 3 abertas por conta, 12 mensagens por minuto por conversa e limite de 500 mensagens. Para tráfego público em escala, complementar com WAF/CAPTCHA e monitoramento. Nenhuma tabela de chat tem acesso direto anônimo.
- A função pública do chat é deliberadamente uma interface restrita para visitantes: a implementação privada valida posse, vínculo, limites e expiração. Não foi concedido acesso anônimo ao esquema privado. O aviso do Advisor sobre essa função pública deve ser avaliado nesse contexto, não removendo a validação ou abrindo as tabelas.

## Configuração e verificação

No Supabase Auth, autorizar a URL de retorno `https://app.vinhaigrejas.com.br/cadastro` e configurar SMTP para entrega confiável de confirmação. Nunca inserir SMTP, chaves privilegiadas ou senhas em variáveis `NEXT_PUBLIC_*`. A entrega real de e-mail e sua chegada à caixa postal não foram testadas nesta execução.

O documento de condições de teste é um texto operacional inicial; a revisão jurídica final deve ser feita antes da expansão comercial.

Verificações: build Vercel, verificação direcionada dos arquivos novos/alterados, controles interativos e `supabase/tests/trial_and_support_chat_transaction.sql` com resultado `passed` e rollback. Testados provisionamento, prazo de 30 dias, repetição, isolamento entre contas, chave incorreta, bloqueio de leitura direta anônima e resposta da equipe. Sem contas Auth novas, e-mails ou cobranças reais criados por estes testes. Não houve validação visual autenticada no navegador.
