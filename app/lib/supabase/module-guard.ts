import {rpc,type OperationsClient} from './operations';
const codes:Record<string,string>={people:'people',terms:'terms',kids:'kids',events:'events',cells:'cells',scales:'scales',worship:'worship',communication:'communication',broadcasts:'broadcasts',finance:'finance',reports:'reports'};
export async function moduleAllowed(client:OperationsClient,organizationId:string,permission:string){const module=codes[permission.split('.')[0]];return !module||await rpc(client,'unit_module_enabled',{p_organization:organizationId,p_module:module})===true}
