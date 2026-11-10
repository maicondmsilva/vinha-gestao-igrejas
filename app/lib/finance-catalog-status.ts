import {financeCommand} from './finance-f1.ts';
type CatalogStatus={id:string;unit_id:string|null;name:string;kind:string;direction:string|null;parent_id:string|null;version:number;details:Record<string,string>};
/** Preserve identity, classification, banking details and optimistic version on activation changes. */
export function catalogStatusCommand(unitId:string,item:CatalogStatus,active:boolean){
 if(typeof active!=='boolean')throw Error('Confirme a situação do cadastro.');
 const command={action:'catalog',unitId,data:{id:item.id,kind:item.kind,name:item.name,direction:item.direction||'',parent:item.parent_id||'',shared:item.unit_id===null,version:item.version,active,details:{...item.details}}};
 financeCommand(command);return command;
}
