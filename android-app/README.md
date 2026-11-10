# Aplicativo-base Vinha — primeiro perfil MPR-Igreja

**Situação mais recente:** primeiro APK interno gerado com sucesso na cópia física ASCII autorizada `C:/VinhaBuild/MPR` (289 tarefas, 8m18s). Nome MPR-Igreja, pacote `com.vinha.mpr.preview`, versão 0.1.0, arm64, assinatura Android Debug verificada. Arquivo entregue em `../output/android/MPR-Igreja-0.1.0-interno-arm64.apk`. Ainda sem teste de execução em aparelho/emulador ou publicação em loja. As seções de diagnóstico abaixo são histórico das tentativas anteriores; recibo atualizado em `../docs/evidencias/RECIBO-ANDROID-APK-INTERNO-2026-10-24.md`.

Base nativa Expo/React Native compartilhada entre ministérios. O perfil `brands/mpr.json` corresponde ao cadastro existente do Ministério Palavra da Reconciliação, não a uma organização criada para demonstração. Novos ministérios recebem perfis e identificadores próprios; as telas e as regras de autenticação permanecem comuns.

## Publicação nas lojas (Android e iOS)

Cada ministério tem o próprio app, publicado na **conta de desenvolvedor do ministério** (exigência da App Store, regra 4.2.6). O código é um só.

1. **Contas do ministério:** Apple Developer como organização (exige número D-U-N-S) e Google Play Console de organização. O ministério convida a Vinha como desenvolvedora nas duas.
2. **Perfil do app:** `node scripts/new-ministry-app.mjs --perfil <id> --nome "<Nome no celular>" --ministerio <uuid> --slug <slug>`. O comando cria `brands/<id>.json` e registra o perfil em `app.config.ts`.
3. **Variáveis no EAS (nunca no repositório):** `VINHA_APP_PROFILE`, `ANDROID_APPLICATION_ID`, `IOS_BUNDLE_IDENTIFIER`, `EXPO_PROJECT_ID`, `EXPO_PUBLIC_SUPABASE_URL` e `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. A produção recusa o build sem os identificadores da plataforma.
4. **Teste interno:** `eas build --profile preview --platform all`.
5. **Lojas:** `eas build --profile production --platform all` e depois `eas submit --profile production --platform all`. O Android entra no teste interno como rascunho.
6. **Correções sem nova revisão:** `eas update --channel production`. Mudanças nativas, como plugins e permissões, exigem nova versão (`runtimeVersion` segue a versão do app).

**Exclusão de conta:** fica no menu "Mais", em "Excluir minha conta", e também na web em `https://app.vinhaigrejas.com.br/conta/excluir`. Informe essa URL no Google Play, em Segurança dos dados → Exclusão de conta. Contas com papel de dono, pastor, administração ou financeiro precisam transferir a função antes.

## Implementado

- Configuração de marca por perfil de geração (`VINHA_APP_PROFILE`), com MPR como primeiro perfil.
- Vínculo fixo ao identificador do ministério; a resposta de configuração deve corresponder a esse identificador. O membro escolhe somente uma igreja desse ministério.
- Nome instalado MPR-Igreja; tema claro/escuro; logo e cores internas consultadas na fonte canônica.
- Cadastro, entrada e recuperação de senha pelo mesmo Supabase Auth do painel.
- Sessão em armazenamento protegido do dispositivo, com fragmentos limitados, operações serializadas e remoção no logout. Nenhuma chave administrativa no aplicativo.
- Perfil cadastral, envio para revisão e consulta da decisão. Permissões administrativas não são concedidas pelo cadastro.

## Preparação e verificações

Instalar com `npm ci` nesta pasta. Configurar em ambiente protegido apenas `EXPO_PUBLIC_SUPABASE_URL` e `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. São valores públicos; nunca usar service role, secret key ou senha de banco. As funções necessárias precisam estar publicadas no projeto correspondente.

Comandos: `npx tsc --noEmit`, `npx expo export --platform android --output-dir dist`, `npx expo start`. O diretório dist é um pacote técnico de JavaScript/Hermes, não um APK. A exportação inicial Android foi concluída com sucesso.

O perfil preview de EAS gera APK interno; produção gera AAB. A produção exige `ANDROID_APPLICATION_ID` definitivo aprovado pelo titular; o identificador de preview não deve ser levado à loja. A assinatura e a conta de publicação devem ser configuradas com o titular, sem compartilhar credenciais pelo chat. O arquivo de exemplo não contém credenciais reais.

## Limites atuais

Ainda não há APK/AAB concluído, execução verificada em dispositivo/emulador ou publicação no Google Play. Android Studio foi localizado com Java 25 em `C:/Android/jbr` e SDK/ADB no diretório Android do usuário. O projeto Android foi gerado e o Gradle baixado, mas a compilação local falha na comunicação interna do Java (`Unable to establish loopback connection`, `UnixDomainSockets.connect0`). Preferência IPv4 e diretório temporário explícito não resolveram; nenhuma proteção de rede foi desativada. O projeto pode ser aberto no Android Studio para diagnosticar o ambiente. Configuração de conta Expo/EAS, assinatura e Google Play são pendências externas. Vídeo/foto de abertura, notificações, conteúdos, agenda, contribuições e operações Kids no aplicativo não estão declarados prontos.

A auditoria inicial do gerador oficial identificou avisos de severidade alta na cadeia de ferramentas Expo (incluindo node-forge e zod). Não foi executado `audit fix --force`, que sugeria regressão incompatível do Expo. Esses avisos exigem revisão antes de assinar e distribuir a versão. A validação do pacote técnico não equivale à homologação de segurança ou da loja.

Diagnóstico adicional em 24/10: a opção `socketTemp` do gerador local apontando para `C:/Windows/Temp` superou a falha de sockets. A compilação avançou até exigir Java 17; o provisionamento automático pelo Gradle baixou a distribuição, mas falhou com `AccessDeniedException` na movimentação para o cache de JDKs. O SDK não foi removido nem foram relaxadas permissões do sistema. Próximo requisito: instalar/configurar JDK 17 e repetir a compilação pelo Android Studio ou pelo gerador interno.

Atualização posterior em 24/10: usuário instalou JDK 17 em `C:/Program Files/Java/jdk-17` e abriu o Android Studio. O projeto MPR foi aberto separadamente do FertCalc. SDK selecionado pela IDE: `C:/SDKStudio`. A sincronização e a compilação não devem executar simultaneamente, pois disputam `buildLogic.lock`. O caminho do usuário contém acento; a opção experimental indicada pelo AGP `android.overridePathCheck=true` permitiu avançar (também incluída no gerador interno, para resistir à regeneração do projeto). Não equivale a garantir compatibilidade de todas as ferramentas com caminhos Unicode. Plugins Kotlin/React Native/Expo compilaram; a tentativa seguinte chegou à instalação do NDK `27.1.12297006`, aguardando download. Os três testes da base Android passaram novamente. APK e execução no aparelho ainda não confirmados.

Resultado da preparação: NDK 27.1.12297006 instalado a partir do pacote oficial Google (781495902 bytes, SHA-1 `3bb7efc850cd0af7707854b7e0d5c3b6a7153703`, conferido com repository2-3.xml). Metadados da tentativa incompleta preservados em `C:/SDKStudio/ndk/27.1.12297006-incomplete-20261024`. Build-Tools 37 e CMake 3.22.1 instalados pelo Gradle com licenças preexistentes. Bundle Android gerado; compilação chegou a 129 tarefas. Bloqueio atual: Prefab/CMake não carrega `com.google.prefab.cli.AppKt` através do caminho Unicode. Invocação direta pelo caminho Windows 8.3 funciona, mas a compilação reconstrói o caminho longo e falha novamente. Próxima alternativa: cópia de compilação em caminho físico ASCII curto, preservando fontes e cache originais; ainda não criada. Não há compilação em andamento nem APK concluído.

Atualizações de dados e configurações são centralizadas; mudanças nativas exigem gerar e distribuir novas versões dos aplicativos afetados. Não há mecanismo de atualização remota de código habilitado nesta entrega. Nenhum perfil pode ser convertido em outro ministério pelo usuário final.
