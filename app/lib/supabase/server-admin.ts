import {createClient} from '@supabase/supabase-js';
import {OperationError,type OperationsClient} from './operations';
// Server-only import. Never use a NEXT_PUBLIC name for this credential.
export function supabaseAdminClient():OperationsClient{
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SECRET_KEY||process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key)throw new OperationError('O processamento seguro de pagamentos ainda não foi configurado.',503);
 return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
}
