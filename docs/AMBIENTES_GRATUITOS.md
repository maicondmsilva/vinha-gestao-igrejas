# Ambientes gratuitos da Vinha

## Decisão atual

Enquanto a Vinha estiver em desenvolvimento, não haverá contratação do Supabase Pro.

- O Supabase local é o ambiente principal de desenvolvimento.
- O projeto hospedado atual será usado apenas como homologação temporária.
- Homologação utiliza somente dados fictícios.
- Nenhum dado real de igreja, membro, criança, pagamento ou consentimento será usado antes da preparação do ambiente de produção.
- A produção será criada ou promovida somente perto do lançamento.

## Desenvolvimento local

Pré-requisitos:

1. Node.js e pnpm;
2. Docker Desktop em execução no Windows;
3. pelo menos 7 GB de memória disponível para a stack completa.

Comandos:

```powershell
pnpm install
pnpm db:start
pnpm db:reset
pnpm db:status
```

O Supabase Studio local fica disponível em `http://127.0.0.1:54323`.

Para encerrar os serviços:

```powershell
pnpm db:stop
```

### Validação realizada

Em 12 de outubro de 2026, o ambiente foi iniciado no Docker Desktop e reconstruído com `pnpm db:reset`. O teste confirmou:

- 7 migrations aplicadas sem intervenção manual;
- seed executado com 1 organização e 3 unidades fictícias;
- 9 tabelas públicas com RLS habilitada;
- API local, Auth, Storage, Studio e e-mail de teste ativos.

## Dados de teste

O arquivo `supabase/seed.sql` cria uma organização fictícia, uma sede, um campus e uma congregação. Usuários de teste devem ser criados pelo Supabase Studio local ou pelos fluxos da aplicação. O arquivo nunca deve conter credenciais ou dados pessoais reais.

## Homologação hospedada

O único projeto hospedado da Vinha será tratado como homologação enquanto não houver clientes reais. Previews autorizados da Vercel poderão apontar para ele, com variáveis exclusivas de homologação e integrações financeiras em sandbox.

## Produção futura

Perto do lançamento, escolher uma das opções:

1. contratar o Supabase Pro e criar um projeto de produção separado, mantendo homologação remota; ou
2. limpar e promover o projeto hospedado atual para produção, mantendo a homologação somente local.

A primeira opção é recomendada quando houver dados reais e clientes pagantes.

## Segurança

- Nunca expor a stack local à internet.
- Nunca versionar `.env.local`, chaves ou tokens.
- Nunca usar a chave `service_role` no navegador.
- Toda tabela exposta deve ter RLS e políticas por organização/unidade.
- Migrações são a fonte oficial do esquema; alterações manuais devem ser convertidas em migrations antes de serem promovidas.
