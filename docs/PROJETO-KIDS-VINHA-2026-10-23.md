# Projeto Kids Vinha

Data: 23/10/2026. Documento de análise e especificação; não representa implementação ou liberação operacional.

Atualização de execução: por decisão do usuário, o aplicativo nativo foi adiado. O K1 web é desenvolvido integralmente com cadastro, responsáveis, autorizações e cuidados; consultar `KIDS-K1-CADASTRO-INTEGRADO-2026-10-23.md` para o escopo implementado e as verificações. As recomendações móveis abaixo permanecem como planejamento futuro, não como condição de desenvolvimento nativo nesta entrega.

## 1. Direção recomendada

Reconstruir o núcleo Kids no Supabase principal, sem criar outro cadastro mestre de crianças ou responsáveis. Reaproveitar identidade visual, controle de acesso, cadastro de pessoas, estrutura de unidades e componentes comprovadamente úteis da Vinha. Não copiar telas, nomes comerciais, materiais ou código dos concorrentes.

A análise combina documentação pública dos fornecedores e inspeção estática do repositório. Não inclui acesso aos painéis privados dos concorrentes, demonstração contratada ou auditoria completa do banco de produção. Recursos anunciados pelos fornecedores não equivalem a uma certificação independente de segurança ou conformidade.

## 2. Referências de mercado

| Referência | Recursos documentados | Aplicação proposta na Vinha |
| --- | --- | --- |
| inChurch Kids | Crianças e responsáveis, turmas por idade, salas e vagas, reservas, etiquetas, app e WebApp, conteúdos e relatórios | Integrar recepção, turmas, responsáveis e acompanhamento, sem exigir aplicativo para participar |
| Prover / Ovelhinhas | Cadastro familiar pelo app, QR Code e etiquetas, comunicação, autorização de retirada, acesso conforme função e autorização de imagem | Portal dos responsáveis e acesso mínimo para professores e recepção |
| Planning Center Check-Ins | Cadastro integrado a People, estações assistidas e familiares, listas de sala, etiquetas de segurança, pessoas autorizadas e relatórios multicampus | Pessoas como fonte principal, estações com escopo definido e cadeia de custódia auditável |
| KidCheck | Procedimentos de retirada, conferência de autorizados, recibos digitais, capacidade e tratamento de etiqueta perdida | Projetar primeiro os fluxos de exceção e impedir que um QR isolado dispense a conferência do responsável |
| Breeze | Entrada familiar, etiquetas, frequência e acompanhamento de ausências | Operação simples para igrejas pequenas, sem perder segurança ou integração cadastral |

Estas são referências selecionadas por aderência funcional, não um ranking universal de melhores produtos. Impressoras e integrações anunciadas pelos fornecedores não devem ser presumidas compatíveis com a Vinha sem teste próprio.

## 3. Situação encontrada na Vinha

Foram identificados componentes KidsArea e KidsTools em app/DashboardApp.tsx; folhas de estilo kids.css e kids-tools.css; rotas children, children/guardians, kids, kids/label e kids/verify.

- Há conceitos de crianças, responsáveis, salas, sessões, entrada, saída, voluntários, ocorrências e chamados.
- As rotas inspecionadas usam cloudflare:workers e env.DB, não o fluxo atual de dados do Supabase.
- Os endpoints estão envolvidos por withLegacyContainment, que responde 503 FEATURE_NOT_RELEASED. Portanto, os problemas abaixo são do código legado bloqueado; não são prova de uma exploração ativa em produção.
- O catálogo marca Kids como development, aguardando validação ponta a ponta.
- A identidade infantil legada mantém nome e nascimento em children, separada de people. É necessário substituir essa duplicação por referência ao cadastro principal.
- A retirada legada pede ID do responsável em um prompt. Isso não é uma experiência operacional aceitável.
- O código legado compartilha código de retirada na etiqueta da criança, usa Math.random para esse código e verifica capacidade antes da inserção, sem demonstrar proteção transacional de concorrência nesse trecho.
- O chamado legado grava status sent sem demonstrar entrega a um serviço de mensagens. O novo módulo deverá distinguir registro interno, envio e entrega.
- A verificação legada por token retorna nome e sala. O novo QR público não deverá divulgar esses dados.
- Não foi demonstrada uma implementação completa de Kids no Supabase pelos arquivos inspecionados. Antes de migrar, inventariar tabelas, registros, arquivos e integrações reais em consulta autorizada somente leitura.

Decisão: não liberar o legado nem simplesmente mudar a aparência. Implementar o novo núcleo e migrar dados existentes apenas após inventário, correspondência e validação.

## 4. Cadastro mestre e vínculos

Pessoas/Membros é o painel principal. Ser uma pessoa cadastrada não significa automaticamente ter a condição eclesiástica de membro.

Modelo conceitual:

    Ministério → Unidades → Pessoas
                           ├─ perfil Kids da criança
                           ├─ responsáveis legais
                           ├─ pessoas autorizadas a retirar
                           └─ voluntários e equipe

### Regras cadastrais

1. Criança possui person_id obrigatório no cadastro principal, com perfil complementar Kids sem repetir nome, data de nascimento e contatos como fontes editáveis independentes.
2. Responsáveis e voluntários também referenciam Pessoas. Conta do aplicativo é um vínculo separado e verificado; cadastrar alguém não cria conta nem concede acesso automaticamente.
3. Busca enquanto digita por nome e código, respeitando ministério, unidade e permissão. Exibir informação mínima para distinguir homônimos, sem expor CPF ou dados sensíveis nas sugestões.
4. Sem cadastro: abrir cadastro rápido no próprio fluxo, salvar em Pessoas como visitante ou pendente, retornar com o vínculo confirmado e concluir o perfil Kids. Não usar texto livre como identidade final de quem retira uma criança.
5. Não exigir CPF da criança para cadastro básico. Não mesclar registros automaticamente somente por nome, nascimento, telefone ou documento de um adulto.
6. Conciliação de possíveis duplicados com revisão humana, histórico, mapa de IDs e preservação dos registros de presença.
7. Reutilizar os códigos e a política de numeração já adotados por Pessoas; não criar um segundo código concorrente para a mesma pessoa.
8. Família, parentesco, responsabilidade legal, contato de emergência, permissão de editar e autorização de retirada são relações distintas.
9. Estar na mesma família não concede automaticamente retirada. Ser responsável por uma criança não concede acesso aos outros adultos ou crianças de toda a família.
10. Nenhum autoatendimento pode autorizar alguém a retirar uma criança apenas por declarar parentesco ou selecionar seu nome no cadastro.

## 5. Estrutura de páginas

Submenu Kids, com nomes personalizáveis por usuário autorizado para todo o ministério:

- Visão geral: presentes agora, salas, ocupação, equipe, pendências operacionais e atalhos.
- Recepção e entrada: pesquisa familiar, visitantes, responsáveis, sessão, reserva e confirmação presencial.
- Retirada segura: conferência de criança, pessoa autorizada, comprovante e registro da entrega.
- Crianças: perfis complementares, vínculos e atalho para a ficha principal em Pessoas.
- Responsáveis e autorizações: vínculos aprovados, validade, restrições, contatos e histórico.
- Turmas e salas: idade, capacidade, localização, acessibilidade e responsáveis por turno.
- Agenda e sessões: cultos, EBD, eventos, recorrência, abertura e encerramento.
- Equipe e escalas: professores, auxiliares e recepção vinculados a Pessoas e Escalas quando disponível.
- Materiais e aulas: estudos, atividades e recursos privados por turma.
- Ocorrências e chamados: registros restritos e comunicação com responsáveis.
- Relatórios: frequência, visitantes, ocupação, ausência, tempo de permanência e movimentações.
- Configurações: nomenclatura, regras, permissões, canais, impressão, retenção e modelos.

Layout com verde e identidade Vinha, cartões e estados legíveis, tablet e celular desde a primeira entrega, formulários organizados, busca rápida e botões contextuais. Não usar prompts de ID, páginas com botões sem ação ou indicadores de tempo real sem atualização real.

## 6. Fluxos operacionais

### Preparação

Configurar unidade, sala, faixa etária, capacidade, sessão e equipe. As proporções de adultos/crianças serão parâmetros da política da igreja, não uma regra legal inventada pela plataforma. Disponibilizar alerta ou bloqueio de abertura conforme política aprovada.

### Entrada

Identificar o responsável, localizar as crianças vinculadas, conferir informações essenciais e autorizações, selecionar sessão/sala e confirmar recebimento físico pela equipe. Reserva ou pré-check-in não equivalem à criança presente. Impressão também não é prova de entrega física.

Uma transação deve revalidar acesso, unidade, sessão aberta, responsável, elegibilidade e vaga; impedir presença ativa duplicada e reservar a última vaga com segurança. Usar idempotência para que repetição de clique, leitura ou resposta perdida não duplique a operação. Entrada familiar deve informar resultado de cada criança, sem anunciar sucesso total se houver falhas.

### Durante a sessão

Lista da sala com presentes, entrada, equipe e alertas essenciais. Transferência entre salas precisa de autorização, capacidade, registro da origem/destino e confirmação da equipe receptora. Não mover a criança somente alterando um campo sem histórico.

### Retirada

Conferir a criança, verificar a identidade da pessoa que está retirando e sua autorização vigente, validar comprovante da sessão e registrar operador, responsável e horário da entrega física. A autorização deve ser reconsultada na operação, inclusive se foi revogada após o check-in.

O QR não substitui a conferência do autorizado. Código reutilizado, de outra sessão, de outra criança, expirado ou tentativas excessivas devem ser recusados. Uma autorização para um irmão não libera os demais implicitamente.

### Exceções obrigatórias

- Comprovante perdido: fluxo assistido de supervisor, confirmação de identidade, justificativa e auditoria; sem botão genérico de ignorar validação.
- Autorização ausente ou conflito: manter criança sob cuidado e acionar coordenação; não resolver automaticamente disputa familiar ou determinação judicial.
- Emergência: protocolo da igreja, contatos e rastreabilidade. O sistema não decide tratamentos médicos nem substitui atendimento profissional.
- Queda de internet: não anunciar operação salva se o servidor não confirmou. Disponibilizar procedimento de contingência e posterior conciliação. Retirada offline irrestrita não integra a primeira liberação.
- Impressora indisponível: procedimento assistido alternativo; fila de impressão com tentativas e estado real, sem criar nova entrada ao reimprimir.
- Encerramento com criança presente: manter pendência e exigir resolução. Nunca transformar encerramento automático em prova de entrega aos responsáveis.

## 7. Identificação, impressão e comunicação

Etiquetas distintas para criança e responsável. A etiqueta da criança não conterá o segredo suficiente para retirá-la. QR com identificador opaco, temporário e restrito à sessão; não incluir nome, nascimento, telefone ou informações de saúde no próprio código ou em página pública.

Configurar primeiro uma opção homologada de impressão térmica e PDF; tamanhos propostos 62×40 e 80×50 mm, sujeitos ao modelo real. Impressão silenciosa, Bluetooth e cada combinação de impressora/dispositivo exigem homologação específica. Não prometer suporte universal pelo navegador.

Modelo da igreja com fallback para Vinha; relatórios em PDF com rodapé Vinha. Etiquetas priorizam identificação operacional e legibilidade, sem publicidade que prejudique o uso.

Chamados privados dentro do painel/portal. E-mail e WhatsApp serão adaptadores separados, com fila, idempotência, consentimento/finalidade aplicável, reenvio controlado e estados pendente, submetido, entregue e falhou. Configurar SMTP no Supabase Auth não configura automaticamente os avisos Kids. WhatsApp depende da configuração e homologação do canal oficial; nenhuma mensagem real será enviada na etapa de planejamento.

Painel público de chamada deve usar identificação reduzida, sem expor nome completo, telefone, sala ou saúde da criança.

## 8. Privacidade, acesso e proteção infantil

Aplicar finalidade definida, minimização, melhor interesse e base legal adequada por tratamento. Consentimento não será tratado como autorização universal ou única base possível. Termo de participação, uso de imagem, comunicações e informações de saúde terão finalidades e controles separados, com revisão jurídica antes da operação real. Recusar uso de imagem não deve bloquear automaticamente a participação.

- Perfil de coordenação Kids por unidade, recepção por estação/sessão e professor/auxiliar por sala atribuída.
- Responsável acessa somente vínculos aprovados com suas crianças; usuário financeiro não herda acesso a informações de saúde do Kids.
- Dados de saúde e documentos restritos, arquivos privados e acesso temporário; etiquetas mostrarão somente alertas operacionais necessários, não prontuários completos.
- Aprovação e revogação de autorizados com autoria e validade. Restrições de retirada só serão vistas por quem precisa operar o procedimento.
- Fotos opcionais com finalidade definida. Não incluir reconhecimento facial, biometria ou compartilhamento entre ministérios na primeira versão.
- Separação por ministério e unidade em APIs, banco, arquivos, eventos em tempo real e exportações. A sede só consolida o que estiver autorizada a consultar.
- Acesso operacional revogado deve ser revalidado em cada operação crítica. Não confiar em papel enviado pelo navegador ou em dados de perfil editáveis pelo usuário.
- Histórico protegido de entrada, saída, transferências, autorizações, reimpressões, exceções e alterações sensíveis; sem registrar segredos, dados de saúde ou documentos completos em logs genéricos.
- Política de retenção, anonimização e atendimento a direitos definida com a igreja e assessoria jurídica. Não presumir prazo único para todos os dados.

## 9. Arquitetura proposta

Modelo conceitual, a ajustar aos nomes reais das tabelas existentes antes de qualquer migração:

- kids_profiles: vínculo único com pessoa e ministério, preferências e situação operacional.
- kids_guardian_links: criança, adulto, tipo de vínculo, autorização, aprovação, vigência e revogação.
- kids_care_information: informações restritas de cuidado, separadas dos cadastros gerais.
- kids_classes e kids_rooms: turmas, faixas etárias, espaços e capacidade.
- kids_sessions e kids_assignments: atividade por unidade/horário e equipe autorizada.
- kids_reservations: reservas sem confundir com presença física.
- kids_attendance e kids_custody_events: estado atual e eventos de entrada, transferência e entrega.
- kids_pickup_credentials: comprovantes temporários, segredos protegidos, expiração e invalidação.
- kids_incidents: ocorrências com visibilidade restrita e correções por histórico.
- kids_print_jobs: fila e reimpressões auditadas.
- kids_notifications: chamados, tentativas e estados reais dos canais.
- kids_materials: estudos e arquivos privados por turma/sessão.

Reutilizar Pessoas, unidades, contas de acesso, vínculos familiares, termos, arquivos e eventos apenas quando já estiverem migrados e seguros. Se Famílias/Termos ainda não estiverem prontos, implementar a dependência necessária no banco principal, sem chamar rotas legadas bloqueadas.

Comandos críticos transacionais no banco, restrições de integridade e acesso mínimo. O serviço administrativo não servirá como atalho para dispensar autorização. Realtime deve ser autenticado e segmentado; prever reconciliação após reconexão, sem assumir que um evento entregue ao cliente é a fonte definitiva do estado.

## 10. Plano de execução e critérios de aceite

### K1 — Cadastro integrado e fundação

Inventário somente leitura; modelo de autorização; migrações locais; perfis vinculados a Pessoas; cadastro rápido de visitante; responsáveis, autorizações e dados restritos; mapa de eventual migração com relatório de conflitos. Aceite: nenhuma identidade duplicada por projeto, nenhum vínculo cruzado entre ministérios e nenhum usuário concede a si próprio retirada indevida.

### K2 — Operação presencial segura

Turmas, salas, sessões, equipe, capacidade, entrada, retirada, comprovantes e exceções. Aceite: última vaga concorrente, presença duplicada, clique repetido, token de outra sessão, revogação durante operação e encerramento com pendências testados no banco e na interface.

### K3 — Recepção, portal e impressão

Estação assistida, modo tablet, pré-check-in, cadastro supervisionado pelo responsável, etiqueta e fila de impressão. Aceite: modelo real de impressora/dispositivo homologado; erro de impressão não duplica entrada; código perdido exige protocolo assistido; nenhuma consulta pública revela criança ou sala.

### K4 — Gestão e acompanhamento

Ocorrências, chamados internos, materiais, presença por turma, faltas, visitantes, aniversário e relatórios por unidade e escopo autorizado da sede. Integrações com agenda, eventos e escalas somente pelos fluxos já disponíveis. Aceite: exportações privadas, nomes e filtros corretos, totais sem duplicação e leitura restrita de dados sensíveis.

### K5 — Canais externos e liberação

Configuração separada de e-mail/WhatsApp, modelos aprovados quando necessários, confirmação de entrega, manuais de recepção/supervisor e treinamento. Homologação integrada com crianças e responsáveis fictícios, restauração de backup de teste, dispositivos reais, acessibilidade e verificação de segurança.

Não liberar retirada real antes de K1 e K2 aprovados e de existir um procedimento operacional homologado de identificação e contingência. Canais externos não configurados devem aparecer como indisponíveis, sem impedir o funcionamento seguro do atendimento assistido já homologado. Liberação por funcionalidade comprovada, sem declarar canais ou impressoras universais como prontos.

## 11. Testes que não podem faltar

Homônimos; visitante sem conta; irmãos com autorizados diferentes; adulto da família sem autorização; responsável sem direito de editar; bloqueio de retirada; tentativa de associação pelo próprio app; troca de unidade; professor removido da escala; sessão encerrada; duas recepções disputando a última vaga; leitura repetida; credencial roubada/reutilizada; duas retiradas simultâneas; mudança de autorização durante a entrega; perda de internet antes/depois da confirmação; falha de impressora; falha de mensageria; exportação de saúde por papel indevido; QR público; arquivo de outro ministério; pedido de anonimização; correção de cadastro com preservação histórica.

## 12. Aplicativo Android e iOS — requisito desde a fundação

O Kids será uma área do aplicativo personalizado do ministério, distribuído na Google Play e na App Store. Não criar um aplicativo por congregação: cada unidade terá seu conteúdo e suas permissões dentro do aplicativo do ministério. A configuração visual incluirá marca, cores e modos claro/escuro. Esta definição não significa que já exista um aplicativo nativo pronto: na busca realizada neste repositório não foi identificada uma base nativa nem uma esteira de publicação Android/iOS.

### Distribuição das funções

| Função | Aplicativo do responsável | Equipe autorizada no celular/tablet | Painel web |
| --- | --- | --- | --- |
| Crianças e responsáveis | Solicitar cadastro/correção; consultar vínculos aprovados | Cadastro assistido conforme papel | Revisar, aprovar e administrar vínculos |
| Reserva/pré-check-in | Selecionar atividade e criança autorizada | Consultar reservas | Configurar vagas e sessões |
| Entrada física | Apresentar comprovante | Identificar, conferir e confirmar chegada | Recepção assistida equivalente |
| Retirada | Solicitar retirada e apresentar credencial | Conferir adulto autorizado e registrar entrega física | Supervisão e tratamento de exceções |
| Cuidados | Solicitar atualização de informação pertinente | Ver somente o necessário para a turma | Gestão restrita e histórico |
| Chamados | Receber aviso e consultar detalhes autenticados | Acionar responsável e acompanhar resposta | Configurar canais e acompanhar falhas |
| Materiais/presença | Consultar conteúdo e registros dos próprios filhos conforme autorização | Registrar presença e conteúdo da turma | Publicar materiais e relatórios |
| Estrutura/segurança | Sem poderes administrativos implícitos | Coordenação limitada ao papel | Salas, capacidade, equipe, permissões e consolidação |

O aplicativo será inicialmente destinado a adultos responsáveis, membros e equipe. Não pressupor conta própria da criança, chat infantil ou participação autônoma de menores. A classificação nas lojas deve refletir público, conteúdo e divulgação reais; a existência de uma área administrativa Kids não define, sozinha, a categoria infantil. Se houver produto diretamente dirigido a crianças no futuro, exigir revisão específica de políticas e proteção de dados.

Conta de acesso, pessoa, parentesco, representação legal e autorização de retirada são vínculos distintos. Ser responsável no cadastro não concede automaticamente acesso digital; uma conta recém-criada não pode se vincular livremente a uma criança. O cadastro escolhe a unidade e solicita conciliação com Pessoas, com identidade verificada e aprovação nos casos necessários, sem promover visitante automaticamente a membro e sem associação automática por semelhança de nomes.

### Arquitetura e segurança móvel

Recomendação inicial: React Native com Expo, sujeita a prova técnica para câmera, notificações, acessibilidade e dispositivos de recepção. Compartilhar contratos de API, validações e tipos com o sistema, não presumir reaproveitamento direto de HTML/CSS. Não empacotar apenas o site em uma janela nativa.

Web, aplicativo do responsável e modo de equipe consumirão a mesma fonte oficial de pessoas e operações, com autorização por ministério/unidade no servidor. Não haverá banco independente de crianças no celular. Nenhuma chave administrativa, token de provedor ou credencial de envio será incluída no aplicativo. Sessões terão armazenamento protegido, revogação e recuperação de acesso; links de confirmação deverão retornar corretamente ao aplicativo ou à alternativa web.

Reserva não é chegada; solicitação de retirada não é entrega. QR será opaco, temporário e restrito à sessão, sem expor identidade ou cuidados em consulta pública. Aplicativo fechado, permissão de câmera recusada, notificações desativadas e falta de internet precisam de alternativas assistidas. Não permitir retirada offline sem validação atual de autorização. Notificação aceita pelo serviço não comprova leitura nem chegada do responsável; prever aviso interno e contingência da recepção. Evitar dados sensíveis na tela bloqueada.

### Aplicativos personalizados e lojas

Manter a proposta comercial de um aplicativo por ministério, mas tratar a aprovação individual como risco real. A regra 4.2.6 da Apple restringe aplicativos produzidos por serviços de modelos e prevê submissão pelo fornecedor do conteúdo. Recomenda-se estruturar a titularidade das contas e a submissão com o ministério, com suporte técnico delegado à Vinha, identidade e conteúdo próprios, sem garantir aprovação. Google também restringe conteúdo repetitivo/baixa qualidade. Um aplicativo agregador Vinha é alternativa a avaliar se necessário, não uma substituição já aprovada do modelo contratado.

Cada aplicativo precisará de identificadores, assinatura, credenciais de publicação, configuração de marca, canais de notificações, suporte e rotina de atualização próprios. Mudanças visuais não substituem utilidade real nem revisão das lojas. Separar homologação e produção, sem misturar contas, dados ou destinatários de teste.

Prever exclusão da conta dentro do aplicativo e solicitação também por página pública para Google Play. Distinguir encerramento do acesso de eventual retenção legítima de registros da igreja: não apagar indiscriminadamente históricos de guarda, nem manter todos os dados indefinidamente. Documentar finalidades, prazos e exceções com revisão jurídica. Preparar política de privacidade e declarações das lojas coerentes com dados, permissões e serviços de terceiros efetivamente usados.

Pagamentos, doações, inscrições em eventos e eventual conteúdo digital pago exigem análise própria do produto e das regras das lojas. Não presumir que toda integração de pagamento web poderá ser reutilizada indistintamente no aplicativo.

### Ajuste do cronograma K1–K5

- K1: incluir fundação móvel, identidade, seleção de unidade, conciliação com Pessoas, contratos de API, vínculos aprovados e planejamento de titularidade/publicação.
- K2: validar entrada e retirada com protótipo do responsável e modo de equipe em aparelhos reais, junto da operação web, com concorrência e revogação.
- K3: integrar câmera/QR, alternativa manual, recepção web/tablet e impressão homologada. Não presumir impressão Bluetooth universal pelo app.
- K4: integrar materiais, histórico permitido, acessibilidade, temas, avisos internos e push, sem depender de WhatsApp para a segurança presencial.
- K5: homologar Android/iPhone, links de autenticação, exclusão de conta, privacidade, comportamento offline e permissões recusadas; testar em TestFlight e faixas aplicáveis da Google Play; preparar conta de demonstração com dados fictícios para revisão, assinatura, suporte e monitoramento. Só declarar publicação após aprovação e disponibilidade verificadas nas lojas.

O desenvolvimento móvel acompanha o módulo desde K1; não será uma adaptação feita somente depois de concluir o painel. A operação assistida e segura deverá continuar disponível para famílias sem aplicativo.

## 13. Fontes

- inChurch Kids: https://www.inchurch.com.br/kids/
- inChurch, cadastro de crianças: https://portal.inchurch.com.br/pt-br/inchurch-kids-como-cadastro-as-crian%C3%A7as
- inChurch, app do responsável: https://portal.inchurch.com.br/pt-br/inchurch-kids-como-fazer-check-in-pelo-app-do-respons%C3%A1vel
- Prover, Ministério Infantil: https://sistemaprover.com.br/solucoes/ministerio-infantil
- Planning Center Check-Ins: https://www.planningcenter.com/check-ins
- Planning Center, segurança: https://help.planningcenter.com/en/138190-security.html
- KidCheck, procedimentos de retirada: https://www.kidcheck.com/tutorial/check-out-procedures/
- Breeze, check-in infantil: https://www.breezechms.com/lp/children-church-check-in
- ANPD, melhor interesse: https://www.gov.br/anpd/pt-br/assuntos/noticias/anpd-divulga-enunciado-sobre-o-tratamento-de-dados-pessoais-de-criancas-e-adolescentes

- Apple, diretrizes de revisão: https://developer.apple.com/app-store/review/guidelines/
- Apple, exclusão de conta: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- Apple, aplicativos para crianças: https://developer.apple.com/kids/
- Google Play, exclusão de conta: https://support.google.com/googleplay/android-developer/answer/13327111?hl=en
- Google Play, políticas: https://support.google.com/googleplay/android-developer/answer/18258653?hl=en
- Expo, projeto Android/iOS: https://docs.expo.dev/get-started/create-a-project/
- Expo, notificações: https://docs.expo.dev/push-notifications/what-you-need-to-know/

Próxima ação proposta: iniciar K1 completo, incluindo a fundação do aplicativo, preservando o bloqueio do legado e sem apagar dados existentes. Este documento não modifica a produção nem cria um projeto separado no GitHub, Vercel ou Supabase.
