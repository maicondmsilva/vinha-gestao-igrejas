export type ChurchTransfer={id:string;source_unit:string;target_unit:string;status:'pending'|'approved'|'rejected'|'cancelled';reason:string;created_at:string};
export type ChurchState={ok:boolean;selectedUnit:string|null;officialUnit:string|null;canRequest:boolean;transfers:ChurchTransfer[]};
export type PublicPost={id:string;kind:string;title:string;body:string;url:string;created_at:string};
export type ChurchRpc={rpc:(name:string,args:Record<string,unknown>)=>PromiseLike<{data:unknown;error:{code?:string;message:string}|null}>};
export const churchStatus={pending:'Aguardando aprovação',approved:'Transferência aprovada',rejected:'Transferência recusada',cancelled:'Solicitação cancelada'};
export function churchError(message:string){
 if(message.includes('member_transfer_access_review'))return 'Este usuário tem cargos ou acessos específicos. Revise-os em Usuários e permissões antes de aprovar a transferência.';
 if(message.includes('member_request_pending'))return 'Há uma solicitação pendente. Aguarde a revisão ou cancele a solicitação de transferência.';
 if(message.includes('member_request_changed')||message.includes('member_transfer_identity'))return 'O vínculo mudou ou exige conferência. Atualize a consulta e procure a administração.';
 return 'Não foi possível confirmar. Atualize a consulta antes de repetir.';
}
export function publicLink(value:string){try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password?u.href:null}catch{return null}}
