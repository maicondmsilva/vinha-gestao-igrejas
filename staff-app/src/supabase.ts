import {AppState} from 'react-native';
import * as SecureStore from 'expo-secure-store';
import {createClient} from '@supabase/supabase-js';
let queue=Promise.resolve();
const serialized=<T>(fn:()=>Promise<T>):Promise<T>=>{const run=queue.then(fn,fn);queue=run.then(()=>undefined,()=>undefined);return run};
const storage={
 getItem:(key:string)=>serialized(async()=>{const count=Number(await SecureStore.getItemAsync(key+'.count'));if(!Number.isInteger(count)||count<1||count>32)return null;const parts=await Promise.all(Array.from({length:count},(_,i)=>SecureStore.getItemAsync(key+'.'+i)));return parts.some(p=>p===null)?null:parts.join('')}),
 setItem:(key:string,value:string)=>serialized(async()=>{const count=Math.ceil(value.length/1800);if(count>32)throw Error('Sessão excede o limite seguro.');await SecureStore.deleteItemAsync(key+'.count');for(let i=0;i<count;i++)await SecureStore.setItemAsync(key+'.'+i,value.slice(i*1800,(i+1)*1800),{keychainAccessible:SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY});await SecureStore.setItemAsync(key+'.count',String(count));}),
 removeItem:(key:string)=>serialized(async()=>{await SecureStore.deleteItemAsync(key+'.count');await Promise.all(Array.from({length:32},(_,i)=>SecureStore.deleteItemAsync(key+'.'+i)))}),
};
const url=process.env.EXPO_PUBLIC_SUPABASE_URL,key=process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
export const configured=!!url&&!!key&&!url.includes('your-project');
export const supabase=configured?createClient(url!,key!,{auth:{storage,autoRefreshToken:true,persistSession:true,detectSessionInUrl:false}}):null;
if(supabase)AppState.addEventListener('change',state=>{if(state==='active')supabase.auth.startAutoRefresh();else supabase.auth.stopAutoRefresh()});
