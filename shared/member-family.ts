export type FamilyKind='kids'|'cells';
export type FamilyChild={id:string;name:string;birth:string;version:number;can_edit:boolean;can_pickup:boolean;care?:string};
export type FamilyRequest={id:string;kind:string;data?:{name?:string;birth?:string;care?:string};status:string;reason?:string;version:number;name?:string;cell_id?:string};
export type FamilyBooking={id:string;profile_id:string;session_id:string;group_id:string;can_pickup:boolean;status:string;version:number;pickup_requested_at:string|null;session:string;name:string;room:string;starts_at:string;ends_at:string;attendance:'present'|'out'|null;checked_in_at?:string;checked_out_at?:string};
export type FamilyGroup={id:string;name:string;meeting_day:number;meeting_time:string;meeting_format:string;area:string;description:string;joined:boolean;location:string;can_report:boolean};
export type FamilySession={id:string;name:string;starts_at:string;ends_at:string;room:string;class_name:string;available:number};
export type FamilyPage={children?:FamilyChild[];reservations?:FamilyBooking[];requests?:FamilyRequest[];presence?:{id:string;name:string;session:string;room:string;status:string;checked_in_at:string;checked_out_at:string|null}[];items?:FamilyGroup[];exits?:FamilyRequest[];materials?:{id:string;title:string;body:string;url:string}[];more?:boolean};
export const familyStatus:Record<string,string>={pending:'Aguardando revisão',approved:'Aprovada',rejected:'Não aprovada',cancelled:'Cancelada',accepted:'Participação aprovada',reserved:'Reserva registrada',present:'Recebida pela equipe',out:'Retirada confirmada'};
export const familyDays=['Domingo','Segunda-feira','Terça-feira','Quarta-feira','Quinta-feira','Sexta-feira','Sábado'];
export const familyDate=(s:string|null|undefined)=>s?new Intl.DateTimeFormat('pt-BR',{dateStyle:'short',timeStyle:'short',timeZone:'America/Sao_Paulo'}).format(new Date(s)):'—';
export function familyError(message=''){
 if(/local_membership/.test(message))return 'Este serviço usa a igreja do seu cadastro oficial. Para mudar o vínculo, solicite a transferência e aguarde a aprovação.';
 if(/identity_pending/.test(message))return 'A igreja precisa conferir o vínculo da sua conta com o cadastro de Pessoas.';
 if(/changed|conflict|23505/.test(message))return 'O registro mudou ou já existe uma solicitação pendente. Atualize antes de tentar novamente.';
 if(/full|capacity/.test(message))return 'Não há vaga disponível nesta sala. Atualize a consulta.';
 if(/already_received/.test(message))return 'A entrada já foi registrada. Procure a equipe para acompanhar a sessão.';
 if(/age/.test(message))return 'Confira a data de nascimento e a faixa etária da turma. O responsável precisa ser maior de idade.';
 if(/closed/.test(message))return 'A sessão não está mais disponível para reservas.';
 if(/denied|42501/.test(message))return 'Serviço indisponível para esta conta ou igreja. Confira seu vínculo e as autorizações com a equipe.';
 if(/verification|mismatch|invalid|220/.test(message))return 'Revise os campos e a conferência do cadastro antes de confirmar.';
 return 'Não foi possível confirmar a operação. Atualize antes de repetir.';
}
