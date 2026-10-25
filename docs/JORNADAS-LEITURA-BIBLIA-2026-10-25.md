# Jornadas, planos de leitura e Bíblia — 25/10/2026

Entrega integrada ao portal do membro e ao Android MPR-Igreja. Cada igreja publica seu próprio catálogo em Configurações → Serviços e segurança → Jornadas e planos de leitura. A Bíblia é compartilhada entre os aplicativos personalizados; inscrições e dados pessoais permanecem separados por ministério e conta.

## Administração

- Criar e editar rascunhos com até 366 etapas, texto e material complementar HTTPS.
- Adicionar capítulos por livro e número. Planos exigem de 1 a 12 capítulos por etapa.
- Preparar João em 21 dias ou todos os 1.189 capítulos em 365 dias. Os modelos começam como rascunhos, sem publicação automática.
- Publicar, arquivar ou duplicar uma edição. Conteúdo publicado não é reescrito: uma nova edição preserva o progresso anterior.
- Ver totais de inscrições e conclusões. Não há consulta administrativa aos marcadores, posição bíblica ou anotações privadas.

## Membro

- Consultar catálogo da igreja acompanhada, iniciar conteúdo e marcar ou desfazer etapas.
- Jornadas seguem sequência; desfazer uma etapa também desfaz as seguintes. Planos permitem leitura fora de ordem.
- Preservar inscrições antigas ao mudar a igreja acompanhada. Arquivamento impede novas inscrições, mantendo a leitura de quem já iniciou.
- Ler os capítulos indicados e retornar ao mesmo dia/etapa. Conclusão é informada pelo participante, sem atribuir cargos, permissões ou certificados.
- Receber aviso privado de conclusão na caixa de entrada.

## Bíblia

66 livros, 1.189 capítulos e 31.102 versículos. Seleção de livro/capítulo, navegação entre livros, pesquisa literal sem distinção de acentos, fonte de 14 a 32, tema automático/claro/escuro, marcadores, ponto de leitura e reflexão em Minhas anotações.

O texto completo é incorporado ao APK e pode ser lido sem internet. Progresso de planos, marcadores e anotações exigem conexão para sincronizar; falhas são mostradas e não simulam gravação. O portal web carrega o texto apenas ao abrir a Bíblia.

Fonte: Bíblia Livre (BLIVRE), fevereiro de 2018, © Diego Santos, Mario Sérgio e Marco Teles, CC BY 4.0. Origem e licença são exibidas no leitor e nas citações salvas. Conversão de XML para JSON sem alteração intencional do texto, sem notas/introduções. Procedência e hash em shared/bible/provenance.json; conversor reproduzível em scripts/prepare-bible.py.

## Validação

- 60 testes SQL locais: isolamento, identidade ativa, versões, sequência, inscrições idempotentes, preferências privadas, marcadores, integração com anotações e caixa de entrada.
- 7 testes de integridade/contratos, incluindo distribuição exata dos 1.189 capítulos em 365 dias.
- Concorrência real no PostgreSQL: inscrição única e rejeição de atualizações concorrentes com versão vencida.
- 21 testes de regressão de experiência Android, agenda e comunidade.
- Tipagem web e Android, verificação de segredos e lint dos esquemas private/public aprovados. O lint global sinaliza funções internas preexistentes do pgTAP, sem achados nas funções da aplicação.
- Homologação no navegador apenas com dados fictícios locais: rascunho/publicação, inscrição, progresso, plano→Bíblia→retorno, busca, marcador, anotação e ponto de leitura.
- Android x86_64 e arm64-v8a compilados com sucesso. APK interno de desenvolvimento, ainda sem publicação no Google Play.

Banco privado com RLS e sem acesso direto dos clientes: operações passam por funções com identidade e escopo verificados. Os avisos de RLS sem políticas são intencionais para esse modelo de acesso; índices recém-criados aparecem como ainda não utilizados.

Nenhuma jornada ministerial real ou conteúdo de terceiros foi publicado automaticamente. A equipe de cada igreja deve revisar e publicar seus materiais.
