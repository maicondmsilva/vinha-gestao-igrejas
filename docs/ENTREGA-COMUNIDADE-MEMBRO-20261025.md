# Participação do membro na igreja — 25/10/2026

Pedidos de oração, testemunhos, ministérios/departamentos e anotações no portal web e no Android MPR-Igreja, usando a mesma conta e o cadastro canônico de pessoas. A igreja acompanhada determina a comunidade consultada; participar de um grupo não transfere o cadastro nem concede acesso administrativo.

## Operação

O membro encontra as quatro áreas em Vida em comunidade; no Android, em Mais. A equipe administra em Configurações → Serviços e segurança → Comunidade do aplicativo, selecionando a igreja local. Somente proprietário, administrador ou pastor com gestão da unidade pode revisar conteúdo e solicitações. Não há desbloqueio das antigas rotas ou módulos legados.

- Oração: área, motivo privado e autorização opcional de contato pelo telefone cadastrado. A equipe recebe o telefone somente quando autorizado e em acompanhamento; registra resposta e situação, que o autor pode consultar. O autor pode cancelar pedidos ainda em acompanhamento. Não há envio automático de WhatsApp, email ou SMS.
- Testemunhos: texto, área, consentimento explícito de publicação e autorização separada para exibir nome. A igreja aprova o texto original ou recusa com motivo. Sem autorização de nome, a publicação usa “Membro da igreja”. Retirada pelo autor elimina imediatamente o texto do feed; revisão antiga não pode republicá-lo. A equipe pode retirar uma publicação por recusa fundamentada. Novo texto deve ser reenviado para revisão.
- Ministérios e departamentos: cadastro por igreja, descrição, tipo, disponibilidade e abertura de solicitações. Pedido único por conta/grupo, aprovação ou recusa com motivo, encerramento pelo membro e nova solicitação posterior. Cada participação referencia a pessoa canônica. Aprovação não cria papel de acesso, escala ou transferência de igreja.
- Anotações: criar, editar, arquivar e restaurar. Visíveis somente à própria conta no ministério, inclusive ao trocar a igreja acompanhada. Não existem listagem administrativa nem notificações contendo anotações. Não há exclusão definitiva nesta entrega.

Listas paginadas de 20 registros, consulta pública apenas de grupos ativos e testemunhos publicados com consentimento, pesquisa do membro na página atual. Dados sincronizam ao abrir a área, retomar o Android ou atualizar. Decisões alimentam a caixa de entrada privada já existente. Push com o aplicativo fechado continua fora desta entrega.

## Proteções e validação

Tabelas privadas com RLS, sem acesso direto de clientes; operações verificam conta confirmada, ministério ativo, filiação e unidade. Envios à igreja exigem pessoa ativa vinculada. As anotações não exigem atribuição em grupo. Decisões e edições usam versão; repetições de envio usam nonce e pedidos de participação têm unicidade por conta/grupo. Auditoria registra ação/identidade, sem conteúdo privado de anotações. Corpo de texto é renderizado como texto, sem HTML.

51 testes pgTAP locais cobrem privacidade, consentimento, identidade, aprovação, retirada, arquivamento, conflitos e preservação de papéis/cadastro. Teste concorrente verifica retirada contra publicação antiga e solicitação duplicada de participação. Testes de rota e estado verificam ministério da sessão, rejeição de payloads forjados, erro sem vazamento e resposta antiga de outra igreja. Tipagem web e Android e fluxos pela interface são conferidos antes da publicação. Somente dados fictícios locais são usados nos testes operacionais.

Compilações Android são versões internas para testes, sem publicação no Google Play. Pagamentos, login social e push dependem das respectivas integrações e contas e não são ativados por esta entrega.
