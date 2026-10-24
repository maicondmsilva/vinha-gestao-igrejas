# Aplicativo-base Vinha — primeiro perfil MPR-Igreja

Base nativa Expo/React Native compartilhada entre ministérios. O perfil `brands/mpr.json` corresponde ao cadastro existente do Ministério Palavra da Reconciliação, não a uma organização criada para demonstração. Novos ministérios recebem perfis e identificadores próprios; as telas e as regras de autenticação permanecem comuns.

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

Atualizações de dados e configurações são centralizadas; mudanças nativas exigem gerar e distribuir novas versões dos aplicativos afetados. Não há mecanismo de atualização remota de código habilitado nesta entrega. Nenhum perfil pode ser convertido em outro ministério pelo usuário final.
