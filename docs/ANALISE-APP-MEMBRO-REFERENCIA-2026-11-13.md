# Análise do app do membro (MPR-Igreja) e plano de aprimoramento — 13/11/2026

Base: varredura do código do app (`android-app/`, `shared/`) e da plataforma web, comparada com 52 telas de um app de mercado
enviadas pelo responsável. A referência é usada **só como inspiração funcional** (o que o membro consegue fazer e em quantos toques).
Nomes, textos, ícones e visual seguem a identidade Vinha: não copiar layout, termos ou fluxos idênticos.

## 1. Resumo

- O app da Vinha já cobre a maior parte das funções vistas na referência: agenda, tickets, conteúdos, ao vivo, contribuição,
  carteirinhas, Kids, grupos, oração, testemunhos, anotações, notificações, Bíblia e jornadas.
- Já temos recursos que a referência não mostra: vídeo offline, escalas com repertório e cifra do músico, revisão de cadastro pela
  secretaria, vínculos familiares e transferência entre igrejas.
- A diferença maior está na **experiência**: tela inicial pouco personalizada, conteúdos sem prateleiras, perfil sem "quanto falta
  preencher", carteirinha sem visual de cartão e a área do líder de célula incompleta no celular.
- Lacunas funcionais reais: painel do líder de célula, contribuição recorrente com cartão salvo, arquivos para baixar, páginas
  institucionais (história, células), categorias em oração e testemunhos, restrições no cadastro da criança pelo responsável.

## 2. Comparação por área

| Área | Referência | Vinha hoje | O que falta | Prioridade |
|---|---|---|---|---|
| Início | Saudação com foto, atalhos em círculo, "minha agenda" (tickets e eventos), conteúdos recentes, trilhas em andamento, destaques | Saudação, destaques e publicações | Atalhos escolhidos pela igreja, bloco "minha agenda", "continue de onde parou" (vídeos e jornadas) | Alta |
| Agenda | Próximos eventos, filtro, itens salvos (tickets, programações, eventos favoritos) | Agenda da igreja, inscrições e tickets | Salvar evento e filtro por categoria | Média |
| Conteúdos | Carrossel em destaque, categorias em botões, continuar assistindo, mais vistos, recentes, séries com episódios, Kids | Biblioteca de vídeos com favoritos, progresso e offline | Organização em prateleiras, filtro por categoria, busca, séries e episódios | Alta |
| Contribua | Cartões ilustrados por finalidade (dízimo, oferta, voto), histórico de únicas e recorrentes, cartões salvos | Finalidades, pedido de contribuição e histórico | Cartões ilustrados, contribuição recorrente e cartão salvo (depende do provedor de pagamento) | Média |
| Perfil | Porcentagem preenchida por seção (dados, contato, igreja, documentos, adicionais), troca de foto | Perfil com envio para revisão | Porcentagem e seções, botão "continuar" onde falta | Alta |
| Mais | Lista de atalhos com ícone | Menu "Mais" | Revisar ordem e ícones | Baixa |
| Líder de célula | Painel com relatórios pendentes, material, indicações, aniversariantes e pessoas; participantes e visitantes com WhatsApp; relatório em 3 passos | Encontros e frequência; materiais do grupo | Painel do líder completo no celular, relatório em passos (presentes, visitantes, observações), indicações e aniversariantes | Alta |
| Notificações | Novas e lidas, "ler todas", busca | Caixa de entrada | "Ler todas" e busca (confirmar o que já existe) | Baixa |
| Grupos | Participando, disponíveis e pendentes, com sair | Disponíveis, minhas participações e pedidos | Equivalente: só ajustes visuais | Baixa |
| Carteirinhas | Uma por função, cartão deitado com foto, matrícula, grupo e nascimento; verso com texto da igreja; baixar e compartilhar | Carteirinhas com validade e compartilhar | Visual de cartão, verso configurável pela igreja, baixar como imagem, QR de conferência | Média |
| Configurações | E-mail, política de privacidade, sobre o app, excluir conta, sair | Excluir conta e sair | Política de privacidade, sobre o app e troca de e-mail | Média (exigida pelas lojas) |
| Kids | Reserva, nova criança, check-in e check-out; cadastro em 2 passos com restrição alimentar, alergia, necessidade especial e "fotos não permitidas", cada uma com campo próprio | Reservas, retirada e nova criança para conferência | Restrições e foto no cadastro feito pelo responsável, cadastro em passos | Alta (segurança da criança) |
| Oração | Área do pedido e permissão de contato por WhatsApp | Motivo e meus pedidos | Área ou categoria e consentimento de contato | Média |
| Testemunhos | Categorias e botão de envio | Envio com autorização e nome opcional | Categorias e mural publicado | Baixa |
| Nossa Igreja | Páginas com imagem e texto (história, células) | "Minha igreja local" com dados | Páginas institucionais editadas no painel (o editor de texto formatado já existe) | Média |
| Ao vivo | Cultos fixos e próximas transmissões | Ao vivo, programadas e encerradas | Equivalente | Baixa |
| Downloads | Pastas, categorias e PDFs | Arquivos só no painel (Comunicação › Arquivos) | Biblioteca de arquivos no app | Média |
| Ticket | QR Code grande com dados do evento | Tickets do membro | Conferir se o QR aparece no app; se não, exibir | Alta (uso na entrada) |
| "Como está se sentindo hoje?" | Registro de humor na tela inicial | Não existe | Opcional; é dado sensível (saúde emocional, LGPD): só com consentimento e uso pastoral claro | Avaliar |

## 3. Plano em ondas

**Onda 1 — experiência, sem mudar o banco (1 a 2 semanas)**
1. Nova tela inicial: atalhos definidos pela igreja, "minha agenda" (tickets e próximos eventos), "continue de onde parou", destaques.
2. Conteúdos em prateleiras: destaque, categorias em botões, continuar assistindo, recentes, busca.
3. Ticket com QR Code grande e dados do evento.
4. Carteirinha em formato de cartão, com baixar e compartilhar.
5. Configurações: política de privacidade, sobre o app e troca de e-mail.
6. Notificações: "ler todas" e busca.

**Onda 2 — pequenas mudanças no banco (2 a 3 semanas)**
1. Perfil com porcentagem por seção e atalho para o que falta.
2. Kids: cadastro em passos com restrições, foto e "fotos não permitidas" (alimenta a recepção e as etiquetas).
3. Oração com área e consentimento de contato; testemunhos com categorias.
4. Arquivos para baixar no app (pastas e categorias), reaproveitando Comunicação › Arquivos.
5. Páginas institucionais (história e células) editadas no painel e exibidas no app.
6. Pedido de familiar pelo app (já existe no web).

**Onda 3 — líder de célula no celular (2 semanas)**
Painel do líder com relatórios pendentes, relatório em 3 passos, pessoas com WhatsApp, visitantes, indicações, aniversariantes e
materiais. O banco e o painel web já têm quase tudo; o trabalho é levar para o app.

**Onda 4 — depende de terceiros**
1. Contribuição recorrente e cartão salvo: tokenização do provedor de pagamento, nunca guardar número de cartão.
2. Push real no Android (Firebase).
3. Séries e episódios nos conteúdos (modelo de dados novo).
4. Publicação nas lojas.

## 4. Cuidados

- Identidade própria: textos, ícones e nomes da Vinha; inspiração só funcional.
- O app está sendo trabalhado também por outra ferramenta (ChatGPT). Antes de cada onda, definir quem mexe em cada tela e juntar
  o código pelo GitHub para não haver conflito.
- Dados sensíveis (humor, saúde e restrições da criança, contatos) exigem consentimento e acesso restrito, como já ocorre no Kids.
