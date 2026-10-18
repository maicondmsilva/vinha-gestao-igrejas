import {createServerClient} from '@supabase/ssr';
import {NextResponse,type NextRequest} from 'next/server';
// Refresh before dispatch; authorization remains in the APIs and database.
export async function proxy(request:NextRequest){
 let response=NextResponse.next({request});
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 if(!url||!key||!request.cookies.getAll().some(cookie=>/^sb-.+-auth-token(?:\.\d+)?$/.test(cookie.name)))return response;
 const client=createServerClient(url,key,{cookies:{getAll:()=>request.cookies.getAll(),setAll:values=>{for(const {name,value} of values)request.cookies.set(name,value);response=NextResponse.next({request});for(const {name,value,options} of values)response.cookies.set(name,value,options)}}});
 try{await client.auth.getUser()}catch{/* The target route must fail closed. */}
 response.headers.set('Cache-Control','private, no-store, max-age=0');return response;
}
export const config={matcher:['/((?!_next/static|_next/image|favicon.ico|api/webhooks).*)']};
