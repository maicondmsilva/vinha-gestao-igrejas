# Financeiro — contas, comprovantes e categorias

Estado: implementação local em revisão, junto da F4. Não corresponde a publicação em produção nem homologação externa dos provedores.

## Contas bancárias e caixas

Financeiro → Contas bancárias e caixas → Nova conta bancária / caixa.

Cada cadastro pertence a uma igreja específica. Campos: nome, banco/instituição, agência/número da conta, descrição e estado ativo. A conta pode ser vinculada ao lançamento e à destinação de recebimentos. Cadastrar a conta não conecta internet banking nem movimenta dinheiro. O saldo inicial usa o lançamento específico já existente, não uma edição arbitrária do saldo.

## Comprovante no lançamento

O formulário de lançamento avulso possui campo opcional para PDF, PNG ou JPEG, até 4 MB. O conteúdo e o tamanho são conferidos antes da gravação e novamente no servidor; a política do armazenamento privado revalida o acesso ao lançamento/igreja. Não há URL pública.

O lançamento precisa ser confirmado antes do envio do arquivo. Se o envio falhar ou seu resultado ficar incerto, o lançamento permanece salvo e a tela abre a consulta de anexos para enviar somente o documento, sem duplicar a movimentação. Se a confirmação do lançamento ficar pendente, o mesmo pedido deve ser retomado. Arquivos permanecem somente na memória do navegador até o envio; após recarregar/encerrar a sessão, pode ser necessário selecioná-los novamente.

Séries/parcelas: o documento é anexado ao lançamento correspondente após sua criação, para não atribuir silenciosamente um comprovante a todas as ocorrências. Lançamentos já existentes permitem consultar/enviar documentos em Consultar → Comprovantes e documentos. Arquivos não são substituídos ou excluídos pelo fluxo comum.

## Categorias

Financeiro → Categorias e subcategorias. Cada cartão agora tem ações separadas:

- Editar: altera dados permitidos, preservando identidade, escopo, tipo e vínculos.
- Desativar categoria: requer confirmação; não apaga lançamentos ou histórico. Subcategorias ativas precisam ser desativadas primeiro.
- Ativar categoria: disponibiliza novamente para novos lançamentos. A categoria principal deve estar ativa antes de uma subcategoria.

O comando preserva a versão otimista; uma alteração concorrente exige atualizar a consulta. Categorias inativas continuam disponíveis para consulta de registros anteriores, mas não para novos lançamentos.

## Conexões dos provedores

- **Asaas:** campo de chave API protegido, ambiente explícito, sem senha pessoal. A chave é retirada do formulário após envio; consulta de acesso ao banco ocorre antes da verificação externa. O segredo é criptografado no servidor e não volta ao navegador.
- **Mercado Pago:** mantém autorização oficial OAuth para contas de igrejas atendidas pela Vinha. Não se troca o consentimento de terceiros por coleta indiscriminada de credenciais de desenvolvedor. [Orientação oficial](https://www.mercadopago.com.br/developers/pt/docs/smartapps/resources/credentials?scope=prod).
- **Safe2Pay:** a API utiliza chave, mas a prova de titular/ambiente do conector e sua homologação continuam pendentes. Não se coleta a chave para depois anunciar uma conexão fictícia.

Abertura de conta, conexão, confirmação de titularidade, conta bancária de destino e liberação de meios de pagamento são etapas distintas. Sem cofre configurado na infraestrutura, o envio de chave permanece bloqueado. A homologação externa foi adiada pelo responsável; nenhum teste deste complemento criou cobrança externa.

## Verificações

- `scripts/finance-usability.test.mjs`: conteúdo/tipo/tamanho dos comprovantes, ausência de reenvio automático, vínculo com lançamento confirmado e preservação do catálogo nas ativações.
- `scripts/finance-f3-route.test.mjs`: permissão antes de consultar chave, persistência protegida e ausência de segredo na resposta.
- `scripts/local-finance-usability-smoke.mjs --local-synthetic`: teste HTTP + Storage no Docker, com conta fictícia; cria conta bancária, vincula lançamento, envia/lista/baixa comprovante privado, recusa arquivo adulterado e acesso indevido, edita/desativa/reativa categoria e recusa versão antiga. Não usa dados de clientes nem provedores externos.
