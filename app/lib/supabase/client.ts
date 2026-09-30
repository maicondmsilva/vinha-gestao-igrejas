import {createBrowserClient} from '@supabase/ssr';

export const supabaseConfigured=Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL&&process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
export function createSupabaseBrowserClient(){if(!supabaseConfigured)throw new Error('Supabase Auth ainda não foi configurado.');return createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!)}
