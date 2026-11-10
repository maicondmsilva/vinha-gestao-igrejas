type HierarchyError={code?:string;message?:string}|null|undefined;
const messages:Record<string,string>={
 invalid_decision:'Escolha aceitar ou recusar o vínculo.',
 invalid_request:'Selecione uma solicitação válida.',
 invalid_hierarchy:'Confira a sede, a igreja filha e a forma de pagamento.',
 invalid_action:'Esta operação de hierarquia não está disponível.',
 use_hierarchy_request:'Crie uma solicitação para que os dois responsáveis aprovem o vínculo.',
 hierarchy_organization_unavailable:'Os dois ministérios precisam estar ativos ou em demonstração para esta operação.',
 hierarchy_previous_approval_unavailable:'O responsável pelo primeiro aceite perdeu o acesso necessário. Um gestor desse ministério precisa renovar o aceite.',
 child_already_linked:'Esta igreja já possui uma sede vinculada.',
 hierarchy_cycle:'Este vínculo criaria um ciclo na hierarquia.',
 request_not_found:'Solicitação não encontrada ou não autorizada para este ministério.',
 link_not_found:'O vínculo já foi encerrado ou não foi encontrado.',
 hierarchy_link_unavailable:'O vínculo não está ativo ou os ministérios não estão disponíveis para consulta.',
 hierarchy_pending_request:'Já existe uma solicitação pendente para esta igreja filha.',
};
export function hierarchyError(error:HierarchyError){
 if(error?.code==='40001'||error?.code==='40P01'||error?.code==='55P03')return {status:409,message:'A hierarquia ou as permissões mudaram durante a operação. Atualize a página e tente novamente.'};
 if(error?.message&&Object.hasOwn(messages,error.message))return {status:error.code==='42501'?403:409,message:messages[error.message]};
 if(error?.code==='42501')return {status:403,message:'Você não possui mais permissão para esta operação. Atualize seu acesso.'};
 return {status:400,message:'Não foi possível concluir a operação de hierarquia. Atualize a página e tente novamente.'};
}
export function validHierarchyDecision(value:unknown):value is 'approve'|'reject'{return value==='approve'||value==='reject'}
export function hierarchyAcceptanceMessage(result:{status?:string;renewalRequired?:boolean}){
 if(result.status==='approved')return 'Vínculo aprovado e ativado.';
 if(result.status==='rejected')return 'Solicitação recusada. Nenhum vínculo foi ativado.';
 if(result.renewalRequired)return 'Seu aceite foi registrado. O outro ministério precisa renovar o aceite anterior para ativar o vínculo.';
 return 'Seu aceite foi registrado. Aguardando o outro ministério.';
}
