# Pessoas: letras, layout e CEP · Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Levar o formulário de pessoa e a ficha da pessoa ao padrão visual novo e tirar a frase sobre o ViaCEP.

**Architecture:** Só o visual muda. Um CSS próprio (`people-form.css`, com o prefixo de classe `pf-`) substitui as regras globais de `.member-modal` e `.step-content`, que usam letras de 7 a 9px. Campos, salvamento e preenchimento automático do CEP continuam iguais.

**Tech Stack:** React (vinext), CSS, Playwright para capturas, testes `node --test`.

**Spec:** aprovado na conversa de 12/11/2026 (itens 1 e 2 da análise de Pessoas).

## Global Constraints
- Letras: 14px nos campos e textos, 13px nos rótulos, títulos sem serifa (fonte da página), 22px no título do formulário.
- Campos com altura mínima de 42px, botões com 40px.
- Cores: `var(--tenant,#285c45)`; textos `#183e31`; texto secundário `#5f6f64`.
- No celular (≤640px), o formulário ocupa a tela inteira e as etapas mostram o nome.
- Nenhuma frase cita o serviço de CEP.

## Review Focus
1. **Nomes de igreja longos e textos grandes** nos campos não podem estourar a largura no celular (390px). O teste de captura confere que a página não ganha rolagem horizontal.
2. **CEP não encontrado ou sem conexão:** o formulário continua permitindo digitar o endereço à mão, e a mensagem não cita o serviço.
3. **Trocar de etapa sem perder o que foi digitado** continua funcionando depois da mudança de classes. A captura percorre as quatro etapas.
4. **A ficha da pessoa com campos vazios** mostra "Não informado" sem quebrar a grade.
5. **Outras telas que usam `.modal`** (Kids, Termos) não podem mudar: as regras novas valem só dentro de `.pf`.

---

### Task 1: Tirar a frase do ViaCEP

**Files:**
- Modify: `app/DashboardApp.tsx` (step 2 do `PersonModal`, o texto `'Consulta automática pelo ViaCEP ao completar o CEP.'`)
- Modify: `app/RegistrationFields.tsx` (linhas 7 e 8: mensagens `'Consultando CEP no ViaCEP…'` e `'Consulta automática pelo ViaCEP ao completar o CEP.'`)
- Test: `scripts/postal-copy.test.mjs`

**Interfaces:**
- Produces: mensagens finais `''` (antes de completar o CEP), `'Buscando endereço…'`, `'Endereço encontrado. Confira e informe o número.'` e `'Não encontramos este CEP. Preencha o endereço.'`

- [ ] **Step 1: Write the failing test**

```js
test('nenhuma tela cita o serviço de CEP', () => {
  for (const f of ['app/DashboardApp.tsx', 'app/RegistrationFields.tsx']) {
    assert.doesNotMatch(readFileSync(f, 'utf8'), /ViaCEP/i);
  }
});
```
- [ ] **Step 2: Run** `node --experimental-strip-types --test scripts/postal-copy.test.mjs`. Expected: FAIL.
- [ ] **Step 3: Implement.** Troque as mensagens pelas da seção Interfaces. Em `DashboardApp.tsx`, use `{registration.postalNotice&&<p role="status">…</p>}`, sem texto padrão.
- [ ] **Step 4: Run** o teste. Expected: PASS. Rode também `node --experimental-strip-types --test scripts/brazil-registration.test.mjs` (já existente). Expected: PASS.
- [ ] **Step 5: Commit** com a mensagem `Pessoas: CEP sem citar o serviço de consulta`.

### Task 2: Formulário de pessoa no padrão novo

**Files:**
- Create: `app/people-form.css`
- Modify: `app/DashboardApp.tsx`, função `PersonModal`: adicionar a classe `pf` ao `<form>` e importar o CSS
- Test: captura `scratchpad/pf.cjs` (fora do repositório) e `scripts/people-form-style.test.mjs`

**Interfaces:**
- Produces: classes `.pf`, `.pf .stepper`, `.pf .step-content`, `.pf .modal-head`, `.pf .modal-actions`. As regras novas sobrescrevem as globais só dentro de `.pf`.

- [ ] **Step 1: Write the failing test**

```js
test('formulário de pessoa usa letras legíveis', () => {
  const css = readFileSync('app/people-form.css', 'utf8');
  for (const m of css.matchAll(/font-size:(\d+)px/g)) assert.ok(Number(m[1]) >= 12, m[0]);
  assert.match(readFileSync('app/DashboardApp.tsx', 'utf8'), /className="modal member-modal pf"/);
});
```
- [ ] **Step 2: Run** `node --experimental-strip-types --test scripts/people-form-style.test.mjs`. Expected: FAIL (o arquivo não existe).
- [ ] **Step 3: Implement** `app/people-form.css` com os valores de Global Constraints:
  - etapas com número e nome (o nome aparece também no celular, abaixo do número, com 12px);
  - rótulos em grade de 1 coluna, com `form-row` virando 2 colunas a partir de 640px;
  - `@media(max-width:640px)`: `.pf{width:100%;height:100%;border-radius:0}` e `.pf .step-content{max-height:none;flex:1}`.
- [ ] **Step 4: Run** o teste. Expected: PASS. Rode a captura das 4 etapas em 1440 e 390px. Expected: sem rolagem horizontal e textos legíveis.
- [ ] **Step 5: Commit** com a mensagem `Pessoas: formulário de cadastro no padrão novo`.

### Task 3: Ficha da pessoa no padrão novo

**Files:**
- Modify: `app/DashboardApp.tsx`, função `PersonProfile`: adicionar a classe `pp` ao `<aside>`
- Modify: `app/people-form.css` (regras `.pp`)
- Test: `scripts/people-form-style.test.mjs` (novo caso) e a captura

**Interfaces:**
- Consumes: `app/people-form.css` (Task 2).

- [ ] **Step 1: Write the failing test** `ficha da pessoa usa o padrão`: confirma que `className="person-profile pp"` existe em `DashboardApp.tsx` e que `.pp h2` tem `font-size:22px`.
- [ ] **Step 2: Run** o teste. Expected: FAIL.
- [ ] **Step 3: Implement.** Cabeçalho com iniciais, nome em 22px e etapa; seções em cartões com títulos de 15px sem serifa; grade de 2 colunas que vira 1 no celular.
- [ ] **Step 4: Run** o teste e a captura (computador e celular, inclusive com campos vazios). Expected: PASS, e "Não informado" alinhado.
- [ ] **Step 5: Commit** com a mensagem `Pessoas: ficha da pessoa no padrão novo`.
