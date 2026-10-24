# Configurações canônicas e revisão de cadastro — recibo

PR: https://github.com/maicondmsilva/vinha-gestao-igrejas/pull/61

Migrações aplicadas pelo conector autorizado no projeto Supabase Vinha `aoxibaaydfgffrdqtkva`:

- `20261024213649_organization_settings_source.sql`
- `20261024213655_member_self_service_identity.sql`

Os nomes locais correspondem aos recibos reais do serviço. O histórico do banco não foi reescrito. Nenhum cadastro real foi modificado para homologação.

Após aplicação: configuração pública do ministério existente acessível; usuário anônimo sem escrita de pessoa; fila privada sem leitura direta; fachadas de configurações e revisão com execução invocadora. Os avisos preexistentes do consultor de segurança sobre funções privilegiadas e proteção contra senhas vazadas permanecem pendentes; isto não é uma declaração de segurança integral da plataforma.

CI inicial do commit `9779664`: aprovado, execução `40134483442`. Regressão local: 46 arquivos e 2.169 testes. No navegador local, solicitação fictícia contendo telefone e endereço foi revisada aceitando apenas telefone; a interface confirmou aplicação somente dos campos selecionados.

Android: perfil MPR-Igreja vinculado ao ministério existente; verificação de tipos e exportação Hermes aprovadas. Java/SDK instalados identificados, projeto nativo gerado. Compilação APK bloqueada por conexão interna de sockets Java no Windows; não houve publicação no Google Play.

Publicação web: aguarda confirmação da implantação do último commit desta PR. Kids K2 e evidências não relacionadas não integram a publicação.
