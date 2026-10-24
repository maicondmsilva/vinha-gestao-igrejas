# Integração de usuários, membros e aplicativo-base

Implementação em preparação para publicação. Esta nota será complementada pelo recibo de produção após confirmação da implantação.

Cadastro confirmado por e-mail → igreja local do ministério → usuário com papel member pendente → cadastro de pessoa ou candidato a vinculação → revisão administrativa por campo → vínculo ativo sem promoção de papel. Todos os aplicativos compartilham a autenticação do painel; permissões continuam subordinadas à administração.

A interface web de autoatendimento fica em `/membro/<slug-do-ministério>`, acessível por Configurações → Serviços e segurança. A revisão fica em Configurações → Usuários e permissões. A listagem de usuários informa a existência do cadastro de pessoa vinculado.

O banco mantém pedidos privados com proposta e fotografia dos campos anteriores. Só campos selecionados são aplicados. Campos alterados por outra pessoa após o pedido geram conflito em vez de sobrescrita. Uma justificativa acompanha a decisão; pedido recusado preserva os dados. Vínculos e revisões são auditados na mesma transação. Pedidos pendentes não podem ser sobrescritos e há limite diário por conta.

Possíveis duplicidades de e-mail/CPF nunca vinculam identidade automaticamente. A administração precisa conferir a identidade e o cadastro. Dados do candidato não são devolvidos ao solicitante antes da vinculação. Casos incompatíveis exigem acerto administrativo, não fusão automática. O solicitante não escolhe papéis nem altera seu ministério/unidade por uma alteração de perfil.

Configuração pública do aplicativo contém somente identificação institucional, cores, logo e nomes/cidades das igrejas ativas; não contém membros, CPF, contatos de pessoas ou permissões. Seu leitor anônimo está em schema específico não exposto, sem conceder acesso ao schema privado geral.

Verificação local: 31 casos SQL de autoatendimento/revisão; 36 de configurações; regressão completa de 46 arquivos e 2.169 testes aprovada. Testes de rotas e armazenamento nativo adicionais aprovados. Compilação web de produção e exportação técnica Android aprovadas. Todas as gravações de homologação ocorreram no Docker local com dados fictícios.

O diretório `android-app` inicia a base única de aplicativos personalizados. Primeiro perfil confirmado pelo usuário: Ministério Palavra da Reconciliação, nome instalado MPR-Igreja. Veja seu README para o escopo, a geração por perfil e as pendências de assinatura/publicação. Não há aplicativo já publicado nas lojas. Kids K2 pendente, rotinas legadas e outras evidências locais não pertencem ao pacote de publicação desta mudança.
