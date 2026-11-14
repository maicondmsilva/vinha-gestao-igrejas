# Kids no telão (Holyrics), número da etiqueta e rascunho do perfil na plataforma

## Por quê
- **Telão:** quando a sala Kids chama um responsável, o aviso no app só chega com o app aberto (o push com Firebase ainda não está ativo). Mostrar no telão do culto garante que a família veja.
- **Número da etiqueta:** o nome de uma criança não deve aparecer no telão nem na transmissão ao vivo. O telão mostra só um número curto.
- **Rascunho:** quem começa o perfil num aparelho perde o que digitou ao trocar de celular ou reinstalar o app.

## Decisões do responsável pelo projeto
- **Telão:** mostra o número da etiqueta: "Kids: responsável pela criança nº 27, compareça à Sala Azul". O número também aparece no app do responsável.
- **Envio ao Holyrics:** pela internet (`api.holyrics.com.br`), a partir da plataforma Vinha. Foi escolhido em vez da rede local da igreja.
- **Rascunho:** fica salvo na plataforma. Só aparece para a secretaria quando a pessoa toca em **Enviar**.

## Abordagens consideradas para o Holyrics
1. **Pela internet, a partir da plataforma (escolhida):** a igreja configura a chave e o token uma vez e funciona de qualquer rede. Exige internet no computador do Holyrics.
2. **Pela rede local, do Vinha Equipe:** funciona sem internet, mas exige mesmo Wi-Fi, IP fixo, liberação de HTTP sem TLS no Android e configuração em cada aparelho.
3. **As duas, com a local como reserva:** fica para depois, se a internet da igreja se mostrar instável.

## Design
### Número da etiqueta
- Coluna `tag_number` em `private.kids_attendance`.
- É sequencial por encontro, começando em 1, e atribuído na entrada. Um trava por encontro e um índice único por encontro evitam números repetidos.
- **Onde aparece:**
  - no quadro da sala do Vinha Equipe;
  - na lista de chamados;
  - no app do responsável, como "Etiqueta nº 27 · Sala Azul" enquanto a criança está presente, por meio da função `member_kids_present`.
- A impressão em etiqueta fica para depois.

### Telão
- **Configuração:** tabela `private.kids_projectors`, uma por igreja local, com ligado ou desligado.
  - A chave da API e o token ficam no **Vault** do Supabase.
  - Nunca voltam para o app nem para o painel. A tela só mostra que estão "configurados".
- **Funções:**
  - `kids_projector(org, unit, get|save|test)`, para coordenação Kids e administração (`kids_op_allowed configure` ou dono, admin ou pastor);
  - `kids_call` ganha o campo `projector`, que vem ligado por padrão, e grava `projector_sent`.
- **Envio:** um gatilho em `kids_guardian_calls` chama `net.http_post` (pg_net):
  - **Ao chamar:** `POST https://api.holyrics.com.br/send/SetAlert`, com os cabeçalhos `api_key` e `token`. O corpo é `{"text":"Kids: responsável pela criança nº N, compareça à <sala>","show":true,"close_after_seconds":60}`.
  - **Quando o responsável responde:** `SetAlert` com `{"text":"","show":false}`.
- **Sem pg_net (banco local de teste):** só registra. Cada envio fica em `private.kids_projector_log` (igreja, chamado, ação e id da requisição) para auditoria.
- **Teste:** "Testar telão" manda "Teste do telão Kids pela Vinha" por 10 s.
- **Painel:** em **Kids › Telão (Holyrics)**, com ligar ou desligar, chave, token, testar e as instruções de como criar o token no Holyrics liberando só o `SetAlert`.
- **Vinha Equipe:** mostra o número da etiqueta e a opção "Mostrar no telão", já marcada quando a igreja tem telão configurado.

### Rascunho do perfil
- Tabela `private.member_profile_drafts` (conta e organização, dados em jsonb e data de atualização).
- Só a própria conta lê e grava, pela função `member_profile_draft(org, get|save|clear)`.
- O rascunho não entra na fila de revisão. Ao enviar (`member_self_service submit`), ele é apagado.
- Rascunhos com mais de 30 dias são apagados quando a pessoa lê ou salva.
- **No app:** salva 1,5 s depois que a pessoa para de digitar. O aparelho guarda só uma cópia de segurança enquanto não há conexão, e ela é apagada depois que o envio dá certo.
- **Ordem de preenchimento ao abrir:** primeiro o rascunho, depois o último pedido enviado e, por fim, o cadastro aprovado.

## Fora do escopo
- Impressão de etiqueta.
- Envio pela rede local.
- Push com Firebase.
- Outras ações do Holyrics.

## Decisões deixadas ao construtor
- A sala no texto é o nome da sala física do encontro.
- O texto "compareça à" é fixo.
- O teste do telão dura 10 s.
