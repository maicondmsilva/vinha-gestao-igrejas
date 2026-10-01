import type {Json} from './database.types';

export type AccessUnit={id:string;name:string;type:string;parent_unit_id:string|null};
export type AccessMembership={
  membership_id:string;
  organization_id:string;
  organization_name:string;
  organization_slug:string;
  primary_color:string;
  role:string;
  status:string;
  default_unit_id:string|null;
  units:AccessUnit[];
};
export type AccessContext={
  email:string|null;
  preference:{selected_organization_id?:string|null;selected_unit_id?:string|null;theme?:string};
  memberships:AccessMembership[];
};

export function parseAccessContext(value:Json|null):AccessContext{
  if(!value||typeof value!=='object'||Array.isArray(value))return{email:null,preference:{},memberships:[]};
  const raw=value as Record<string,unknown>;
  return{
    email:typeof raw.email==='string'?raw.email:null,
    preference:raw.preference&&typeof raw.preference==='object'&&!Array.isArray(raw.preference)?raw.preference as AccessContext['preference']:{},
    memberships:Array.isArray(raw.memberships)?raw.memberships as unknown as AccessMembership[]:[],
  };
}

export function organizationSlug(value:string){
  return value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,60);
}

