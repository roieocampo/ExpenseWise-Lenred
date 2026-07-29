import { createClient } from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL;
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
if(!url||!key)console.warn('Missing Supabase environment variables.');
export const supabase=createClient(url||'',key||'');
export async function resolveLoginEmail(username=''){
  const clean=username.trim().toLowerCase().replace(/[^a-z0-9._-]/g,'');
  if(!clean)throw new Error('Enter your username.');
  if(clean==='roieocampo')return 'roieocampo@expensewise.app';
  const{data,error}=await supabase.rpc('expense_resolve_login_email',{p_username:clean});
  if(error)throw error;
  if(!data)throw new Error('Username was not found.');
  return data;
}

export async function invokeExpenseFunction(name, body={}){
  const {data:{session},error:sessionError}=await supabase.auth.getSession();
  if(sessionError)throw sessionError;
  if(!session?.access_token)throw new Error('Your login session has expired. Please sign in again.');
  const {data,error}=await supabase.functions.invoke(name,{
    body:body||{},
    headers:{Authorization:`Bearer ${session.access_token}`}
  });
  if(error){
    let message=error.message||`${name} failed.`;
    try{
      if(error.context){
        const payload=await error.context.json();
        message=payload?.error||payload?.message||message;
      }
    }catch{}
    throw new Error(message);
  }
  if(data?.error)throw new Error(data.error);
  return data;
}
