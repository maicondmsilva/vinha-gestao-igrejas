import {createServerClient} from '@supabase/ssr';
import {createClient} from '@supabase/supabase-js';
import type {Database} from './database.types';

export const supabaseServerConfigured=Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL&&process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);

function parseCookies(request:Request){
 return (request.headers.get('cookie')||'').split(/;\s*/).filter(Boolean).map(item=>{const separator=item.indexOf('=');const name=separator<0?item:item.slice(0,separator),raw=separator<0?'':item.slice(separator+1);let value=raw;try{value=decodeURIComponent(raw)}catch{}return{name,value}});
}

/** Native staff app: an access token in Authorization, never mixed with a browser cookie session. */
export function bearerToken(request:Request){
 const value=request.headers.get('authorization')||'';
 return !request.headers.get('cookie')&&/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value)?value:null;
}

export function createSupabaseRequestClient(request:Request){
 if(!supabaseServerConfigured)throw new Error('Supabase não configurado.');
 const bearer=bearerToken(request);
 if(bearer)return createClient<Database>(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{global:{headers:{Authorization:bearer}},auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}}) as unknown as ReturnType<typeof createServerClient<Database>>;
 return createServerClient<Database>(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{cookies:{getAll:()=>parseCookies(request),setAll:()=>{}}});
}
