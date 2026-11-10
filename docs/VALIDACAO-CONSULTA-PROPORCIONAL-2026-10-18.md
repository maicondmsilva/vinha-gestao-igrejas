# Consulta proporcional — verificação local

## Resultado desta rodada

- 145 testes da aplicação passaram (`node --test scripts/*.test.mjs`).
- Quatro cenários reais sobrepostos em READ COMMITTED passaram: repetição da mudança, conflito de versões, emissão repetida e virada repetida.
- O banco temporário sintético foi removido pelo executor; dados locais existentes foram preservados.
- Compilação completa com `node scripts/local-pilot-build.mjs` concluída, saída 0. Houve avisos de dependências opcionais no rastreamento do Nitro e de imports dinâmicos; não foram tratados como falhas de compilação.
- Nenhuma publicação, cobrança, mensagem ou migração de produção foi realizada.

## Limites

Não é homologação visual autenticada. As três migrações proporcionais continuam candidatas; os testes usam transação desfeita ou banco temporário, e não confirmam a disponibilidade dessas tabelas no banco persistente usado pelo navegador.

Ainda faltam concorrência com gerador mensal antigo, alterações de catálogo e revogação de acesso durante operações; prévia e confirmação da mudança pela interface; cancelamento com restituição de crédito, troca de pagador e recuperação de períodos atrasados. A proteção do salvamento antigo é uma barreira de API no piloto, não substitui uma garantia transacional no banco.

O bloco L4 permanece aberto e restrito ao desenvolvimento local.
