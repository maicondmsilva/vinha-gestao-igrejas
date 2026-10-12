# Fluxo de release da Vinha

## Branches

- `main`: producao.
- `develop`: homologacao compartilhada.
- `feature/*`: novas funcionalidades.
- `fix/*`: correcoes.

## Promocao

1. Criar `feature/*` ou `fix/*` a partir de `develop`.
2. Abrir Pull Request para `develop`.
3. Aguardar build e preview.
4. Homologar em `staging.vinhaigrejas.com.br`.
5. Abrir Pull Request de `develop` para `main`.
6. Exigir aprovacao antes do merge em `main`.
7. Validar o deploy de producao e executar os smoke tests.

## Banco de dados

- Toda alteracao estrutural deve ser uma nova migracao em `supabase/migrations/`.
- A migracao deve ser aplicada primeiro no banco local e depois em homologacao.
- Dados reais nunca devem ser copiados sem anonimização para homologacao.
- Migracoes aplicadas nao devem ser editadas; correcoes usam uma nova migracao.
- A promocao para producao exige plano de backup, verificacao e rollback.

