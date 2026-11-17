// Área Kids: textos e utilitários usados pela tela principal e pelas abas.
import {formatInZone,panelTimezone,toLocalInput} from '../../shared/timezone';
export const statusLabel:Record<string,string>={draft:'Em preparação',open:'Aberta',closed:'Encerrada',cancelled:'Cancelada',present:'Presente',out:'Retirada confirmada'};
export const roles:Record<string,string>={supervisor:'Supervisão',reception:'Recepção',teacher:'Responsável pela sala',assistant:'Auxiliar'};
// Times in the church's zone (sent with the Kids page).
export const stamp=(v:string|null)=>v?formatInZone(v,panelTimezone()):'—';
// Session times are edited in the church's zone, whatever the device's own zone is.
export const localTime=(v:unknown)=>typeof v==='string'&&v?toLocalInput(v,panelTimezone()):'';
export const secret=()=>Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');
