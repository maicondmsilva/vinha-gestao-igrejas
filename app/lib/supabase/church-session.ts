import {createSupabaseRequestClient} from './request';
import {parseAccessContext} from './access';
import {tenantHint} from './tenant-hint';
import {selectActiveMembership} from '../access-security';
import type {ChurchSession} from '../../api/_auth';

export async function supabaseChurchSession(request:Request):Promise<ChurchSession|null>{
 const client=createSupabaseRequestClient(request),{data:{user},error:userError}=await client.auth.getUser();if(userError||!user)return null;
 const {data,error}=await client.rpc('access_context');if(error)return null;
 const context=parseAccessContext(data),hint=tenantHint(request);
 const membership=selectActiveMembership(context.memberships,hint,context.preference.selected_organization_id);
 if(!membership)return null;
 return{id:membership.membership_id,churchId:membership.organization_id,churchSlug:membership.organization_slug,externalUserId:user.id,email:user.email||'',name:String(user.user_metadata?.full_name||user.email||''),role:membership.role==='owner'?'admin':membership.role,personId:null};
}
