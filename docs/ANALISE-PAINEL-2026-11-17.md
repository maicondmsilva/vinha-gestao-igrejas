# Painel da Vinha — Kids operante, Configurações, CEP, Células em cartões e barra lateral

Data: 17/11/2026 · Escopo: painel, Vinha Equipe e banco. Análise feita em duas passadas: primeiro o levantamento de cada pedido, depois a revisão de impacto em cada módulo que usa as mesmas funções.

## 1. Kids — salas e turmas não salvavam (corrigido)

**Causa:** o Vinha Equipe chamava a função do banco `kids_operations_save` com o parâmetro `p_org`, mas a função usa `p_organization`. O servidor não encontrava a função e a tela mostrava só "não foi possível". O mesmo erro existia em `kids_admission_choices`.

**Telas afetadas no Vinha Equipe:** Configurar Kids (salas, turmas e sessões), entrada e saída por QR, recepção manual (entrada e retirada), busca de criança na recepção e o totem.

**Painel:** não era afetado (usa a rota `/api/kids-operations`). Conferido em produção: criar sala e turma pela função funciona.

**Correção e prevenção:**

- As 6 chamadas foram corrigidas.
- Novo teste `scripts/rpc-contract.test.mjs`: lê a definição de cada função nas migrações e confere **todas** as chamadas `.rpc()` do painel, do app da igreja e do Vinha Equipe (mais de 100). Sem esse teste o erro passou despercebido; agora o CI barra.
- Painel › Configurar › Sessões: quando faltam salas ou turmas, aparece o aviso com o botão **Cadastrar salas e turmas**.
- É preciso **instalar o novo APK do Vinha Equipe**.

## 2. Configurações › Serviços e segurança (removido)

| Bloco                                                                   | Uso real                                                                                                          | Destino                                                                                                                                                                                         |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mídia e abertura do aplicativo                                          | Usado pelo app (abertura e biblioteca de mídia)                                                                   | **Comunicação › Abertura e mídia do app**                                                                                                                                                       |
| Contribuições e carteirinhas                                            | Finalidades: usadas no Contribua; carteirinhas: usadas no app; preço de ingresso: duplicado (já existe no evento) | **Financeiro › Contribua** (finalidades) · **Pessoas › Carteirinhas** · preço do ingresso removido daqui (fica no evento, em Programação)                                                       |
| Agenda e eventos                                                        | Só um link para Programação                                                                                       | Removido                                                                                                                                                                                        |
| Comunidade do aplicativo                                                | Usado pelo app (ministérios e pedidos)                                                                            | **Comunicação › Comunidade do app**                                                                                                                                                             |
| Jornadas e planos de leitura                                            | Usado pelo app                                                                                                    | **Comunicação › Jornadas e leitura**                                                                                                                                                            |
| Kids e Grupos Vida no app                                               | Parte Kids já estava em Kids › Crianças; parte de grupos só existia aqui                                          | **Células › Pendências e avisos › Grupos no aplicativo**                                                                                                                                        |
| Links (portal do membro, contrato, recebedoras, segurança, atendimento) | Atalhos                                                                                                           | Portal, contrato e segurança em **Configurações › Identidade › Atalhos**; "Segurança da conta" também no topo da barra lateral; contas recebedoras já estão no Financeiro; atendimento é o chat |

Nenhuma função do banco foi apagada; só a tela mudou de lugar. As permissões continuam as mesmas (cada bloco confere a própria permissão no servidor).

## 3. CEP automático

| Cadastro                                        | Situação                                                                      |
| ----------------------------------------------- | ----------------------------------------------------------------------------- |
| Pessoas (painel) e portal de cadastro do membro | Já buscava pelo CEP                                                           |
| App da igreja (cadastro do membro)              | Já buscava pelo CEP                                                           |
| Programação (local do evento)                   | Já buscava pelo CEP                                                           |
| **Igrejas e unidades**                          | **Novo**: CEP preenche rua, bairro, cidade e UF                               |
| **Células**                                     | **Novo**: CEP + número montam o endereço do local (o texto continua editável) |

A consulta usa o ViaCEP direto do navegador, não grava o CEP pesquisado e nunca apaga o que a pessoa já digitou.

## 4. Células e redes em cartões com capa

- Cada célula e cada rede tem capa opcional (JPEG, PNG ou WebP até 3 MB). Sem capa, o cartão mostra a cor e as iniciais.
- **Segurança:** bucket privado `vinha-cell-covers`; o banco (`cell_cover`) confere quem vê (quem acessa Células na igreja) e quem troca (quem edita a célula ou a rede). A imagem sai por link temporário. Capa enviada pela metade nunca aparece.
- Migração `20261117210000_celulas_capas.sql` · teste `supabase/tests/cell_covers.sql`.

## 5. Barra lateral, chat, Portal e igreja inicial

- **Usuário no topo**: foto (do cadastro de membro), nome, papel e "Segurança da conta", logo abaixo da marca Vinha. A foto é a do próprio usuário, por link temporário.
- **"Precisa de ajuda?" removido** (o atendimento é o chat).
- **Recolher a barra** (botão « no topo): fica só com ícones; passar o mouse abre por cima do conteúdo; tirar o mouse recolhe; » fixa aberta. A escolha fica salva no navegador. No celular continua o menu ☰.
- **Chat Fale com a Vinha** em círculo com ícone próprio (balão com a folha), menor e no canto.
- **Portal da Vinha**: botão verde com ícone e ↗; abre em nova aba.
- **Igreja inicial**: depois do login o painel abre na igreja do cadastro de membro do usuário (sem cadastro, na igreja padrão do acesso). Quem tem acesso a várias igrejas troca no topo.

## 6. Publicação

- Produção: migrações `20261117210000_celulas_capas.sql` aplicadas.
- **Banco de teste (homologação) pausado — aplicar quando for reativado:**
  1. `20261117210000_celulas_capas.sql`
  2. (as anteriores do dia já estão no banco de teste)
- APK novo do **Vinha Equipe** (correção do Kids e totem).
