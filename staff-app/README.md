# Vinha Equipe

App único da Vinha para a equipe dos ministérios: secretaria, recepção, liderança e pastores. Ele é publicado uma vez, nas contas de loja da Vinha. Cada pessoa entra com a conta do painel, escolhe o ministério e a igreja e vê só o que o acesso dela permite. Quem confere as permissões é sempre o servidor.

## O que faz nesta versão

- **Validar entrada:** lê o QR Code de ingressos pagos, inscrições gratuitas e retiradas de vendas. Mostra "liberada", "já registrada" ou "não liberar", com vibração e contador de entradas no aparelho.
- **Enviar push:** título, mensagem, igrejas de destino (só as que o servidor libera para a pessoa) e, se quiser, células ou ministérios específicos. Mostra o alcance antes de enviar. Agendamento, repetição e filtros por idade ficam no painel.

Próximas versões: Kids (modo estação, impressão de etiquetas por Bluetooth) e validação sem internet.

## Configuração

Variáveis no EAS (nunca no repositório): `EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `EXPO_PROJECT_ID`, `STAFF_ANDROID_APPLICATION_ID` e `STAFF_IOS_BUNDLE_IDENTIFIER`.

```
npm install
npx expo run:android            # aparelho ou emulador (Android Studio)
eas build --profile preview --platform all
eas build --profile production --platform all && eas submit --profile production --platform all
```

O app chama a mesma API do painel (`https://app.vinhaigrejas.com.br`) com `Authorization: Bearer <sessão>` e `x-vinha-tenant: <ministério>`. Sem cookie, o servidor aceita o token, e o banco aplica as mesmas regras do painel web.
