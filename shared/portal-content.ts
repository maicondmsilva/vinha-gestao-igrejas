// Portal da Vinha: guia de cada módulo (texto e vídeo). Construído módulo a módulo, conforme cada análise é concluída.
export type PortalSection = {id: string; title: string; text: string[]; steps?: string[]; tip?: string};
export type PortalModule = {
  id: string;
  title: string;
  icon: string;
  summary: string;
  status: 'pronto' | 'em breve';
  /** Endereço do vídeo (YouTube ou Vimeo). Vazio: o vídeo ainda está em gravação. */
  video?: string;
  sections: PortalSection[];
};

export const portalModules: PortalModule[] = [
  {
    id: 'pessoas',
    title: 'Pessoas',
    icon: '♙',
    status: 'pronto',
    summary: 'O cadastro único de membros, pessoas em integração, visitantes e crianças da igreja, ligado ao app da igreja e ao Vinha Equipe.',
    video: '',
    sections: [
      {
        id: 'visao',
        title: 'Para que serve',
        text: [
          'Pessoas é o coração da Vinha: cada pessoa tem um único cadastro, usado por todos os outros módulos (Kids, Células, Escalas, Eventos, Financeiro e o app da igreja).',
          'O que o membro atualiza pelo app chega para a secretaria conferir; o que a secretaria aprova aparece no app.',
        ],
      },
      {
        id: 'configurar',
        title: 'Antes de começar',
        text: ['Três ajustes deixam o módulo pronto para uso.'],
        steps: [
          'Em Configurações › Igrejas e unidades, confira as igrejas (sede e filiais). Cada pessoa pertence a uma igreja.',
          'Em Configurações › Usuários e permissões, dê a cada pessoa da equipe o que ela pode ver e editar em Pessoas (membros, visitantes, notas pastorais).',
          'Em Pessoas › Termos, revise os textos de privacidade e uso de imagem e crie os termos próprios da igreja, se precisar.',
        ],
      },
      {
        id: 'cadastrar',
        title: 'Cadastrar uma pessoa',
        text: ['Use “Nova pessoa”. O cadastro tem quatro etapas: dados pessoais, família e endereço, vida na igreja e privacidade.'],
        steps: [
          'Preencha o nome completo e a data de nascimento: a idade aparece ao lado.',
          'Escolha a etapa: Membro, Em integração, Visitante ou Criança.',
          'Em Família, ligue a pessoa a parentes já cadastrados (cônjuge, filhos, pais…). O vínculo aparece no cadastro dos dois.',
          'Na última etapa, registre os consentimentos. A assinatura eletrônica com PDF é feita pelo próprio membro no app.',
        ],
        tip: 'Muitas pessoas de uma vez? Use “Importar planilha”.',
      },
      {
        id: 'etapas',
        title: 'Etapas da jornada',
        text: [
          'Visitante: veio aos cultos ou pelo QR de visitantes. Em integração: está sendo acompanhado. Membro: faz parte da igreja.',
          'Criança: definida automaticamente quando a criança ganha ficha no Kids (pelo app ou pela recepção). O círculo da criança tem um anel dourado e o selo K; o número aparece com a marca “Kids”.',
        ],
      },
      {
        id: 'lista',
        title: 'Lista, busca e filtros',
        text: [
          'Os cartões no topo contam Todos, Membros, Em integração, Visitantes e Crianças; tocar num cartão filtra a lista.',
          'Em “Filtros” há célula, rede, ministério, cargo, gênero, faixa etária, batismo, marcador, “só liderança” e novos convertidos. Marque pessoas para mudar a etapa em lote, aplicar marcador ou enviar um comunicado no app.',
          '“Exportar Excel” gera a planilha com os filtros escolhidos.',
        ],
      },
      {
        id: 'ficha',
        title: 'A ficha da pessoa',
        text: [
          'Toque no nome para abrir a ficha: foto (enviada pelo app), contato, dados pessoais com a idade, família, vida na igreja, termos assinados, visitas, arquivos privados e histórico.',
          'A observação pastoral só aparece para quem tem essa permissão.',
        ],
      },
      {
        id: 'familia',
        title: 'Família e crianças',
        text: [
          'Quando o responsável cadastra uma criança pelo app, ele informa o que é dela (pai ou mãe, avô ou avó, tio ou tia, irmão, padrasto ou madrasta, responsável legal ou “outro”).',
          'Se for parente, a criança entra automaticamente na família dele: o vínculo aparece na ficha dos dois. Se for “outro” (amigo da família, vizinho), a pessoa só fica autorizada a buscar a criança no Kids.',
          'O mesmo vale quando o responsável adiciona outros responsáveis (fixos ou temporários) pelo app.',
          'A criança já fica ativa e pode entrar na sala; a secretaria confere o cadastro e os vínculos em Kids › Crianças › Para conferir.',
        ],
      },
      {
        id: 'cargos',
        title: 'Cargos e funções',
        text: [
          'Cargo é o que a pessoa é na igreja (Pastor ou Pastora, Presbítero, Diácono ou Diaconisa, Missionário…); uma pessoa pode ter vários ao mesmo tempo. A igreja escolhe como chamar (Cargo, Título, Ofício) e cria os seus próprios em Configurações › Cargos e funções.',
          'Função é o que a pessoa faz em um grupo: Líder, Vice-líder, Anfitrião ou Participante numa célula; Supervisor ou Pastor de rede numa rede; Líder ou Integrante num ministério. O antigo campo de texto “Grupo / ministério” deu lugar à busca dos grupos cadastrados.',
          'Funções de liderança sugerem um acesso limitado ao próprio grupo (a célula, a rede ou as escalas do ministério). O acesso só vale depois que o dono ou um administrador confirma em Configurações › Cargos e funções › Acessos sugeridos; quando a pessoa deixa a função, a retirada também é proposta.',
          'No app, cada membro vê as suas funções no perfil e a carteirinha mostra o cargo. A página Liderança da igreja lista pastores e líderes com botão de mensagem; o telefone só aparece se o próprio líder autorizar.',
        ],
        steps: [
          'Em Configurações › Cargos e funções, revise os cargos sugeridos, ajuste os nomes e a ordem (é a ordem da página Liderança).',
          'Em Funções nos grupos, confira o acesso sugerido de cada função de liderança.',
          'Em Ministérios, ligue cada ministério às suas equipes de escala (Louvor › Banda, Vocal…).',
          'Na ficha ou no cadastro da pessoa, adicione os cargos e os grupos com a função.',
          'Em Conferir grupos antigos, vincule os cadastros que tinham o grupo escrito à mão.',
        ],
        tip: 'Líder definido no módulo Células ou supervisor definido em Redes já aparecem como função automaticamente.',
      },
      {
        id: 'termos',
        title: 'Termos de consentimento',
        text: [
          'Há quatro termos padrão (dados pessoais, imagem do adulto, responsável pela criança e imagem da criança) e a igreja pode criar outros em “Novo termo”, para adultos ou para crianças (retiro, passeio, viagem…).',
          'O membro assina no app; cada assinatura gera um PDF com código de verificação. Publicar um novo texto cria uma nova versão sem alterar o que já foi assinado. “Retirar do app” encerra um termo da igreja mantendo os aceites antigos.',
        ],
      },
      {
        id: 'ferramentas',
        title: 'Outras ferramentas',
        text: [
          'Aniversariantes: do dia, da semana e do mês, com atalho de mensagem.',
          'Duplicados: encontra cadastros repetidos e une os dois sem perder histórico.',
          'QR de visitantes: cartaz com QR Code para o visitante se cadastrar sozinho.',
        ],
      },
      {
        id: 'integracao',
        title: 'Integração Visitante',
        text: [
          'Integração Visitante (antes “Novos convertidos”) acompanha quem chegou à igreja, convertido ou não. A decisão de fé é registrada à parte da etapa: ainda não se decidiu, decidiu-se nesta igreja (com a data), reconciliação ou já convertido vindo de outra igreja (com o nome da igreja).',
          'Cada pessoa tem um acompanhante, que recebe aviso no app e encontra a área Integração Visitante para ligar, mandar mensagem, registrar cada contato e mudar a etapa (contato feito, em uma célula, integrado, sem retorno).',
          'Os indicadores mostram as decisões do mês, quantos já vieram de outra igreja e quem está há mais de 7 dias sem contato.',
        ],
        steps: [
          'Em Pessoas › Integração Visitante, use “Incluir na integração” e escolha a decisão de fé.',
          'Em “Acompanhar”, escolha quem acompanha e a data do próximo contato.',
          'Use “Registrar contato” depois de cada ligação, visita ou encontro: o registro entra no Histórico de atendimento da pessoa.',
        ],
      },
      {
        id: 'agenda',
        title: 'Agenda pastoral e relatório de atendimento',
        text: [
          'Quem atende define horários, datas específicas, bloqueios e as regras: quem pode pedir pelo app (todos, só líderes, só a própria célula ou rede, ou só por convite), antecedência mínima, limite de pedidos, máximo de atendimentos por dia e intervalo entre atendimentos.',
          'Todo agendamento respeita a disponibilidade, inclusive quando é o próprio atendente ou a secretaria que marca. Quem atende também é atendido: o horário fica ocupado nos dois papéis.',
          'Quando o atendente convida um membro, ele recebe a notificação no app e aceita, recusa ou pede outro horário. Sem resposta, o horário é liberado 12 h antes. Há lembrete 24 h antes.',
          'Depois do atendimento, o atendente preenche o relatório (resumo, assuntos, oração, encaminhamentos e próximo contato) e escolhe quem pode ler: Equipe pastoral, Restrito ou Sigiloso. O membro nunca vê o relatório; toda leitura fica registrada e, depois de 7 dias, o texto trava e só aceita complemento.',
        ],
        steps: [
          'Em Configurações › Usuários e permissões, dê a quem precisa: “Histórico de atendimento (sem conteúdo)”, “Relatórios de atendimento”, “Relatórios restritos” ou “Relatórios sigilosos”. Mesmo um pastor só lê com a permissão.',
          'Em Pessoas › Agenda pastoral › Quem atende › Configurar, ajuste horários e regras.',
          'No Calendário, as cores mostram: confirmado, aguardando aceite, pedido para decidir, relatório pendente e realizado.',
        ],
        tip: 'No app, “Minha agenda de atendimento” mostra os próximos 14 dias com atendimentos, convites, relatórios pendentes e contatos de integração.',
      },
      {
        id: 'app',
        title: 'Integração com o app da igreja e o Vinha Equipe',
        text: [
          'No app da igreja, o membro preenche o próprio cadastro, envia a foto, assina os termos e cadastra as crianças; os pedidos chegam para a secretaria em Pessoas (perfis pendentes).',
          'No Vinha Equipe, a equipe cadastra visitantes na hora e opera o Kids com as mesmas fichas.',
        ],
      },
    ],
  },
  {id: 'kids', title: 'Área Kids', icon: '★', status: 'em breve', summary: 'Salas, turmas, sessões, entrada e retirada com QR, telão e responsáveis.', sections: []},
  {id: 'celulas', title: 'Células', icon: '◎', status: 'em breve', summary: 'Células, redes, encontros, visitantes e relatórios.', sections: []},
  {id: 'escalas', title: 'Escalas', icon: '✓', status: 'em breve', summary: 'Equipes, cultos, quadro de montagem e confirmações.', sections: []},
  {id: 'programacao', title: 'Programação', icon: '▦', status: 'em breve', summary: 'Agenda, eventos, inscrições e tickets.', sections: []},
  {id: 'comunicacao', title: 'Comunicação', icon: '◌', status: 'em breve', summary: 'Avisos, push, vídeos e páginas da igreja.', sections: []},
  {id: 'financeiro', title: 'Financeiro', icon: 'R$', status: 'em breve', summary: 'Lançamentos, contas, conciliação, recebimentos e Contribua no app.', sections: []},
];

/** Endereço de incorporação do vídeo (YouTube ou Vimeo) ou vazio. */
export function portalEmbed(url = '') {
  const yt = /(?:youtube\.com\/(?:watch\?v=|embed\/|live\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/.exec(url);
  if (yt) return 'https://www.youtube-nocookie.com/embed/' + yt[1];
  const vm = /vimeo\.com\/(\d+)/.exec(url);
  if (vm) return 'https://player.vimeo.com/video/' + vm[1];
  return '';
}
