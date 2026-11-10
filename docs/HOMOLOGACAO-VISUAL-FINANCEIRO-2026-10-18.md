# Homologação visual do financeiro local — 18/10/2026

Ambiente: navegador local, aplicação em 127.0.0.1:4100 e Supabase Docker em 127.0.0.1:54321. Sem produção, provedores financeiros ou e-mails externos.

Conta/organização exclusivamente fictícias, preparadas com `scripts/local-browser-fixture.mjs --local-synthetic`. Credencial recebida por stdin sem eco e sem persistência; não reutilizar conta/senha de clientes. Organização sintética: `visual-local-f04e77f4-0cf7-4d5b-8abc-db5e185f7477`. Dados preservados no Docker para rastreabilidade, não enviados a produção.

## Resultados observados no navegador

| Fluxo | Resultado |
|---|---|
| Login pela tela /login | Sucesso com Auth local e conta confirmada; tela financeira carregou unidade autorizada |
| Nova conta Caixa visual fictício | Mensagem de gravação confirmada e conta persistida |
| Nova categoria Ofertas visuais fictícias | Categoria de receita persistida e disponível nos seletores |
| Lançamento com contas iguais | Recusado, sem movimento criado e sem botão preso |
| Lançamento de 12,34 em 17/10/2026 | Confirmado; caixa +1234 centavos e receita -1234 centavos |
| Estorno em 18/10/2026 | Original preservado, segundo movimento identificado como estorno e saldos zerados |
| Fechar até 17/10/2026 | Exigida confirmação de revisão; fechamento exibido após resposta do banco |
| Lançamento retroativo em período fechado | Recusado; histórico permaneceu com exatamente dois movimentos |
| Recarregar página | Fechamento e dois movimentos permaneceram persistidos |
| Retornar ao painel | Após correção, manteve tenant no endereço e abriu a configuração inicial da organização sintética (ainda não concluída), sem selecionar outro ministério |
| Paginação com dois movimentos | Anterior/Próxima desabilitados conforme limite; não equivale a teste de várias páginas |

## Correções feitas a partir da inspeção

1. O link de retorno perdia o tenant devido à diferença entre renderização de servidor e hidratação do navegador. O escopo agora é lido após montagem, antes de consultar dados; estado inicial idêntico nos dois lados. Nenhum fetch ocorre antes da definição do escopo. Respostas de consultas canceladas também deixam de atualizar a tela.
2. O reset global de estilos deixava inputs e botões sem contraste suficiente. CSS restrito à classe ledger-pilot acrescenta bordas, estados desabilitados, foco visível e hierarquia de títulos, sem alterar os demais módulos.
3. Adicionado teste de regressão do escopo/hidratação. Checagem de tipos strict e 107 testes locais aprovados após as correções.

Evidência visual local: `outputs/ledger-visual-20261018.png`, ignorada pelo Git. Não contém cliente real nem credenciais. O script de preparação não recebe URLs remotas e utiliza o leitor de configuração loopback já validado.

## O que este ensaio não comprova

Não foi simulada perda/interceptação de rede no navegador. Reenvio idempotente foi exercitado anteriormente por HTTP e pelos testes do núcleo; não rotular esse teste como navegador offline. Ainda faltam comportamento entre recargas com pedido incerto, papéis restritos e múltiplas unidades no navegador, várias páginas, telas mobile, conciliação e adaptadores externos.

Não houve implantação na Vercel, migração no banco principal, cobrança, nota fiscal, e-mail externo, aceite comercial ou liberação integral L3/L4. O servidor temporário deve ser encerrado ao fim do ensaio; os contêineres/volumes locais permanecem.
