# Eventos — etapa 2

A etapa 2 adiciona o ciclo de tickets ao cadastro canônico de eventos, preservando a identidade visual da Vinha e o isolamento entre ministérios e igrejas.

## Operação

1. Em Programação, abra o evento e a aba **Tickets e reservas**.
2. Salve o funcionamento: inscrições ativas, visitantes, vagas restantes, prazo de reserva e perguntas por participante. Para pagos e reservas, selecione uma finalidade de eventos com recebimento verificado no Financeiro.
3. Cadastre tipos gratuitos, pagos ou de reserva. Configure quantidade, prazo, limites por comprador/CPF e público. Igrejas selecionadas usam o vínculo confirmado do usuário, não a igreja de conteúdo escolhida enquanto uma transferência está pendente.
4. Se necessário, cadastre cupons em valor ou porcentagem, validade, tipos elegíveis, limite global e um uso por comprador.
5. Publique o evento e divulgue seu link exclusivo. O comprador escolhe os tickets, informa os participantes, confere o total e confirma inscrição, reserva ou pagamento.
6. Acompanhe inscritos em **Inscritos e check-in**. A lista distingue reservas, pagamentos pendentes, confirmações, cancelamentos e conferências. A entrada aceita o código individual somente no intervalo permitido.

A reserva pode ser paga depois no mesmo pedido. A confirmação vem da prova financeira validada pelo provedor; a página de retorno não confirma pagamento. Descontos e classificação financeira ficam registrados no pedido. Um pagamento tardio sem vaga fica em conferência e não emite entrada indevida.

## Preservação e acesso

Eventos com inscrições financeiras anteriores continuam no modelo anterior. A nova configuração não converte pedidos existentes. Inscrições antigas permanecem consultáveis em uma seção própria.

Visitantes só acessam seu pedido com comprovante privado salvo neste navegador. Contas autenticadas acessam seus próprios pedidos em outros dispositivos. Um e-mail informado por visitante não concede vínculo de membro nem acesso a uma conta existente. As tabelas são privadas e as rotas validam identidade e permissões antes de usar processamento privilegiado.

O aplicativo consulta a mesma agenda e recebe o histórico dos novos pedidos. Pagamento e consulta completa abrem o link seguro do evento. As alterações de código Android precisam de uma nova versão instalada/distribuída; publicar a plataforma web não atualiza automaticamente um APK já instalado.

## Validação

- 556 testes da aplicação, 2.748 verificações de dados em 59 arquivos.
- 65 verificações específicas da etapa 2: visitante, vínculo, estoque, reserva, cupom, confirmação financeira, reembolso, pagamento tardio e check-in.
- Disputa concorrente pela última vaga: um vencedor; repetição do pedido não duplica ticket.
- Tipagem da plataforma e Android, build, segredos e ações da interface.
- Fluxo local pelo navegador até QR individual, com dados fictícios. Layout conferido em desktop e largura de 390 px.

A etapa 3 trata a operação ampliada do evento: comunicação segmentada/agendada, interessados, acompanhamento financeiro e procedimentos de cancelamento/reembolso. Esta etapa não envia mensagens a participantes nem executa reembolsos automaticamente.
