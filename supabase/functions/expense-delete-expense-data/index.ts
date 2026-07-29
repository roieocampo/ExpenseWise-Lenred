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
    if(!authHeader.startsWith('Bearer '))return json({error:'Missing signed-in user token.'},401)
    if(!configured)return json({error:'EXPENSE_ADMIN_SECRET is not configured in Edge Function Secrets.'},500)

    const userClient=createClient(url,anonKey,{global:{headers:{Authorization:authHeader}}})
    const {data:authData,error:authError}=await userClient.auth.getUser()
    if(authError||!authData.user)return json({error:'Invalid or expired session.'},401)

    const body=await req.json()
    const entityType=String(body.entity_type||'')
    const entityId=String(body.entity_id||'')
    const supplied=String(body.admin_secret||'').trim()
    if(!entityId||!['item','section'].includes(entityType))return json({error:'A valid item/list is required.'},400)
    if(supplied!==configured)return json({error:'Invalid delete secret password.'},403)

    const admin=createClient(url,serviceRoleKey)
    if(entityType==='item'){
      const {data:item,error:itemError}=await admin.from('expense_items').select('id,category_id').eq('id',entityId).single()
      if(itemError||!item)return json({error:'Expense item was not found.'},404)
      const {data:profile}=await admin.from('expense_profiles').select('role').eq('id',authData.user.id).single()
      if(!['admin','super_admin'].includes(profile?.role)){
        const {data:membership}=await admin.from('expense_category_members').select('category_id').eq('category_id',item.category_id).eq('user_id',authData.user.id).maybeSingle()
        if(!membership)return json({error:'You do not have edit access to this category.'},403)
      }
      const {error}=await admin.from('expense_items').delete().eq('id',entityId)
      if(error)return json({error:error.message},400)
    }else{
      const {data:section,error:sectionError}=await admin.from('expense_list_sections').select('id,category_id').eq('id',entityId).single()
      if(sectionError||!section)return json({error:'Expense list was not found.'},404)
      const {data:profile}=await admin.from('expense_profiles').select('role').eq('id',authData.user.id).single()
      if(!['admin','super_admin'].includes(profile?.role)){
        const {data:membership}=await admin.from('expense_category_members').select('category_id').eq('category_id',section.category_id).eq('user_id',authData.user.id).maybeSingle()
        if(!membership)return json({error:'You do not have edit access to this category.'},403)
      }
      const {error}=await admin.from('expense_list_sections').delete().eq('id',entityId)
      if(error)return json({error:error.message},400)
    }
    return json({ok:true})
  }catch(error){
    return json({error:error instanceof Error?error.message:'Unexpected protected delete error.'},500)
  }
})
