# Kids, termos de consentimento, fotos e app Vinha Equipe: análise e plano (14/11/2026)

## 1. Correções feitas agora no app do membro

| Problema | Causa | Correção |
|---|---|---|
| Início mostra "visitante" mesmo logado | O nome só vinha do cadastro **aprovado**; enquanto a igreja analisa, ficava vazio | O nome vem do cadastro aprovado, do último envio ou dos dados da criação da conta |
| Perfil "perde" o que foi preenchido | O formulário recarregava vazio enquanto o cadastro estava em análise ou recusado. O que foi digitado e não enviado não era guardado | O formulário volta com o último envio, e o rascunho fica salvo no aparelho até o envio |

## 2. Termo de consentimento com autenticação

**Hoje:** existe um módulo antigo de termos (banco legado, desativado) com textos de dados pessoais, imagem, comunicações e responsável por menor. No Supabase **não há registro de aceite**. No Kids, "Uso de imagem" é só uma opção dentro do texto de cuidados.

**Proposta:**
- **Modelos por igreja e com versão**, editados no painel (Igreja › Termos). Cada aceite fica preso ao texto exato daquela versão.
  - Adultos: "Tratamento de dados", "Uso de imagem e voz" e "Comunicações".
  - Kids: "Responsável pela criança" e "Imagem da criança", com as opções fotos, vídeos, redes sociais e transmissões.
- **Aceite no app:**
  - **adulto:** ao enviar o cadastro;
  - **responsável:** ao cadastrar a criança, com um termo para cada criança.
  - O membro lê, marca o que autoriza e confirma digitando o próprio nome.
- **Autenticação automática do documento:**
  - O servidor monta o documento com o texto, a versão, os nomes, o CPF parcial, a data e hora, o aparelho e a conta.
  - Calcula a **impressão digital SHA-256** do documento e gera um **código de verificação**, por exemplo VNH-7K2Q-9MXA.
  - O **PDF** traz o código, a impressão digital e um **QR Code** para a página pública **vinhaigrejas.com.br/verificar/CÓDIGO**. Ela confirma que o documento é autêntico e não foi alterado, sem mostrar dados sensíveis.
  - É uma assinatura eletrônica simples (Lei 14.063/2020, art. 4º, I). Para valer como assinatura qualificada seria preciso certificado ICP-Brasil, que fica fora do escopo.
- **Vínculo com o cadastro:** em Pessoas, a ficha do membro e a da criança mostram os termos aceitos (versão, data, código e PDF). A revogação fica registrada e vale daqui em diante.
- **Uso pela equipe:** a autorização de imagem aparece para a recepção do Kids e na etiqueta, por exemplo "Sem fotos".

## 3. Fotos de perfil

**Hoje:** o cadastro de pessoas já tem o campo da foto (`people.photo_path`), mas nem o app nem o Kids enviam fotos.

**Proposta:**
- **No app:** foto no "Meu perfil" e já na etapa "Sobre você" do cadastro. O membro tira ou escolhe a foto e ela é recortada em formato quadrado e reduzida.
- **Armazenamento:** a foto fica num espaço privado do Supabase e só é mostrada por link temporário.
  - Enquanto o cadastro está em análise, a foto fica com a conta.
  - Quando a igreja aprova, ela **migra para o cadastro de membros**.
- **No Kids:** foto da criança no cadastro feito pelo responsável. Ela ajuda a recepção na conferência e na retirada.
- **No início:** a foto aparece ao lado do nome ("Que bom ter você aqui, Maicon"). Também aparece no botão do perfil, no lugar da inicial.

## 4. Kids: chamar o responsável pela sala

**Proposta:** o líder ou monitor da sala, no **Vinha Equipe**, toca na criança e em "Chamar responsável", escolhendo o motivo (troca de fralda, choro, saúde, buscar mais cedo ou outro).
- O responsável recebe **na hora** um aviso no app da igreja, na caixa de notificações. Quando o Firebase for ativado, recebe também um push.
- O responsável responde "Estou indo" e a equipe vê a resposta.
- Tudo fica no histórico da sessão Kids. Quem pode chamar segue as permissões da turma (`kids.checkin`).

### Situação (14/11)
- Banco: `kids_call` (equipe) e `member_kids_call` (responsável). Uma chamada a cada 2 minutos enquanto não houver resposta. Fica registrado na auditoria.
- Vinha Equipe: tela **Sala Kids**, com as crianças presentes por sala e o botão **Chamar**.
- App da igreja: aviso no topo com **Estou indo** e **Vi o recado**, e o chamado também na caixa de notificações.
- Voluntários com papel de membro já entram no Vinha Equipe e veem só as tarefas que o banco libera.

## 5. App Vinha Equipe: como está e o que falta

**Hoje:**
- entrada com conta, escolha do ministério e da igreja (só onde a pessoa tem acesso);
- **Validar entrada** (QR Code de ingressos e inscrições);
- **Enviar push**;
- funções do Kids prontas no código (estação, quadro da sessão, entrada e saída), mas **sem tela**.

Hoje o acesso usa duas chaves antigas (`checkin` e `push`). Ele precisa usar o **mesmo catálogo de permissões do painel**.

| Área | O que falta no Vinha Equipe | Prioridade |
|---|---|---|
| Acesso | Mostrar só o que cada permissão libera (catálogo do painel, por igreja e por turma ou célula). Trocar de ministério e de igreja | Alta |
| Kids | Recepção (entrada e saída com conferência do responsável), quadro da sala, **chamar responsável**, ocorrências, foto e restrições da criança | Alta |
| Mídia e comunicação | Publicar aviso, banner e vídeo com fotos da galeria; transmissão (marcar ao vivo ou encerrada); push | Alta |
| Escalas e louvor | Minha escala do dia, presença da equipe, repertório e cifras do culto | Média |
| Agenda pastoral e células | Já existem no app do membro para quem atende ou lidera; levar também para o Equipe | Média |
| Eventos | Lista de inscritos e check-in manual sem QR | Média |
| Notificações para a equipe | Avisos internos (escala trocada, pedido pastoral, chamado Kids) | Depende do Firebase |

## 6. Etapas anteriores que entram neste plano

- Push real no Android (Firebase).
- Contribuição recorrente com cartão salvo (provedor de pagamento).
- Carteirinha: baixar como imagem e verso definido pela igreja.
- Escalas E1–E3: painel da semana, calendário e quadro de montagem.
- Revisão jurídica de /privacidade e /termos.
- Publicação nas lojas.
- SMTP próprio na homologação.

## 7. Ordem de desenvolvimento

| Fase | Entrega |
|---|---|
| 1 | Correções do app do membro (nome e perfil), já feitas |
| 2 | Fotos: perfil no app, no cadastro e no início, foto da criança no Kids e migração para Pessoas, já feitas |
| 3 | Termos com autenticação: modelos no painel, aceite no app (adulto e Kids), PDF com código e QR, página /verificar e ficha em Pessoas, já feitos |
| 4 | Kids no Vinha Equipe: quadro da sala e chamar responsável (aviso no app do responsável), já feitos. Falta a recepção (entrada e saída) no Equipe |
| 5 | Vinha Equipe: permissões pelo catálogo do painel, mídia e comunicação, escala do dia |
| 6 | Pendências: Firebase, carteirinha, escalas, lojas |
