# Revisão financeira e códigos de cadastro

Implementação local na branch F4. Esta revisão não foi publicada em produção.

## Entregue

- A configuração normal dos provedores usa chave API/Access Token por igreja e ambiente, sem botão de criar conta.
- Asaas mantém a consulta cadastral já implementada. Mercado Pago e Safe2Pay por chave são armazenados criptografados e **pendentes de validação**, sem ativar meios de pagamento, checkout ou cobranças.
- Uma conexão efetivamente verificada cria uma conta de controle do provedor, sem saldo inicial presumido. O saldo vem dos lançamentos, não de uma consulta ao saldo bancário. A conta é mapeada por identificador interno, nunca por aproximação de nomes.
- Clicar no nome do lançamento abre modal. O modal contém os comprovantes, a autoria e as ações disponíveis.
- Previsões manuais sem baixas, série ou vínculo digital podem ser editadas: valor, descrição, conta, categoria/subcategoria, centro, forma, competência, vencimento e observações. Pessoa, identidade, criação e código são preservados. Versão e pedido idempotente impedem sobrescrita e repetição.
- A exclusão oferecida para previsão é cancelamento lógico. Lançamentos realizados exigem estorno; não há exclusão física de histórico financeiro.
- Anexos ficam no modal de criação e no modal de consulta/edição/baixa de um compromisso existente. O envio em um compromisso existente é uma operação independente da baixa, explicitada na tela. Séries não distribuem um único arquivo silenciosamente entre parcelas.
- O histórico apresenta nomes dos cadastros e valores monetários; referências técnicas de diário contábil, versão e UUID não aparecem como alterações comerciais.
- Os lançamentos compartilham uma sequência por igreja, iniciada em 1, sem reutilização após cancelamento. Pagar e receber usam o mesmo código estável do lançamento.
- Membros recebem simultaneamente um número geral do ministério e um número local da igreja. Proprietários/administradores escolhem o modo exibido. A preferência não recria pessoas; uma transferência de igreja aloca novo número local, preservando o geral.
- Cadastros existentes recebem números pela ordem de criação e, em empates, identidade. Números não representam CPF nem a identidade técnica do banco. Legados sem unidade não recebem número local fictício.
- Seletor superior apresenta nome e ID da igreja, sem prefixo do tipo. Botão Sair encerra a sessão deste navegador e remove dados temporários da Vinha.

## Verificações

- Tipagem e build Vercel aprovados localmente.
- 368 testes automatizados aprovados.
- 93 asserções SQL aprovadas, incluindo regressão F4, sequência, preferência, idempotência e conflito de edição, permissões e chave pendente. Fixtures SQL revertidas.
- Fluxo HTTP/Storage local: criação, revisão repetida sem duplicação, versão antiga recusada, códigos, upload/listagem/download privado, categoria ativa/inativa e acesso indevido.
- Conferência visual com conta fictícia: criação de previsão #3, edição de R$ 25,00 para R$ 29,00 preservando código, consulta de autoria/diferenças e cancelamento lógico.
- Advisor de segurança do banco local: nenhum alerta retornado. Isso não equivale à auditoria integral de produção.

## Pendências externas e publicação

- Mercado Pago/Safe2Pay por chave ainda exigem validação externa do titular/ambiente e compatibilidade do conector com esse modo. Não são apresentados como conectados ou homologados por apenas salvar a chave.
- Cofre de credenciais precisa estar configurado no servidor de destino; nenhuma chave foi solicitada em conversa ou inserida neste teste.
- Provedores, pagamentos, fiscal, e-mail e WhatsApp não foram acionados nesta revisão.
- A migração nova foi aplicada apenas no Docker local, sem registrar versão no histórico de migrações durante iteração. Antes de publicar, conciliar a branch F4 e aplicar as migrações revisadas no ambiente correto. Não publicar build com variáveis locais.
- A configuração de numeração deve ser avaliada antes da operação real: mudar o modo altera os códigos visíveis, mas não os vínculos.
