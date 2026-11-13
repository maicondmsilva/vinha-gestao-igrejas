/** "Minha célula" (app do líder): regras puras usadas pela tela e pelos testes. */
export type LeaderPerson = {participantId: string; name: string; phone: string; birthday: string; since: string; recent: boolean[]};
export type LeaderMeeting = {
  id: string;
  topic: string;
  date: string;
  time: string;
  status: string;
  version: number;
  notes: string;
  expected: number;
  present: number;
  visitors: number;
  roster: {participantId: string; name: string; present: boolean}[];
};
export type LeaderVisitor = {id: string; name: string; phone: string; date: string};
export type LeaderReferral = {id: string; name: string; version: number; linked: boolean};
export type LeaderMaterial = {id: string; title: string; body: string; url: string};
export type LeaderOverview = {
  cell: {id: string; name: string; day: number; time: string; format: string; location: string};
  canReport: boolean;
  today: string;
  people: LeaderPerson[];
  meetings: LeaderMeeting[];
  visitors: LeaderVisitor[];
  referrals: LeaderReferral[];
  materials: LeaderMaterial[];
};

export const weekDays = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];

/** Só dígitos; aceita número digitado com máscara. Vazio se não parecer telefone. */
export function phoneDigits(raw: string) {
  const d = (raw || '').replace(/\D/g, '');
  return d.length >= 8 && d.length <= 15 ? d : '';
}

/** Link do WhatsApp; números brasileiros (DDD + número) ganham o 55 na frente. */
export function whatsappLink(phone: string, text = '') {
  let d = phoneDigits(phone);
  if (!d) return '';
  if (d.length === 10 || d.length === 11) d = '55' + d;
  return 'https://wa.me/' + d + (text ? '?text=' + encodeURIComponent(text) : '');
}

/** Dias até o próximo aniversário (0 = hoje). `birthday` no formato MM-DD, `today` AAAA-MM-DD. */
export function daysToBirthday(birthday: string, today: string) {
  const m = /^(\d{2})-(\d{2})$/.exec(birthday || ''),
    t = /^(\d{4})-(\d{2})-(\d{2})$/.exec(today || '');
  if (!m || !t) return -1;
  const base = Date.UTC(+t[1], +t[2] - 1, +t[3]);
  const at = (y: number) => {
    const month = +m[1] - 1,
      day = +m[2];
    const d = new Date(Date.UTC(y, month, day));
    return d.getUTCMonth() === month ? d.getTime() : Date.UTC(y, month, 28);
  };
  let next = at(+t[1]);
  if (next < base) next = at(+t[1] + 1);
  return Math.round((next - base) / 86400000);
}

/** Aniversariantes dos próximos `days` dias, do mais próximo ao mais distante. */
export function upcomingBirthdays(people: LeaderPerson[], today: string, days = 30) {
  return people
    .map((p) => ({...p, inDays: daysToBirthday(p.birthday, today)}))
    .filter((p) => p.inDays >= 0 && p.inDays <= days)
    .sort((a, b) => a.inDays - b.inDays || a.name.localeCompare(b.name));
}

/** Pessoa que faltou aos dois últimos encontros registrados merece um contato. */
export function needsCare(p: LeaderPerson) {
  return p.recent.length >= 2 && !p.recent[0] && !p.recent[1];
}

/** Frequência média dos encontros concluídos (0–100), ou null sem dados. */
export function attendanceRate(meetings: LeaderMeeting[]) {
  const done = meetings.filter((m) => m.status === 'completed' && m.expected > 0).slice(0, 4);
  if (!done.length) return null;
  return Math.round((100 * done.reduce((s, m) => s + m.present, 0)) / done.reduce((s, m) => s + m.expected, 0));
}

/** Encontros que já aconteceram e ainda esperam o relato do líder. */
export function pendingMeetings(meetings: LeaderMeeting[], today: string) {
  return meetings.filter((m) => m.status === 'scheduled' && m.date <= today).sort((a, b) => a.date.localeCompare(b.date));
}

export function shortDate(iso: string) {
  const [y, m, d] = (iso || '').split('-');
  return d && m ? d + '/' + m + (y && y !== String(new Date().getFullYear()) ? '/' + y : '') : '';
}
export const monthShort = ['JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN', 'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ'];
export function initials(name: string) {
  return (
    (name || '')
      .trim()
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((w) => w[0]!.toUpperCase())
      .join('') || '?'
  );
}

export function leaderError(message: string) {
  if (/version_conflict/.test(message)) return 'Alguém atualizou este encontro agora há pouco. Atualize e tente de novo.';
  if (/link_member_before_accept/.test(message)) return 'Esta indicação ainda não tem cadastro na igreja. Peça à secretaria para vincular a pessoa.';
  if (/access_denied/.test(message)) return 'Você não tem acesso de liderança a esta célula.';
  if (/invalid_cell_leader/.test(message)) return 'Confira os dados: nomes com pelo menos 2 letras, telefone só com números e encontro já realizado.';
  return 'Não foi possível concluir agora. Tente de novo.';
}
