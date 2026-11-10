# Execução inicial no emulador — 25/10/2026

AVD existente: Medium_Phone, arquitetura principal x86_64. Iniciado sem apagar dados e sem salvar novo snapshot. Nenhum cadastro real foi usado nos testes.

A instalação ARM64 foi aceita pelo emulador, mas a inicialização falhou no carregamento de `libreactnative.so`. Isso não confirma defeito em aparelho ARM64: o teste precisa ser realizado na arquitetura correspondente.

Gerador interno atualizado com arquitetura explicitamente limitada a `arm64-v8a` ou `x86_64`. Compilação x86_64 concluída: **BUILD SUCCESSFUL in 2m 37s**, 289 tarefas (20 executadas, 269 reaproveitadas). APK para celular preservado separadamente.

APK x86_64: `output/android/MPR-Igreja-0.1.0-emulador-x86_64.apk`.

- Nome: MPR-Igreja.
- Pacote: `com.vinha.mpr.preview`, versão 0.1.0, código 1.
- SHA-256: `8849e0550a9e2bcf2b50b0242d074109ba8ddda431a22153c00f18e4ba4beaca`.
- Atualização no emulador via ADB: Success, sem remoção dos dados.
- Inicialização: MainActivity iniciada; processo 32548 permaneceu ativo na verificação subsequente.
- Registros AndroidRuntime e ReactNativeJS do processo atual: sem erro reportado nessa janela de observação.
- Activity identificada como visível pelo Android.
- Três testes da base Android e verificação de sintaxe do gerador aprovados novamente.

Verificação visual e interação de telas pendentes: a autorização do controle da janela do emulador expirou. Não foram usados meios alternativos de captura para contornar essa autorização. Login, cadastro e sincronização em dispositivo não foram homologados nesta execução. APK mantém assinatura de teste; não houve publicação em loja.

## Verificação visual após autorização do usuário

Controle do emulador retomado após autorização explícita. Tela Meu perfil visível na sessão já aberta, com nome MPR-Igreja, identificação do ministério e seleção de igreja. Navegação para Início realizada pela interface: igreja MPR SEDE e mensagem de cadastro vinculado apresentadas corretamente. Nenhum formulário foi enviado, nenhuma igreja foi trocada e nenhuma credencial foi digitada. A sessão existente foi preservada. Este teste confirma renderização e navegação, não homologa entrada por senha, recuperação ou envio cadastral. Agenda, conteúdos e notificações continuam apresentados como pendentes de conexão, sem alegação de entrega desses módulos.
