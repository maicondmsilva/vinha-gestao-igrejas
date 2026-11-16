# Arquitetura, layout e segurança — análise

Data: 17/11/2026 · Escopo: banco (Supabase), API do painel, painel (Next/vinext), app da igreja e Vinha Equipe. Os números foram medidos no código e no banco local com todas as migrações aplicadas.

## 1. Retrato atual

| Item | Quantidade |
|---|---|
| Migrações do banco | 175 |
| Rotas de API do painel | 206 |
| Funções públicas do banco (RPC) | 243 |
| Testes de banco (pgTAP) | 119 arquivos |
| Testes de código (node) | 143 arquivos |
| Arquivos de estilo do painel | 90 |

**Padrão de arquitetura:** a tela chama uma rota curta da API. A rota confere a sessão e o formato do pedido, e chama uma função do banco. As regras de negócio e de acesso ficam no banco (`security definer`, `search_path` fixo), testadas com pgTAP. É um bom padrão: a regra fica num lugar só e vale igual para o painel, o app e o Vinha Equipe.

## 2. Segurança

| Verificação | Resultado |
|---|---|
| Funções `security definer` sem `search_path` fixo | **0** ✅ |
| Tabelas do esquema público sem RLS | **0** ✅ |
| Tabelas do esquema `private` com acesso direto para `anon` ou `authenticated` | **0** ✅ |
| Funções executáveis sem login (`anon`) | **23**, todas de conteúdo público por definição: agenda pública, páginas da igreja, eventos, ingressos, verificação de termo, QR de visitante, chat de suporte, convite de organização ✅ |
| Cabeçalhos HTTP | `X-Frame-Options: DENY`, `frame-ancestors 'none'`, `object-src 'none'`, `Referrer-Policy`, API com `no-store` ✅ |
| Dados sensíveis (relatório de atendimento) | Tabela própria, 3 níveis de sigilo por permissão de usuário, registro de leitura, fora das exportações ✅ (nesta entrega) |
| Acesso pela função de liderança | Só proposto; o dono ou um administrador confirma. A retirada também é proposta ✅ (entrega anterior) |
| Segredos no repositório | Verificação automática no CI (`check:secrets`) ✅ |

**Pontos de atenção**
1. **Banco de teste pausado.** O projeto de homologação foi pausado pelo limite de 2 projetos gratuitos. As duas últimas migrações foram aplicadas direto em produção, depois de passar nos testes locais. *Recomendação:* plano pago com ramificação (branching) ou liberar um projeto, para voltar a testar antes de produção.
2. **Funções sem login que gravam dados** (`visitor_checkin`, `support_chat`). *Recomendação:* limite de frequência por IP na borda (Vercel Firewall) além das checagens do banco.
3. **Ajustes de funções por substituição de texto.** Várias migrações alteram funções existentes trocando trechos do código (padrão "falha se o trecho não existir"). Funciona e é seguro, mas acumula camadas. *Recomendação:* a cada trimestre, reescrever as funções mais alteradas (agenda pastoral, pessoas, caixa do app) numa migração "consolidada", com os mesmos testes.

## 3. Layout

**Corrigido nesta entrega**
- Regra global `header{height:78px;background:white}` em `globals.css` cortava cabeçalhos internos (Agenda pastoral, calendário, histórico). Foi neutralizada nas telas novas.
- A cor azul antiga (`#087fa3`) da Agenda pastoral foi trocada pelo verde da Vinha.
- Cabeçalho da Agenda no celular empilhado, com botão em largura total; calendário mostra só os dias com atendimento no celular.
- Ficha da pessoa: histórico de atendimento em linha do tempo, com cor por nível de sigilo.

**Recomendações**
1. **Escopo dos estilos globais.** `header{…}` e `button{…}` em `globals.css` afetam qualquer tela nova. Trocar por classes (`.app-header`, `.btn`) numa entrega própria, conferindo página por página com capturas.
2. **Arquivos muito longos.** Alguns componentes têm linhas com mais de 2.000 caracteres (Financeiro, Conciliação, Recebíveis, Operação de eventos). Passar o Prettier aos poucos (o CI já confere um conjunto de arquivos) facilita revisão e reduz erros.
3. **Componentes de base.** Botões, chips, abas e cartões se repetem em vários arquivos de estilo. Um pequeno conjunto comum (`vinha-ui.css`) com abas, chips, cartão, botão principal e secundário garante o mesmo visual em todos os módulos.

## 4. Desempenho
- As telas pesadas de Pessoas carregam sob demanda (ficha, cadastro, editor de cargos), e a lista usa uma chamada leve para os filtros (`roles-api.ts`), sem carregar o editor.
- Funções do servidor na região de São Paulo (gru1), perto do banco (sa-east-1).

## 5. Próximos passos sugeridos
1. Voltar a ter banco de teste ativo.
2. Limite de frequência nas funções públicas que gravam dados.
3. Entrega de estilo: escopo de `header` e `button`, mais o conjunto comum de componentes.
4. Consolidar as funções mais alteradas do banco.
