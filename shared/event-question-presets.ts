import type {TicketQuestion} from './event-tickets';
export const ticketQuestionPresets:{key:string;question:Omit<TicketQuestion,'id'>;hint:string}[]=[
 {key:'shirt',question:{label:'Tamanho da camiseta',kind:'select_other',required:true,options:['PP','P','M','G','GG','XG','XGG']},hint:'Tamanhos prontos e opção Outro para escrever.'},
 {key:'birth',question:{label:'Data de nascimento',kind:'date',required:false,options:[]},hint:'Data do participante.'},
 {key:'church',question:{label:'Igreja do participante',kind:'text',required:false,options:[]},hint:'Nome da igreja em texto livre.'},
 {key:'meal',question:{label:'Opção de alimentação',kind:'select_other',required:false,options:['Tradicional','Vegetariana','Vegana']},hint:'Lista de opções com espaço para outra escolha.'},
 {key:'companion',question:{label:'Participará com acompanhante?',kind:'boolean',required:false,options:[]},hint:'Resposta Sim ou Não.'},
 {key:'notes',question:{label:'Observações para a organização',kind:'text',required:false,options:[]},hint:'Campo livre para informações necessárias ao evento.'},
];
export const ticketOtherPrefix='Outro: ';
export function ticketQuestionSelection(q:TicketQuestion,value:string){return q.kind==='select_other'&&value.startsWith(ticketOtherPrefix)?'__other__':value}
export function ticketQuestionOther(value:string){return value.startsWith(ticketOtherPrefix)?value.slice(ticketOtherPrefix.length):''}
