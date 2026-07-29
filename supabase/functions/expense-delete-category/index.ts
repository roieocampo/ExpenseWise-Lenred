import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods':'POST, OPTIONS'
}
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,'Content-Type':'application/json'}})

Deno.serve(async(req)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:corsHeaders})
  if(req.method!=='POST')return json({error:'Method not allowed'},405)
  try{
    const url=Deno.env.get('SUPABASE_URL')!
    const anonKey=Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const configured=(Deno.env.get('EXPENSE_ADMIN_SECRET')||'').trim()
    const authHeader=req.headers.get('Authorization')||''
    if(!authHeader.startsWith('Bearer '))return json({error:'Missing signed-in user token'},401)

    const userClient=createClient(url,anonKey,{global:{headers:{Authorization:authHeader}}})
    const{data:authData,error:authError}=await userClient.auth.getUser()
    if(authError||!authData.user)return json({error:'Invalid or expired session'},401)

    const admin=createClient(url,serviceRoleKey)
    const{data:caller,error:callerError}=await admin.from('expense_profiles').select('role').eq('id',authData.user.id).single()
    if(callerError||!['admin','super_admin'].includes(caller?.role))return json({error:'Admin access required'},403)

    const body=await req.json()
    const categoryId=String(body.category_id||'')
    const secret=String(body.admin_secret||'').trim()
    if(!categoryId)return json({error:'Category is required.'},400)
    if(!configured||secret!==configured)return json({error:'Invalid category delete secret password.'},403)

    const deletes:[string,string][]=[
      ['expense_items','category_id'],
      ['expense_list_sections','category_id'],
      ['expense_weekly_budgets','category_id'],
      ['expense_category_members','category_id'],
      ['expense_activity_logs','category_id'],
    ]
    for(const [table,column] of deletes){
      const{error}=await admin.from(table).delete().eq(column,categoryId)
      if(error)return json({error:`Unable to clear ${table}: ${error.message}`},400)
    }

    const{error}=await admin.from('expense_categories').delete().eq('id',categoryId)
    if(error)return json({error:error.message},400)
    return json({ok:true})
  }catch(error){
    return json({error:error instanceof Error?error.message:'Unexpected delete error'},500)
  }
})
