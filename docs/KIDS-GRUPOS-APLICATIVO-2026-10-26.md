# Área Kids e Grupos Vida no aplicativo

Entrega de 26/10/2026 para portal do membro e Android personalizado. Reutiliza Pessoas, os vínculos Kids e o módulo de células do ministério, com escopo por igreja local. Não há um segundo cadastro mestre de crianças ou participantes.

## Área Kids

O membro vê somente crianças com vínculo aprovado e vigente. A consulta respeita a igreja do cadastro oficial; acompanhar conteúdo de outra igreja não transfere vínculos ou autorizações.

- Solicitar cadastro infantil e atualização de nome, nascimento e orientações de cuidado. O envio fica pendente e não autoriza retirada.
- A administração confere identidade e vínculo. Ao aprovar um novo cadastro, pode selecionar um perfil infantil existente, evitando duplicação, ou criar Pessoas + perfil Kids + responsável em uma transação.
- A aprovação de vínculo novo concede edição e retirada ao responsável explicitamente conferido. As telas identificam essa consequência. Cuidados existentes são preservados quando se vincula uma criança já cadastrada.
- Pedidos de alteração guardam as versões do perfil e dos cuidados; uma revisão antiga não sobrescreve mudanças posteriores.
- Consultar sessões abertas compatíveis com a faixa etária, reservar e cancelar antes do recebimento físico. Há uma reserva por criança/sessão.
- A capacidade considera presenças e reservas. Entradas presenciais e transferências não podem ocupar vagas reservadas por outras famílias. Transações com snapshot antigo falham por serialização.
- Acompanhar entradas e saídas confirmadas pela equipe. O aplicativo do responsável não chama funções de custódia nem recebe a chave de retirada.
- Solicitar retirada à administração; a criança permanece presente até a equipe conferir identidade, autorização vigente e comprovante.

A fila nova de reservas e pedidos de retirada é administrativa. Ela não amplia os acessos de contas de recepção por escala. O módulo presencial K2 mantém suas verificações existentes de equipe, sala, capacidade, bloqueio de retirada, comprovante, recuperação assistida e aceite de transferência.

## Grupos Vida e células

- Catálogo de grupos que a igreja escolheu publicar, com região, apresentação, dia e horário. Busca por nome/região e dia na página atual; paginação disponível.
- Endereço interno fica disponível apenas a participantes. Listas de pessoas e dados de contato não são publicados no buscador.
- Solicitar participação gera uma indicação no módulo Células → Indicações. A aprovação existente inclui a pessoa no grupo; o aplicativo não se autoaprova nem concede função de liderança.
- Consultar materiais publicados de sua igreja e rede após aprovação da participação.
- Solicitar saída, com revisão administrativa e preservação do histórico de participação.
- Liderança já autorizada pode consultar encontros e registrar frequência no aplicativo, usando o snapshot de participantes e as versões do módulo existente. Janela de consulta: últimos 90 dias e próximos 30; encontros são paginados. A gestão completa permanece acessível pelo painel.
- Decisões de solicitações são incluídas na caixa privada de notificações, preservando as notificações anteriores.

## Gestão

Configurações → Serviços e segurança → Área Kids e Grupos Vida no aplicativo: solicitações infantis, reservas/retirada, publicação dos grupos e pedidos de saída. O módulo Área Kids passa a abrir a operação integrada K2, com acesso ao cadastro K1.

Nenhum grupo real é publicado automaticamente e nenhuma autorização real de criança é criada pela implantação.

## Validação

- 62 testes SQL da integração: isolamento, identidade, autorizações, reservas, revisão, conflitos de versão, custódia assistida, materiais e participação.
- 83 testes SQL da operação K2 e testes de concorrência em read committed, repeatable read e serializable.
- Concorrência de duas famílias pela última vaga: capacidade preservada, inclusive com snapshot anterior.
- 18 testes de regressão de Android/K2 e quatro testes novos de contratos/rota/privacidade.
- Tipagem web/Android, verificação de segredos e lint private/public sem achados.

Os testes usam dados fictícios locais. Uma confirmação visual de aprovação persistente do cadastro fictício permaneceu sujeita à autorização específica solicitada ao usuário pela revisão automática; os testes SQL desse fluxo foram executados em transações revertidas.

O Android é entregue como APK interno de teste. A disponibilização na loja segue a preparação de assinatura e publicação do aplicativo de cada ministério.
