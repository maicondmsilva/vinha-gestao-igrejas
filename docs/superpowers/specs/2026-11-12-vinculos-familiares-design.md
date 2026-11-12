# Vínculos familiares

Data: 12/11/2026 · Desenho aprovado pelo dono do produto na conversa de 12/11/2026.

## 1. Objetivo
Ligar pessoas do cadastro por parentesco, mostrar a família na ficha da pessoa, sugerir responsáveis no Kids e permitir que o membro peça pelo aplicativo a inclusão de um familiar.

## 2. Situação atual
- Existem só os **responsáveis das crianças do Kids** (`private.kids_guardians`) e os **pedidos de família do app** para Kids e células (`private.member_family_requests`, tipos `kids` e `cells`).
- Não há ligação entre pessoas. O formulário de Pessoas mostra "Vínculos familiares serão disponibilizados em um próximo bloco".
- A página "Famílias e termos" usa a base antiga (`/api/children`, `/api/terms`) e está desativada. Ela fica fora desta etapa.

## 3. Regras
1. **Parentescos**: cônjuge, pai/mãe, filho(a), irmão(ã), avô/avó, neto(a), tio(a), sobrinho(a), padrasto/madrasta, enteado(a), responsável legal, outro.
2. **Vínculo inverso automático**, guardado nos dois sentidos para que a consulta seja simples:

   | Ida | Volta |
   |---|---|
   | pai/mãe | filho(a) |
   | avô/avó | neto(a) |
   | tio(a) | sobrinho(a) |
   | padrasto/madrasta | enteado(a) |
   | responsável legal | tutelado(a) |
   | cônjuge, irmão(ã), outro | o mesmo |
3. Uma pessoa não se liga a si mesma. Um par de pessoas tem um só vínculo; para trocar o parentesco, edita-se o vínculo existente.
4. **Mora junto** (sim ou não): marcado no vínculo. Ao ligar e marcar "mora junto", o endereço da pessoa principal pode ser copiado para o familiar (opção na tela). O **núcleo familiar** é o conjunto de pessoas ligadas com "mora junto".
5. **Cônjuge**: o vínculo guarda a **data de casamento**, que alimenta o aniversário de casamento. Ao salvar, ela é copiada para `people.marriage_date` dos dois cônjuges (coluna criada na etapa Usuários; se esta etapa vier antes, a coluna é criada aqui).
6. **Cadastro rápido de familiar**: nome, data de nascimento e etapa (Membro, Em integração ou Visitante). Útil para filhos pequenos. Cria a pessoa na mesma igreja da pessoa principal.
7. **Permissões**:
   - ver os vínculos = poder ver as duas pessoas (`private.person_record_view`);
   - criar, editar ou remover vínculo = poder editar as duas pessoas (`private.person_record_manage`);
   - cadastro rápido = poder criar pessoa (regra atual de inclusão em `people`).
8. **Auditoria** de inclusão, alteração e remoção de vínculo.
9. **Kids**: ao cadastrar uma criança, as pessoas ligadas como pai/mãe, avô/avó ou responsável legal aparecem como **sugestão** de responsável. A autorização de retirada continua sendo uma aprovação do Kids.
10. **Aplicativo**:
    - o membro vê a própria família, só nome e parentesco;
    - o membro pode pedir a inclusão de um familiar (nome, nascimento, parentesco, mora junto); o pedido entra em `member_family_requests` com o tipo novo `relative`;
    - o pedido é analisado em Pessoas › Perfis pendentes, numa seção "Familiares". Aprovado: cria a pessoa (ou liga a uma existente escolhida por quem analisa) e o vínculo.

## 4. Desenho técnico
- **Tabela** `private.person_relationships`, com as colunas:
  - `id`, `organization_id`, `person_id`, `related_person_id`, `relation text`;
  - `same_household boolean default false`, `marriage_date date null`;
  - `created_by`, `created_at`, `updated_at`, `version`.

  Restrições:
  - `unique(person_id, related_person_id)`;
  - `check(person_id <> related_person_id)`;
  - `relation` restrito à lista da regra 1, mais `tutelado`.

  RLS ativo, sem acesso direto do cliente.
- **Função** `private.person_family(p_org, p_action, p_data)` com as ações:
  - `list`: os vínculos de uma pessoa, com nome, idade, etapa, igreja e mora junto;
  - `set`: cria ou edita, mantendo o par inverso;
  - `remove`: apaga os dois sentidos;
  - `quick_create`: cadastra o familiar e já cria o vínculo;
  - `suggest_guardians`: lista para o Kids.

  Expõe também a fachada `public.person_family`.
- **Rota** `/api/people/family` (GET para listar, POST para as demais ações).
- **Telas**:
  - formulário de Pessoas, etapa "Família e endereço": bloco "Família" no lugar do aviso;
  - ficha da pessoa (`PersonProfile`): seção "Família";
  - aplicativo (`MemberFamilyPortal.tsx`): seção "Minha família" e o pedido de inclusão.

## 5. Testes
- **Banco (pgTAP)**:
  - inverso automático em cada parentesco;
  - par único;
  - não ligar a si mesmo;
  - remover apaga os dois sentidos;
  - permissões: ver exige ver as duas pessoas, editar exige editar as duas;
  - cadastro rápido;
  - data de casamento nos dois cônjuges;
  - sugestão de responsáveis;
  - pedido `relative` aprovado cria pessoa e vínculo.
- **Rota (unidade)**: validação dos campos e do parentesco.
- **Telas**: computador e celular.
