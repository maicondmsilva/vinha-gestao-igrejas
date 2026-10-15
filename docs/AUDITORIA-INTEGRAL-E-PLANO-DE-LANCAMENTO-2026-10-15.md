# Vinha — auditoria integral e plano de lançamento

Data: 15/10/2026, horário de referência America/Sao_Paulo. Versão examinada: `2c0dafe55c2221bbcc88b2d7c9633dd5fbc53a7f`.

## 1. Parecer executivo

**Não recomendo disponibilizar hoje a Vinha como plataforma completa, com contratação aberta e todos os módulos operacionais.** A Central tem uma base significativa implementada, mas o painel das igrejas ainda reúne funcionalidades persistentes, funcionalidades dependentes do ambiente antigo e demonstrações visuais. Há bloqueios de lançamento ligados a segurança, persistência, migração, autenticação e recuperação de dados.

É possível avançar para um **piloto assistido e restrito**, depois dos critérios obrigatórios deste documento. O primeiro produto vendável deve ter escopo explícito: membresia básica, unidades e operação administrativa, sem anunciar financeiro, Kids, aplicativo nativo ou integrações como prontos enquanto não forem homologados.

Não atribuo percentual global de conclusão: quantidade de telas, arquivos, commits ou testes unitários não representa prontidão para clientes. O progresso deve ser medido por jornadas aprovadas e módulos liberados.

### Respostas diretas

| Pergunta | Conclusão |
|---|---|
| A Vinha já está hospedada e publicada? | Sim. Site, login das igrejas e login da Central responderam HTTP 200 nesta auditoria; a versão principal tem publicação Vercel bem-sucedida. |
| Toda a Vinha foi migrada para Supabase? | **Não.** Existem 55 arquivos com referências ao banco antigo, incluindo 52 arquivos de rotas. Dois destes têm adaptadores Supabase explícitos; 50 rotas ainda precisam de migração/revisão do caminho legado identificado. |
| A Central já usa o banco principal? | As 23 rotas em `app/api/platform` não referenciam `env.DB` e usam a camada Supabase ou serviços correspondentes. Isso não comprova, sozinho, que todos os fluxos estejam completos ou homologados. |
| O financeiro das igrejas está pronto? | **Não.** O livro de movimentações exibido no painel é demonstrativo e registra alterações somente no estado React. É diferente do faturamento comercial da Central. |
| Cartão recorrente e emissão fiscal estão ativos? | **Não.** A integração nova é restrita a homologação; produção real continua bloqueada e faltam etapas de ciclo de vida. |
| Há aplicativo nativo pronto para as lojas? | Não foi encontrada, neste repositório, uma base nativa ou pipeline Android/iOS que comprove essa entrega. A interface de aplicativo no site não equivale a publicação nas lojas. |
| A segurança está certificada? | **Não.** Há controles relevantes, mas também pendências e limitações de verificação. Esta é uma auditoria técnica orientada a lançamento, não certificação, parecer jurídico nem pentest completo. |

## 2. Escopo, método e limites

Foram examinados código, migrações SQL, políticas de acesso versionadas, configuração de hospedagem, automação de validação, testes existentes, inventário de rotas, dependências e respostas públicas de produção. Foram executados testes automatizados locais e consultas HTTP de leitura, sem autenticação e sem tentativa de exploração.

**Limite importante:** nesta sessão, o conector Supabase recusou acesso à consulta SQL e ao Security Advisor. Portanto, não foi possível reconfirmar ao vivo todas as tabelas, políticas, buckets, configurações Auth, backups, plano contratado e alterações manuais no projeto. As conclusões sobre desenho de banco se baseiam nas migrações; informações da auditoria anterior são identificadas como histórico, não como verificação atual.

Não foram feitos: envio de mensagens, criação de cobranças ou notas, testes de carga em produção, alteração de credenciais, leitura de senhas/tokens, criação de usuários ou exploração de dados de outras igrejas. Não foi executado novo build local completo nesta auditoria; foi reconfirmado o sucesso da publicação da versão examinada e reexecutados os testes abaixo.

### Evidências quantitativas

| Verificação | Resultado |
|---|---|
| Arquivos de rotas API | 86 |
| Arquivos com `env.DB` | 55: 52 rotas e 3 helpers |
| Rotas com banco antigo e adaptador explícito | 2: Pessoas e Unidades |
| Demais rotas com dependência legada identificada | 50; cada operação ainda precisa de teste e revisão próprios |
| Rotas da Central em `app/api/platform` | 23, sem referência direta a D1 |
| Migrações SQL versionadas | 27; histórico aplicado precisa ser reconfirmado com acesso ao banco |
| Testes automatizados reexecutados | 14 aprovados; foco em avisos e integrações financeiras, não em todo o produto |
| Verificador de controles | 49 controles legados; o verificador passou porque não houve aumento, não porque as ações estejam concluídas |
| TypeScript | 318 diagnósticos `error TS...`; comando não passou |
| Auditoria de pacotes de produção | 25 avisos: 3 críticos, 11 altos, 10 moderados, 1 baixo |
| Auditoria completa de pacotes | 66 avisos: 3 críticos, 30 altos, 26 moderados, 7 baixos; inclui ferramentas usadas para construir o runtime |

Os números de dependências são avisos do registro de pacotes, não número de falhas exploráveis comprovadas na Vinha. Inventário de banco: `INVENTARIO-BANCO-LEGADO-2026-10-15.csv`.

## 3. O que existe e o que precisa melhorar

Classificações: **base implementada** significa código e persistência relevantes presentes; **parcial** exige conclusão; **legado** depende de recursos incompatíveis com a implantação atual; **demonstração** não deve guardar dados reais de clientes.

| Área | Estado observado | Melhorias ou desenvolvimento necessário |
|---|---|---|
| Site de apresentação | Publicado, com soluções e entrada para cadastro/teste | Alinhar a oferta ao que é realmente entregue; revisar contatos e promessas de aplicativo, financeiro, LGPD e auditoria. |
| Autenticação e seleção de ambiente | Supabase Auth, seleção de organização, onboarding e MFA da Central implementados | Testar confirmação, expiração, recuperação e renovação de sessão; configurar SMTP próprio; uniformizar autorização; tratar falhas de configuração sem recorrer à identidade antiga. |
| Central da Vinha | Organizações, convites, avaliação, acompanhamento, operadores, suporte, setores, contratos e catálogo possuem base Supabase | Homologação ponta a ponta, testes de regressão, estados de erro, paginação, auditoria completa e navegação consistente. Não equiparar base implementada a aceite final. |
| Hierarquia e unidades | Organizações/unidades, códigos desde 1000, vínculos e acessos modelados | Testar igreja contratada antes da sede, aprovação/revogação do vínculo, acesso por unidade, segregação de dados e troca de pagador sem duplicidade. |
| Membresia | GET/POST/PATCH com caminho Supabase; endereço, contato de emergência, notas restritas e consentimentos modelados | Transação única no cadastro, importação migrada, pesquisa/paginação, duplicidade, exclusão/arquivamento, histórico e autorização por campo. Não há DELETE exportado na API de Pessoas examinada. |
| Importação de membros | Interface e validação existem; API ainda utiliza D1 | Migrar lotes, prévia, relatório de erros, deduplicação, vínculo de unidade, reversão e trilha de importação. É bloqueio importante para onboarding comercial. |
| Famílias, consentimentos e PDFs | Fluxos e gerador existem, mas APIs dependem de D1 | Migrar relações e aceites; congelar versão e dados do termo aceito; aplicar autorização por titular/responsável; logotipo real, paginação e acentuação em PDF. |
| Kids | Interfaces e lógica antiga de salas, responsáveis/check-in | Migrar modelo e APIs; validar responsáveis e retirada, aceite no app, alergias, lotação, etiquetas, auditoria e concorrência. Não liberar para controle real de retirada infantil antes dos testes de segurança. |
| Eventos | Interface desenvolvida, ingressos, inscrição pública e pagamentos têm código legado | Migrar todo o fluxo, capacidade/estoque transacional, lotes, cupons, autorização de publicação por unidade, checkout, retorno, cancelamento/reembolso e QR anti-reuso. |
| Células | Interface chama API, mas a API ainda depende do banco antigo | Migrar grupos, supervisão, participantes, reuniões e presença; restringir informações dos participantes por liderança/unidade. |
| Escalas | Interfaces, confirmações e chat têm implementação antiga | Migrar persistência, permissões, indisponibilidade, conflito de horários, substituições, edição concorrente e escala consolidada. |
| Louvor | Interface e pesquisa demonstrativa em catálogo local | Pesquisa não é integração real com LouveApp/plataformas. Persistir repertórios, versões/tons, transposição musical real, referências e comunicação. Validar direitos de letras/cifras e apresentações antes de usar conteúdo protegido. |
| Comunicação das igrejas | Código de chat, anexos e notificações existe, mas depende do ambiente antigo | Migrar conversas, arquivos privados, membros e leituras; proteção de menores, denúncias, retenção e push. Diferente do chat de atendimento da Central. |
| Transmissões | Tela com dados de exemplo e ações locais | Integrar player/agenda/publicação; contas e permissões; notificações; moderação e métricas reais. A tela indicar “conectado” não comprova conexão ao YouTube. |
| Financeiro das igrejas | Livro financeiro demonstrativo; conciliação e provedores usam APIs antigas | Implementar razão persistente, categorias personalizáveis, contas, centros, transferências, competência/caixa, aprovações, anexos, conciliação e prestação de contas. Nunca usar o estado da tela como livro financeiro. |
| Relatórios/contabilidade | Central do contador exporta linhas de exemplo em CSV | Relatórios devem sair do banco e reconciliar totais. Validar layouts reais por versão com escritórios e arquivos de referência; não anunciar adaptador Prover/Domínio/Alterdata homologado sem teste de importação. |
| Cobrança SaaS da Vinha | Faturas, pagadores, planos/módulos e contratos por unidade implementados | Fechar descontos por unidade, consolidação por CNPJ, mudanças de ciclo, conciliação e recuperação de falhas. Separar dinheiro da assinatura Vinha de dízimos/ofertas da igreja. |
| Recorrência/fiscal | Preparação e processamento restritos ao sandbox Asaas | Cancelar assinatura no provedor, mapear pagamentos mensais, alterar preço/pagador, recuperar resultado incerto, homologar tomador/tributos, cancelar/substituir nota e enviar documento aos responsáveis. |
| Aplicativos por ministério | Configurações/preview web e fluxo antigo de cadastro existem | Implementar app real, tenant por ministério, escolha de unidade, conciliação por identidade verificada, aprovações e familiares. Construção white-label, nome/ícones/cores/vídeo, temas, push, atualizações e revisão das lojas. |
| Configurações | Há agrupamento de telas e algumas consultas persistentes | Há funções que apenas exibem “salvo” sem gravação demonstrada. Inventariar e persistir cada opção; eliminar sucesso fictício e impedir botões genéricos de simular conclusão. |

### Evidências funcionais especialmente importantes

- `app/FinanceProviders.tsx` renderiza `FinancialLedger`; este possui lançamentos fixos e `save()` apenas chama `setEntries`. Recarregar a página descarta o novo lançamento.
- `app/AccountingCenter.tsx` gera CSV com linhas fixas, não com lançamentos reais do período escolhido.
- `app/MusicCatalogSearch.tsx` pesquisa quatro músicas locais e calcula uma progressão genérica de acordes; isso não é a cifra original transposta nem busca automática nos provedores.
- `app/WorshipOperations.tsx` guarda alterações no estado local e possui mensagens de sucesso sem persistência correspondente.
- `app/BroadcastCenter.tsx` mostra métricas/contas exemplificativas e preparação em memória, sem integração operacional comprovada.
- `app/ActionCoordinator.tsx` abre um aviso de “ação não executada” para controles inacabados. É melhor que silêncio, mas não é implementação funcional.

## 4. Migração: diagnóstico e plano técnico

### 4.1 Por que o ambiente atual falha

O build Vercel substitui `cloudflare:workers` pelo arquivo `app/lib/cloudflare-env-stub.ts`. O acesso a `env.DB` nesse arquivo dispara explicitamente erro de rota dependente do banco antigo. Logo, trocar apenas login e domínio não migra as APIs de dados.

Pessoas e Unidades mantêm caminho Supabase explícito e fallback legado. `_auth.ts` também contém ambos os modelos de identidade. Isso deve ser eliminado ou isolado para impedir reativação acidental da identidade baseada em cabeçalhos antigos.

As outras dependências não se limitam a SQL: uploads de eventos/anexos usam `env.FILES`, o binding antigo de arquivos. A migração precisa contemplar armazenamento de objetos, URLs, permissões e arquivos existentes, não apenas tabelas.

### 4.2 Inventário por área — rotas com referência legada

| Grupo | Quantidade de arquivos de rota |
|---|---:|
| Pessoas/Unidades com adaptador explícito | 2 |
| Chat e aplicativo | 11 |
| Eventos e pagamentos | 12 |
| Identidade, hierarquia, importação e segurança | 10 |
| Kids, famílias e termos | 8 |
| Demais módulos | 9 |
| Total | 52 |

Há também três helpers com referências. O CSV fornece os 55 caminhos. Uma referência não significa que todas as operações daquele arquivo falham; o caminho efetivo depende do adaptador e das condições. Tampouco uma rota sem `env.DB` prova que a jornada inteira esteja pronta.

### 4.3 Processo obrigatório para cada migração

1. Inventariar tabelas, relações, arquivos, volume e IDs do sistema de origem. Não foi demonstrada nesta auditoria uma reconciliação completa dos dados antigos.
2. Definir destino Supabase com organização/unidade e chaves estrangeiras, evitando registros órfãos e vínculos cruzados.
3. Criar políticas RLS, grants mínimos e testes de acesso antes de expor a API.
4. Migrar API e frontend juntos, preservando estados, mensagens e contratos de resposta.
5. Executar transformação dos dados com mapa de IDs, relatório de duplicados/rejeitados e migração de arquivos; registrar a origem.
6. Comparar contagens por entidade/organização, totais financeiros, vínculos e amostras. Não basta a rotina terminar sem erro.
7. Testar criar/consultar/editar/arquivar, recarregar, usar outro navegador e trocar de usuário/unidade.
8. Fazer corte controlado, interromper gravação na origem e aplicar o delta. Evitar duas bases graváveis sem uma estratégia explícita de conciliação.
9. Definir rollback que preserve gravações posteriores; voltar apenas o código não desfaz mudança de banco com segurança.
10. Retirar o acesso antigo e adicionar verificação automática contra novas dependências D1/bindings em caminhos Vercel.

## 5. Segurança — achados por prioridade

**P0:** impede lançamento do escopo afetado. **P1:** concluir antes de ampliar o piloto ou liberar o módulo. **P2:** evolução após estabilização. Riscos identificados pelo código não são descritos como exploração comprovada.

### SEC-01 — P0: dependências com avisos críticos/altos

O projeto usa Next 16.2.6 e outras dependências com avisos. Os três alertas críticos consultados estão ligados a servidor Windows, otimização de imagem AVIF e `next/og`. A produção Vercel compila em Linux e a aplicação usa Vinext; portanto, é necessário identificar quais caminhos e bibliotecas realmente entram no pacote publicado. Não há comprovação de exploração nesta auditoria.

**Ação:** inventário do runtime e triagem de aplicabilidade, atualização compatível do conjunto Next/React/Vinext/Nitro e dependências transitivas, teste de regressão e nova auditoria. Não usar atualização forçada e indiscriminada como substituto da validação. A auditoria completa importa porque ferramentas declaradas como desenvolvimento também constroem o runtime final.

Referências: [servidor Windows](https://github.com/advisories/GHSA-p293-qw3h-jr36), [otimizador AVIF](https://github.com/advisories/GHSA-2xp9-vwfh-vxw4), [ImageResponse](https://github.com/advisories/GHSA-vcvr-r3jv-pc5j).

### SEC-02 — P0: autorização e isolamento precisam de prova integral

Há desenho de organização/unidade, RLS e papéis. A Central valida operador ativo e MFA. Notas pastorais têm políticas próprias restritas nas migrações. Entretanto, não foi possível executar nesta sessão a matriz de acesso no banco ao vivo.

Existem duas matrizes de permissões no código (`_auth.ts` e `church-access.ts`). A função contratual permite módulos quando não há contrato de unidade ou ele está em rascunho; o bloqueio aplicado no servidor não aparece nas políticas de Pessoas examinadas. Assim, bloquear uma tela/rota não comprova bloqueio equivalente na API REST direta do Supabase.

**Ação:** uma fonte de autorização, escopo explícito de administrador global/local, proteção no banco quando necessária e testes negativos por igreja, unidade, papel, estado da assinatura e acesso direto. Separar licença de módulo de permissão sobre os dados e definir comportamento de leitura/exportação após suspensão.

### SEC-03 — P0 antes de migrar documentos: autorização por titular/responsável

`app/api/documents/pdf/route.ts` exige sessão e filtra por igreja, mas o fluxo examinado não valida papel ou vínculo do solicitante com `personId`/`childId`. O código acessa CPF, contato, criança e alergias por esses identificadores. Hoje a dependência D1 bloqueia o caminho na Vercel; isso **não deve ser transportado como está** para Supabase.

**Ação:** autorizar antes de consultar; responsável só vê crianças vinculadas/validadas; documentos administrativos seguem papel/unidade; testar ID de outra pessoa na mesma igreja e de outra igreja. Não basta filtrar o CNPJ/organização.

### SEC-04 — P0 para entrada de clientes: autenticação, convites e e-mails

Convite de organização da Central foi migrado, mas convite de usuários da igreja ainda usa banco e cabeçalhos da identidade antiga. O cliente SSR de requisição ignora `setAll` de cookies; revisar o fluxo completo de renovação, sem concluir automaticamente que toda sessão falha. Na auditoria anterior, SMTP de autenticação e entrega real estavam pendentes.

**Ação:** migrar identidade de usuários/convites; configurar domínio e SMTP; testar e-mail real, retorno correto, convite revogado/aceito/expirado, recuperação, expiração e logout; nenhum segredo ou OTP deve ser enviado no chat. Erros de configuração devem falhar de forma fechada e explícita.

### SEC-05 — P0 para piloto: proteção e restauração

Não foi encontrada evidência versionada suficiente de backup automatizado completo e restauração exercitada. O plano/configuração real não pôde ser reconfirmado no Supabase. O plano gratuito tem limitações de backup/disponibilidade; backup de banco não inclui automaticamente os objetos de Storage.

**Ação:** definir RPO/RTO, cópia criptografada fora do ambiente, retenção, backup de arquivos e teste de restauração em ambiente isolado. É possível planejar piloto econômico, mas não tratar o gratuito como se fornecesse toda a operação de recuperação necessária.

Fontes: [backups Supabase](https://supabase.com/docs/guides/platform/backups), [checklist de produção](https://supabase.com/docs/guides/deployment/going-into-prod).

### SEC-06 — P1: proteção HTTP, origem e cache

As páginas públicas testadas têm HSTS. Não retornaram CSP, X-Frame-Options e X-Content-Type-Options. A ausência não comprova uma exploração, mas reduz a proteção em profundidade. As chamadas sem autenticação testadas retornaram 401/403, resultado positivo limitado ao acesso anônimo.

**Ação:** política de conteúdo compatível com players/fontes, `frame-ancestors`, `nosniff`, Referrer/Permissions Policy; verificação consistente de origem/CSRF em mutações; `no-store` para respostas privadas; testar cache com duas contas e sessões diferentes. Não afirmar vazamento de cache sem reproduzi-lo.

### SEC-07 — P1: uploads, anexos, URLs e conteúdo

Há binding de arquivos antigo. Ainda é necessário verificar buckets privados, MIME real, tamanho, nome/chave, vínculo à igreja/conversa e URLs temporárias. Documentos e anexos não podem ser públicos por conveniência.

**Ação:** Storage com RLS e limites, download autorizado, validação de conteúdo e arquivo perigoso, expiração de URLs, antivírus quando aplicável e testes de acesso cruzado. Revisar fetches externos contra SSRF e registrar apenas metadados necessários, nunca credenciais.

### SEC-08 — P1: abuso e notificações

O atendimento público possui limites modelados e secret de conversa em cookie HttpOnly. Os retornos financeiros novos validam assinaturas/tokens e tratam repetição. Isso é positivo, mas não substitui controles de abuso para todo o sistema.

Os alertas operacionais antigos marcam `delivered` após aceite da API e podem tentar novamente após resultado incerto. A fila financeira nova é mais conservadora. Existem dois comportamentos a unificar.

**Ação:** rate limits por identidade/IP/tenant e limites globais adequados, proteção contra automação abusiva e monitoramento; uma semântica de fila: preparado, aceito, entregue, falhou e incerto. WhatsApp automático deve usar modelos permitidos para o contexto. Testar callbacks fora de ordem e evitar reenvio duplo.

### SEC-09 — P1: privacidade e dados sensíveis

Filiação religiosa e informações de saúde exigem cuidados específicos. Crianças precisam de avaliação de melhor interesse e relações de responsabilidade verificadas. Um checkbox genérico não resolve sozinho as finalidades, bases legais, retenção ou prova de aceite.

**Ação:** revisão jurídica apropriada, papéis de tratamento, aviso e contrato com igrejas, finalidades/bases por dado, minimização, atendimento de direitos, retenção/exclusão/anonimização, resposta a incidentes e registro dos consentimentos aplicáveis. Cada termo aceito deve preservar versão, conteúdo, dados relevantes, responsável e evidência de aceite; não reconstruí-lo apenas com o cadastro atual.

Fontes: [FAQ ANPD](https://www.gov.br/anpd/pt-br/acesso-a-informacao/perguntas-frequentes), [crianças e adolescentes](https://www.gov.br/anpd/pt-br/assuntos/noticias/anpd-divulga-enunciado-sobre-o-tratamento-de-dados-pessoais-de-criancas-e-adolescentes). Esta recomendação técnica não substitui validação jurídica.

### SEC-10 — P1: segredos e observabilidade

A chave privilegiada Supabase é usada em módulo de servidor; a criptografia de credenciais implementa AES-GCM. A busca limitada no código versionado atual não confirmou chave privada/API embutida; um resultado de PEM era expressão de processamento de certificado, não uma chave fixa. Isso **não** certifica histórico Git, ambientes, bundles ou serviços externos.

**Ação:** varredura automática do histórico/bundles, rotação quando houver exposição, separação de chaves por ambiente, restauração segura da chave-mestra e logs sem dados sensíveis. Criar trilha de ações administrativas/financeiras e alertas para erros, falhas de cron, filas paradas e acesso suspeito.

### Pendências históricas a reconfirmar no banco

O relatório anterior registrou proteção contra senhas vazadas desabilitada, funções privilegiadas expostas intencionalmente, índices ausentes em tabelas anteriores e eventos restritos ao servidor com RLS sem política. Reexecutar Advisors e revisar cada achado com acesso renovado; não repetir estes itens como resultados atuais nem remover permissões legítimas apenas para silenciar alertas.

[Senhas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection), [funções privilegiadas](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [RLS sem política](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

## 6. Qualidade, dados e operação

- Os 14 testes cobrem uma parte restrita. As suítes SQL existem, mas não são executadas na rotina CI examinada. Faltam testes de navegador, matriz de papéis, persistência, importação, pagamentos e restauração.
- A CI faz build e testes financeiros, mas não bloqueia os 318 erros de tipos, não executa a verificação de botões e não inclui auditoria de dependências ou segurança de migrações como critérios obrigatórios.
- O uso genérico de `select('*')` e de listas sem paginação traz risco de truncamento por limites da API, lentidão e carregamento excessivo de dados pessoais. Conferir totais com volumes maiores que o limite de retorno padrão.
- O cadastro de pessoa é feito por várias chamadas com compensação posterior, não em uma transação única. Falhas parciais e políticas diferentes para exclusão podem deixar registros incompletos.
- O gerador PDF examinado cria uma página, remove acentos, desenha iniciais em vez do logotipo real e possui versão/data fixas. Não atende integralmente ao requisito de termos extensos, personalizados e fiéis ao aceite histórico.
- Configuração de ambiente local contém parâmetros de desenvolvimento como localhost/confirmação desabilitada; isso não comprova a configuração da produção. Não executar sincronização indiscriminada de configuração Auth.
- Não há comprovação nesta auditoria de isolamento completo entre Preview/homologação e banco/arquivos/provedores reais. Usar branch Git não isola banco automaticamente.
- A aplicação usa componentes de framework em beta. Não é proibitivo por si só, mas exige política de versões compatíveis, rollback, teste e acompanhamento de manutenção.

## 7. Estratégia recomendada de lançamento

### Oferta inicial

Começar com poucas igrejas-piloto, por exemplo 3 a 5, atendidas manualmente, sem prometer módulos não liberados. A quantidade é sugestão operacional, não capacidade comprovada do sistema.

**Escopo candidato:** login validado, convite/primeiro acesso, cadastro e edição de membros, importação, sede/unidades, papéis testados, atendimento e operação da Central. Recursos de nota fiscal/cobrança da Vinha devem ter processo comercial/fiscal válido definido com a contabilidade, mesmo que provisoriamente fora da automação da plataforma.

**Fora da primeira oferta, até homologação própria:** livro financeiro, pagamentos de eventos/doações no app, Kids/retirada infantil, chat interno com menores, integrações de cifras e app nas lojas. Bloquear por licença e autorização no servidor/banco; não apenas esconder o menu.

Não é necessário esperar todos os módulos para começar um piloto. É necessário que tudo o que for oferecido nesse piloto funcione e seja seguro. Hoje, mesmo esse escopo reduzido ainda exige fechar importação, segurança, autenticação e recuperação.

### Critérios obrigatórios de entrada do piloto

- [ ] Acesso de auditoria ao banco renovado e políticas/grants/Storage/contas privilegiadas revisados.
- [ ] Alertas críticos/altos aplicáveis corrigidos; não aplicabilidade documentada com evidência do runtime, sem exceções genéricas.
- [ ] SMTP/domínio e confirmação/recuperação/convites testados com destinatário real autorizado.
- [ ] Caminhos legados do escopo migrados; telas e APIs não prontas bloqueadas, sem mensagens falsas de sucesso.
- [ ] Membros/importação/unidades persistem ao recarregar e em outra sessão; falhas não deixam cadastro pela metade.
- [ ] Duas igrejas e duas unidades testadas com papéis distintos e tentativas de acesso cruzado, incluindo REST direto quando aplicável.
- [ ] Backup de banco e arquivos restaurado em ambiente separado; RPO/RTO medidos e aprovados.
- [ ] Monitoramento, responsável de suporte, procedimento de incidente e rollback exercitados.
- [ ] Termos comerciais, privacidade e escopo de oferta revisados; site não promete recurso inexistente.
- [ ] Nenhum defeito P0 aberto no escopo do piloto; validação registrada em ata/checklist de release.

## 8. Plano detalhado de execução

### Fase L0 — contenção e definição da primeira oferta

**Objetivo:** impedir uso incorreto de demonstrações enquanto a base é finalizada.

1. Aprovar o escopo do MVP e o catálogo de módulos: disponível, piloto, em desenvolvimento e não contratado.
2. Retirar dados demonstrativos dos ambientes de clientes e impedir gravações em memória apresentadas como definitivas.
3. Ajustar site, aquisição e onboarding à disponibilidade real; considerar acesso assistido em vez de liberação irrestrita durante a preparação.
4. Criar inventário de ações/rotas por módulo e regressão dos 49 controles; cada ação precisa de destino, permissão, resultado e tratamento de erro.
5. Definir responsáveis por desenvolvimento, validação/QA, operação e aprovação comercial/contábil.

**Aceite:** uma igreja nova não recebe métricas/lançamentos de exemplo como dados reais e não acessa operação inacabada como se estivesse pronta.

### Fase L1 — segurança e plataforma de qualidade

1. Renovar acesso de auditoria ao Supabase; comparar migrações aplicadas com as 27 versionadas e inspecionar mudanças manuais.
2. Fazer triagem/atualização das dependências, com teste do runtime Vinext/Nitro/Vercel e dos fluxos de login, imagem e páginas.
3. Unificar identidade e autorização; validar escopos de organização/unidade/pessoa e de contrato; remover dependência de cabeçalhos antigos no caminho de produção.
4. Implementar/revisar cabeçalhos, origem/CSRF, cache privado, validação de entrada e proteção de APIs públicas.
5. Configurar SMTP, testes de confirmação/recuperação, MFA e rotação/revogação de sessões sensíveis.
6. Fazer TypeScript passar no escopo inicial e criar plano de zerar a dívida inteira; novas alterações não podem aumentar o baseline.
7. Inserir CI de tipos, testes, botões, dependências e detecção de segredos. Separar teste de unidade, integração SQL e navegador.

**Aceite:** relatório de segurança atualizado, testes negativos aprovados e nenhuma vulnerabilidade aplicável impeditiva sem correção. Não emitir certificado de segurança próprio como substituto dos testes.

### Fase L2 — migração do núcleo e onboarding

1. Migrar convites de funcionários, diretório/permissões e preferências de unidade; autenticação uniforme.
2. Migrar importação; processar em lotes com transação/controle de reexecução, prévia, erros e deduplicação.
3. Tornar cadastro/edição de membros transacional; confirmar alteração/exclusão pela quantidade de registros efetivamente afetados.
4. Paginar listas e criar busca no banco; separar dados públicos, administrativos e pastorais por permissões.
5. Migrar arquivos para armazenamento com autorização; auditar dados preexistentes e relatórios de reconciliação da origem.
6. Revisar suspensão, troca de unidade e hierarquia, inclusive filha contratada antes da sede.

**Aceite:** novo ministério chega do cadastro ao painel, importa membros, delega acesso a uma unidade e consulta/edita dados persistidos sem acessar outra igreja. Todos os botões do escopo possuem teste de regressão.

### Fase L3 — operação confiável e início do piloto

1. Isolar homologação: projeto Supabase separado se houver disponibilidade no plano, ou ambiente local Supabase/Docker; banco e provedores de produção não devem ser padrão em Preview.
2. Criar rotina de backup de banco/arquivos, retenção, criptografia e restauração; definir RPO/RTO mensuráveis.
3. Configurar monitoramento de erros, latência, falhas de cron, filas e mudanças administrativas, sem registrar dados pessoais completos.
4. Ensaiar implantação e rollback com mudanças de schema compatíveis e dados posteriores ao release.
5. Preparar guia para cliente, checklist de onboarding, suporte e tratamento de incidentes.
6. Fazer homologação assistida com as igrejas-piloto e medir criação de conta, importação, erros e resolução de suporte.

**Aceite:** critérios do piloto concluídos e aprovação explícita do responsável pelo lançamento. Só então liberar o escopo reduzido para dados reais.

### Fase L4 — financeiro real da igreja e operação comercial da Vinha

1. Desenvolver livro financeiro persistente: contas, categorias de dízimos/ofertas personalizáveis, centros de custo, lançamentos, transferências e anexos.
2. Adotar valores em centavos e regras de conciliação, fechamento e reversão auditável; não apagar movimentos confirmados sem histórico.
3. Migrar configurações dos provedores e conciliação das igrejas; cada igreja recebe na própria conta contratada, sem misturar com o faturamento SaaS da Vinha.
4. Concluir fatura por unidade ou pagador central, descontos, promoções, pacotes/módulos e histórico de preços. Cobranças emitidas não mudam silenciosamente.
5. Homologar recorrência: autorização hospedada, identificação exata, mensalidades seguintes, falha, cancelamento no provedor, mudança de plano e ausência de duplicidade com a geração interna.
6. Homologar fiscal com contabilidade: dados do emissor/tomador, tributos, autorização, rejeição, cancelamento/substituição e envio do documento aos responsáveis.
7. Unificar filas/retornos, validar domínio e modelos WhatsApp; começar com destinatários autorizados, nunca envio em massa de teste.
8. Gerar relatórios reais e validar cada adaptador contábil com arquivo importado pelo escritório. Entrega fiscal/declaração é distinta de uma exportação contábil genérica.

**Aceite:** fechamento real reconciliado, reexecução sem duplicidade, devolução/cancelamento testados e homologação documental. Até lá, o módulo não deve ser vendido como livro financeiro operacional.

### Fase L5 — eventos, famílias/termos, Kids e células

1. Migrar Eventos e inscrições públicas; qualquer pessoa pode usar link público quando permitido, sem obter acesso administrativo. Publicação para todas as unidades exige permissão específica.
2. Implementar controle transacional de vagas, cupons, pagamentos, expiração de reserva, cancelamentos e check-in único.
3. Migrar famílias/responsáveis e consentimentos. Vínculos de crianças devem exigir comprovação/validação adequada, não somente o conhecimento de nome/CPF.
4. Reimplementar PDFs com logotipo, múltiplas páginas, caracteres corretos, dados históricos do aceite e pastor titular configurado; testar documentos longos e nomes extensos.
5. Homologar Kids: vagas por sala, entrada e saída distintas, retirada autorizada, etiquetas/códigos, condição médica restrita e supervisão/auditoria.
6. Migrar células: líderes/supervisores, participantes, reuniões e indicadores calculados de dados reais.

**Aceite:** matrizes por módulo e testes ponta a ponta aprovados. Kids só libera após teste específico de retirada indevida, duplicidade e acesso de responsável não vinculado.

### Fase L6 — escalas, louvor, comunicação e transmissões

1. Escalas persistentes por ministério, visão consolidada, confirmação/recusa, indisponibilidade, conflitos e substituição.
2. Repertório persistente, tom original e da execução, versão musical e transposição real de cifras autorizadas, não progressão genérica.
3. Links/metadados verificados nos provedores; conteúdo integral apenas com licença apropriada ou material próprio autorizado. Não presumir API disponível por existir uma página pública.
4. Chat de equipe/escala com permissões, anexos privados, notificações e retenção definida; proteção de menores e gestão de denúncias.
5. Transmissões com player e publicação por unidade, moderação e métricas comprovadas; não simular audiência, saúde do sinal ou conta conectada.

**Aceite:** fluxos usados por uma equipe real em ambiente controlado, persistência em múltiplas sessões e falhas de integração tratadas sem sucesso fictício.

### Fase L7 — aplicativo white-label e ampliação comercial

1. Definir arquitetura de app por ministério, API comum e isolamento; selecionar unidade no ingresso e aplicar segmentação em todas as consultas e notificações.
2. Vincular conta autenticada a membro preexistente somente após verificação segura e aprovação quando necessária; nunca por identificador artificial como `app-${Date.now()}`.
3. Personalização de nome, cores, logo, abertura, claro/escuro e acessibilidade; configuração e cache não podem misturar ministérios.
4. Homologar pagamentos e inscrições no aplicativo, responsáveis/filhos, consentimentos, push e preferências.
5. Criar builds Android/iOS, credenciais de publicação, política de atualização, privacidade e revisão das regras de aplicativos personalizados das lojas; aprovação não deve ser presumida.
6. Testar carga em homologação, limites por cliente, custos de armazenamento e suporte. Escalar por resultados medidos, não por promessa de armazenamento ilimitado.

**Aceite:** aplicativo assinado e aprovado no canal de distribuição aplicável, instalação em dispositivos reais, jornadas completas e monitoramento. Preview web não atende este critério.

## 9. Matriz mínima de testes de liberação

| Cenário | Resultado obrigatório |
|---|---|
| Anônimo chama API administrativa | 401/403, sem dados ou mutação |
| Usuário da igreja A informa ID da igreja B | Negado em API e banco; nenhuma existência/dado sensível revelado indevidamente |
| Administrador local acessa unidade não concedida | Negado; administrador global segue regra explicitamente aprovada |
| Responsável solicita documento/filho não vinculado | Negado antes da leitura dos dados |
| Módulo não contratado/suspenso por contrato | Comportamento consistente em tela, servidor e acesso direto, segundo política de leitura/exportação definida |
| Sessão expira ou é revogada | Renovação segura ou retorno ao login; sem aceitar identidade antiga |
| Salvar e recarregar em outro navegador | Registro preservado com dados e unidade corretos |
| Falha no meio de cadastro/importação | Transação revertida ou lote retomável, sem duplicados/órfãos |
| Duas pessoas ocupam a última vaga do evento/Kids | Uma confirmação; capacidade respeitada |
| Retorno de pagamento repetido/fora de ordem | Sem dupla baixa, receita ou assinatura |
| Timeout após pedido externo | Estado incerto conciliável; nenhum reenvio financeiro automático cego |
| Exportação contábil | Totais conciliados e importação validada no software destino |
| PDF com conteúdo longo e acentos | Legível, paginado, com logo e versão correta, sem expor terceiro |
| Backup restaurado | Dados e arquivos recuperados em ambiente isolado dentro do RPO/RTO aprovado |

## 10. Prioridade imediata e acompanhamento

**Próximo bloco recomendado: L0 + L1, seguido do núcleo L2.** Não começar outra grande frente visual antes de eliminar os bloqueios do piloto.

Para cada item, registrar ID, responsável, dependência, critério de aceite, evidência de teste, versão de release e plano de reversão. Um item só pode ser encerrado quando o critério for observado; “tela criada” e “build passou” são evidências parciais.

Não há estimativa responsável de prazo fechado sem definir equipe, escopo e restabelecer a inspeção do banco. Após L0/L1, estimar cada bloco por capacidade real e incerteza, com revisão semanal. Não confundir desenvolvimento pendente com simples falta de credencial: vários módulos exigem implementação substancial.

### Decisões necessárias do responsável pela Vinha

1. Aprovar ou ajustar o escopo de piloto proposto e a lista de igrejas iniciais.
2. Renovar acesso de auditoria ao Supabase sem compartilhar senhas/chaves no chat.
3. Definir caixa/remetente e serviço de envio; informar destinatário autorizado para a prova de e-mail.
4. Definir operação de backup, responsáveis e orçamento mínimo de infraestrutura; plano gratuito pode exigir procedimentos próprios e tem limitações.
5. Confirmar emissor fiscal e regras com a contabilidade antes de habilitar emissão/cobrança real.
6. Aprovar revisão da oferta pública para não contratar módulos ainda demonstrativos.

## 11. Referências e evidências complementares

- `INVENTARIO-BANCO-LEGADO-2026-10-15.csv`: 55 caminhos identificados.
- `VALIDACAO-INTEGRACOES-FINANCEIRAS-2026-10-15.md`: integração em homologação e pendências documentadas.
- `VALIDACAO-CENTRAL-2026-10-15.md`: registro anterior da Central; não substitui reconfirmação ao vivo.
- [OWASP ASVS](https://owasp.org/projects/asvs): referência para requisitos e verificações de segurança, não selo concedido à Vinha.
- [Supabase: checklist de produção](https://supabase.com/docs/guides/deployment/going-into-prod).
- [Supabase: backup de banco e limites de cobertura](https://supabase.com/docs/guides/platform/backups).
- [ANPD: dados pessoais e sensíveis](https://www.gov.br/anpd/pt-br/acesso-a-informacao/perguntas-frequentes).

**Conclusão:** há trabalho valioso já implementado, principalmente na Central e na fundação multi-igrejas. O próximo passo profissional não é declarar a plataforma completa: é transformar esse conjunto em um produto pequeno, persistente, auditável e recuperável, homologar com clientes-piloto e ampliar módulo a módulo.
