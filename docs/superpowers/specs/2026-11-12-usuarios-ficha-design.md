# Usuários: ficha completa, criação sem convite e cadastro pelo aplicativo

Data: 12/11/2026 · Situação: aguardando revisão do dono do produto.

## 1. Objetivo

Unificar "usuário" (quem tem login) e "membro" (cadastro em Pessoas) num fluxo único:

- A pessoa tem **um único login** (e-mail e senha), que vale para o **aplicativo** e para o **painel**.
- Ao clicar em um usuário, ou ao criar um, abre uma **ficha completa** que edita o **mesmo cadastro do membro**. Os dados não são guardados em dois lugares.
- O **convite por e-mail sai**. A gestão cria, edita e exclui usuários diretamente.
- O cadastro feito no aplicativo dá **acesso imediato** e abre uma **solicitação de membro** para análise. Na reprovação, a pessoa recebe **e-mail e alerta no aplicativo** com o que precisa ajustar.

Referência visual: as telas da InChurch serviram só para entender o fluxo. Nomes, layout e organização seguem a identidade do Vinha (painel lateral, blocos em cartões, vocabulário do sistema), para não caracterizar cópia.

## 2. Situação atual (código lido em 12/11/2026)

| Peça | Hoje |
|---|---|
| Lista de usuários | `StaffDirectory.tsx` mostra os vínculos com a organização: papel, situação, igrejas de acesso e permissões (aba). |
| Criar usuário | Só por **convite**: `staff_invitations`, `create_staff_invitation`, link `/convite/{token}`. |
| Excluir | Não existe. Só dá para suspender. |
| Cadastro pelo app | `member_self_service` cria a conta e um vínculo **pendente** e envia a solicitação para Perfis pendentes. A aprovação ativa o vínculo e liga a pessoa ao membro. |
| Reprovação | Fica registrada (`member_profile_requests.status='rejected'`), mas a pessoa **não é avisada**. |
| Senha no painel | Não existe. A troca é feita pela própria pessoa em `/conta/nova-senha`. |
| Peças reaproveitáveis | Chave administrativa do Supabase no servidor (`supabaseAdminClient`); e-mail SMTP `notificacoes@vinhaigrejas.com.br` (`event-email.ts`); caixa de avisos do aplicativo (`member_inbox_*`). |

## 3. Regras de negócio

### 3.1 Login e senha
1. Um login por pessoa, o mesmo no aplicativo e no painel.
2. **Conta criada no aplicativo:** a senha é a que a pessoa escolheu. Se ela ganhar permissões, entra no painel com os mesmos dados.
3. **Usuário criado no painel (pessoa sem aplicativo):** a gestão **digita a senha** e a repassa para a pessoa. No **primeiro acesso, a troca de senha é obrigatória**. Não há botão de senha aleatória.
4. **Editar usuário que já tem conta:** o campo Senha fica **em branco**; em branco, a senha atual continua. Se a gestão digitar uma nova, ela vale e a troca no próximo acesso volta a ser obrigatória.
5. Senha com no mínimo 8 caracteres. Nunca é mostrada depois de salva nem registrada na auditoria.

### 3.2 Novo usuário (painel)
1. O botão **Novo usuário** primeiro **busca a pessoa em Pessoas** (nome, e-mail ou CPF):
   - **Pessoa encontrada sem login:** a ficha abre com os dados dela. A gestão completa e-mail e senha, e a conta é criada e ligada a esse membro.
   - **Pessoa encontrada que já tem login:** a ficha abre para dar acesso nesta igreja. A senha fica em branco e continua a dela.
   - **Não encontrada:** ficha em branco. Ao salvar, cria o **membro** e a **conta** juntos, já ligados.
2. Se o e-mail digitado já pertence a um login de outra pessoa, a gravação é recusada com uma mensagem clara (sem expor dados dessa outra pessoa).
3. Quem pode: dono, administrador e pastor (como hoje) ou quem recebeu **Configurações › Usuários e permissões**. Ninguém concede um tipo maior que o próprio.

### 3.3 Ficha do usuário
Painel lateral com quatro blocos e uma aba de permissões:

| Bloco | Campos | Onde grava |
|---|---|---|
| Conta | Nome, igreja principal, tipo de usuário (papel), celular, e-mail, senha | Nome, celular e e-mail no **membro** (`people`). Papel e igreja no vínculo (`organization_memberships`). E-mail e senha no login (Supabase Auth). |
| Endereço | CEP, rua, número, complemento, bairro, cidade, UF | `person_addresses` |
| Informações adicionais | Sexo, CPF, nascimento, data de casamento, data de batismo, é pastor | `people` |
| Grupos | Células, equipes de escala e turmas Kids de que a pessoa participa | Tabelas de cada módulo (só exibição e atalho nesta etapa) |
| Permissões | A matriz atual (`UserPermissions`) | `permission_grants` |

- Alterar o e-mail na ficha muda também o e-mail de login. O login exige que o novo e-mail não esteja em uso.
- Data de casamento e "é pastor" não existem hoje em `people` e serão acrescentados.

### 3.4 Excluir usuário
- **Excluir = tirar o acesso** a esta organização: o vínculo é removido. A **conta de login** e o **cadastro de membro** continuam, e o histórico fica preservado.
- O **dono** não pode ser excluído. Ninguém exclui a si mesmo. Administrador só é excluído pelo dono.
- As permissões avulsas da pessoa nesta organização são removidas junto.

### 3.5 Convites
- A tela de convite sai. Os convites pendentes são **cancelados** na migração.
- A rota `/convite/{token}` passa a responder "convite encerrado; peça acesso à sua igreja".

### 3.6 Cadastro pelo aplicativo
1. O cadastro no app cria o login e um vínculo **ativo** como usuário do aplicativo (papel `member`). A pessoa usa o app na hora, sem aprovação, e já aparece na lista de Usuários.
2. O cadastro também abre uma **solicitação de membro** em Pessoas › Perfis pendentes (já existe).
   - **Aprovada, sem membro existente:** cria o membro ligado ao usuário (já existe).
   - **Aprovada, com membro existente:** os campos aprovados atualizam o cadastro existente e a ligação é feita (já existe, com candidatos por e-mail/CPF).
3. Atualizações de perfil feitas pelo app seguem a mesma análise (já existe).

### 3.7 Reprovação com aviso
1. Ao reprovar (no todo ou em parte), quem analisa escreve o **motivo** e marca os campos que precisam de ajuste.
2. A pessoa recebe:
   - **alerta no aplicativo** (caixa de avisos) com a lista do que foi reprovado e o motivo;
   - **e-mail** pelo endereço de notificações, com o mesmo conteúdo e um link para abrir o app e corrigir.
3. Ao corrigir e reenviar, uma nova solicitação entra na fila.
4. Se o e-mail não puder ser enviado, o alerta no app vale sozinho, e a falha fica registrada para nova tentativa.

## 4. Desenho técnico

### 4.1 Banco (migração `usuarios_ficha`)
- `people`: novas colunas `marriage_date date` e `is_pastor boolean default false`.
- `organization_memberships`: nova coluna `password_change_required boolean default false`.
- `private.staff_user(p_org, p_action, p_data)`, com as ações:
  - `get`: ficha completa (vínculo, membro, endereço, grupos);
  - `save`: grava membro, endereço e vínculo, com versão para não sobrescrever alterações de outra pessoa;
  - `remove`: remove o vínculo e as permissões avulsas;
  - `search`: busca pessoas para "Novo usuário".

  As regras ficam no banco (quem pode, dono protegido, sem conceder acima do próprio papel), e tudo gera auditoria.
- `member_self_service`: o vínculo criado no cadastro passa a nascer **ativo**.
- Reprovação: `member_profile_review2` passa a gravar o aviso na caixa do app (`member_inbox`) e um item numa fila de e-mail (`private.member_review_emails`).
- Convites pendentes passam para `revoked`.

### 4.2 Servidor (rotas do painel)
- `POST /api/users`: cria usuário. A rota valida e chama `staff_user('save')`. Quando é preciso criar ou alterar o login, ela usa a **chave administrativa** (`auth.admin.createUser` / `updateUserById`), **só depois** que o banco confirma a permissão. Se o login falhar, desfaz o vínculo criado.
- `PATCH /api/users`: edita a ficha (e, quando informados, o e-mail e a senha do login).
- `DELETE /api/users`: remove o acesso.
- Primeiro acesso: no login, se `password_change_required` estiver ativo, a pessoa é levada para `/conta/nova-senha`. Ao trocar a senha, a marca é apagada.
- E-mail de reprovação: processado pela mesma rotina de envio de Eventos (`event-email.ts`), com novas tentativas.

### 4.3 Telas
- `StaffDirectory.tsx`: o clique abre a **ficha** (novo componente `UserSheet.tsx`); o botão "Novo usuário" abre a busca; saem o formulário e a lista de convites.
- `UserSheet.tsx`: blocos Conta, Endereço, Informações adicionais e Grupos, mais a aba Permissões. Ações: Salvar, Excluir (tirar acesso) e Voltar. No celular, a ficha ocupa a tela inteira.
- Aplicativo: o alerta de reprovação aparece na caixa de avisos com o botão "Corrigir meu cadastro".

## 5. Testes
- **Banco (pgTAP):**
  - criar usuário (pessoa nova, pessoa existente sem login, pessoa com login);
  - editar com versão;
  - excluir (dono protegido, não excluir a si mesmo, administrador só pelo dono);
  - ninguém concede papel maior que o próprio;
  - cadastro pelo app nasce ativo;
  - reprovação gera o aviso e o item de e-mail;
  - convites pendentes cancelados.
- **Rotas (unidade):** validação, criação do login só após a permissão confirmada, desfazer em caso de falha, senha nunca devolvida.
- **Telas:** ficha no computador e no celular; fluxo de Novo usuário; troca obrigatória de senha no primeiro acesso.
- **Teste de ponta a ponta no ambiente de teste:** criar usuário, entrar, trocar a senha, reprovar uma solicitação e conferir o e-mail.

## 6. Fora do escopo desta etapa
- Editar a participação em grupos dentro da ficha (nesta etapa só exibe; a edição continua nos módulos).
- Aplicativo móvel nativo: o alerta usa a caixa de avisos que o app já lê.
