# Entrega: Comunicação, Ao vivo e organização Kids — 27/10/2026

## Comportamento entregue

- Navegação lateral única por módulo, com subpáginas persistentes no módulo ativo e recolhimento ao trocar de módulo. Financeiro, Células, Configurações, Comunicação, Programação e Kids seguem a mesma regra. Links preservam ministério e igreja.
- Comunicação: avisos, vídeos, categorias, grupos de publicação, banners/atalhos e arquivos. Pesquisa, situação, paginação, rascunho, publicação explícita e arquivamento. Imagens por endereço público HTTPS com prévia.
- Ao vivo: canais YouTube (ID ou endereço oficial), HLS e Vimeo; transmissões com origem, canal, categoria, início/término em Brasília e estados programada/ao vivo/encerrada. A marcação de estado não inicia um encoder nem grava uma transmissão externa.
- Destinos: igreja atual, igrejas escolhidas, todas as igrejas atuais autorizadas ou grupo versionado. Alterar grupo não redistribui conteúdo anterior. Publicação tem confirmação nominal dos destinos e revalida permissões e módulos no servidor. Gestor local consulta compartilhamentos sem alterar o alcance de outras igrejas.
- Publicações possuem fonte única e cópias sincronizadas no catálogo público já usado pelo aplicativo. Arquivamento retira todas as cópias; edição publicada retorna a rascunho. Editores anteriores não alteram isoladamente cópias gerenciadas. Canais e banners também aparecem no portal web do membro.
- Kids: Materiais com editor e arquivamento, Ocorrências e chamados internos com filtros e conclusão pela supervisão, Presenças por sala com período, paginação e exportação CSV da página exibida. Contagens não exportam dados pessoais. Ocorrências seguem a autorização por sala; recepção não recebe os textos. Fluxos de entrada/retirada e conferência presencial preservados.

## Validação local

- TypeScript core aprovado; verificação de segredos e controles aprovada.
- 27 testes Node dos fluxos alterados aprovados, incluindo API com identidade da sessão, URLs, versões e CSV.
- Regressão SQL: 57 arquivos, 2.646 testes aprovados (36 de publicação e 33 na fixture de relatório Kids).
- Duas publicações simultâneas: somente uma revisão vence; exatamente duas cópias para duas igrejas autorizadas.
- Advisors local sem apontamento novo sobre publishing/kids_desk; avisos existentes de outras tabelas fora deste escopo.
- Navegador local: alternância Financeiro/Comunicação/Programação/Kids; grupo com duas igrejas, aviso por grupo publicado, canal YouTube fictício salvo, relatório e ocorrências carregados, editor de materiais.
- Todos os cadastros de homologação permanecem no Docker local. Produção estava com zero mídias, publicações e ocorrências antes da migração.

## Limites explícitos

- Push em aparelhos reais depende de Firebase/Expo e homologação, já registrados como pendência anterior. Publicar conteúdo não afirma envio externo.
- Não há descoberta automática de lives YouTube, ingestão RTMP, gravação automática ou cadastro de rádio nesta entrega. O vídeo específico ou HLS deve ser informado.
- Materiais Kids mostram até 100 registros recentes com busca local; relatório pagina 20 salas e exporta somente a página exibida.
- Categorias de eventos continuam no módulo Programação; categorias de conteúdo são compartilháveis em Comunicação. Questionários adicionais de eventos não fazem parte desta alteração.

## Publicação

A preencher após CI, migração remota e implantação verificadas.
