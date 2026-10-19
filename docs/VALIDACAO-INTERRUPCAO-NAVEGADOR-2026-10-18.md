# Interrupção do servidor no navegador — 18/10/2026

## Escopo

Somente localhost:4100 com Supabase Docker e o ministério sintético `visual-local-356d6c4b-bc38-4ddc-9920-8b032ec24c62`. Produção não acessada. Interrupção do servidor local não equivale a simular todos os modos offline do navegador.

## Observado

Preparada categoria de receita fictícia e formulário de lançamento de R$ 1,23, sem envio inicial. Após encerrar exclusivamente o processo Vite da homologação, o envio pelo navegador falhou e mostrou pedido pendente `54b5c4e7-2884-4549-a310-1e9fb8918ba9`, botão de reenvio e bloqueio de novos lançamentos/troca de unidade.

Ao restabelecer o servidor, a prévia de desenvolvimento recarregou a página. O estado pendente desapareceu: a implementação atual usa somente memória do componente. Portanto **a recuperação ponta a ponta não foi aprovada**. Não foi executado novo lançamento ou reenvio para substituir o identificador perdido. Não se afirma duplicidade nem confirmação de gravação desse pedido.

## Ajuste local

Mensagem técnica de falha de rede foi substituída por aviso em português que explica que o resultado não está confirmado. Teste de regressão confere o aviso.

## Correção necessária antes de liberar o piloto

Preservar pedido e identificador antes do envio, com escopo da conta autenticada, ministério e unidade. Restaurar somente após revalidar o acesso; falha de armazenamento não pode permitir envio sem proteção. Tratar privacidade, encerramento de sessão, dados inválidos e resposta já confirmada. Repetir os testes com recarga e resposta perdida após confirmação no banco. Não habilitar o piloto em produção enquanto isso estiver pendente.

Nenhuma publicação ou atualização remota de PR neste bloco.
