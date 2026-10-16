type Unit = {id:string;name:string;parent_unit_id?:string|null};

export function unitPreference(units:readonly Unit[],preferred:string|null|undefined,defaultId:string|null):string {
 if(preferred&&units.some(u=>u.id===preferred))return preferred;
 return defaultId&&units.some(u=>u.id===defaultId)?defaultId:'';
}

// An explicit selection must resolve uniquely; never replace it with a default.
export function resolveUnitSelection(units:readonly Unit[],selection:string|undefined,defaultId:string|null):string|null {
 if(selection===undefined||!selection.trim())return defaultId&&units.some(u=>u.id===defaultId)?defaultId:null;
 const value=selection.trim();
 const byId=units.find(u=>u.id===value);
 if(byId)return byId.id;
 const matches=units.filter(u=>u.name.toLocaleLowerCase('pt-BR')===value.toLocaleLowerCase('pt-BR'));
 return matches.length===1?matches[0].id:null;
}

export function validUnitParent(units:readonly Unit[],unitId:string,parentId:string|null):boolean {
 if(parentId===null)return true;
 const byId=new Map(units.map(u=>[u.id,u]));
 const visited=new Set<string>([unitId]);
 let current:string|null|undefined=parentId;
 while(current){
  if(visited.has(current))return false;
  visited.add(current);
  const unit=byId.get(current);
  if(!unit)return false;
  current=unit.parent_unit_id;
 }
 return true;
}
