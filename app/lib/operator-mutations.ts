// RLS can return zero changed rows without a database error. Never report that as success.
export function requireOperatorChange(result:{data:unknown;error:{message?:string}|null},missingMessage:string){
 if(result.error)throw new Error(result.error.message?.includes('last active owner')?'É obrigatório manter ao menos um proprietário ativo.':'A alteração não foi permitida para o seu perfil.');
 if(!Array.isArray(result.data)||result.data.length!==1)throw new Error(missingMessage);
}
