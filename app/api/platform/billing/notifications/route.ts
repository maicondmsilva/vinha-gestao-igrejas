import {centralRoute,check,requireValue,recordAudit} from '../../../../lib/supabase/operations';
import {processBillingNotifications} from '../../../../lib/supabase/billing-notifications';
export const GET=centralRoute(async(_r,client)=>({items:check(await client.from('saas_invoice_notifications').select('*').order('created_at',{ascending:false}).limit(100))}));
export const POST=centralRoute(async(request,client,session)=>{requireValue(request.headers.get('origin')===new URL(request.url).origin,'Origem inválida.',403);const result=await processBillingNotifications(client);await recordAudit(client,session.id,'billing.notifications_processed','billing',undefined,result);return{ok:true,...result}});
