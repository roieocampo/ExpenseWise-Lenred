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
    const callerClient=createClient(url,anonKey,{global:{headers:{Authorization:authHeader}}})
    const{data:authData,error:authError}=await callerClient.auth.getUser()
    if(authError||!authData.user)return json({error:'Invalid or expired session'},401)
    const admin=createClient(url,serviceRoleKey)
    const{data:caller,error:callerError}=await admin.from('expense_profiles').select('role').eq('id',authData.user.id).single()
    if(callerError||!['admin','super_admin'].includes(caller?.role))return json({error:'Admin access required'},403)
    const body=await req.json()
    const userId=String(body.user_id||'')
    const secret=String(body.admin_secret||'').trim()
    if(!userId)return json({error:'Account is required.'},400)
    if(!configured||secret!==configured)return json({error:'Invalid account delete secret password.'},403)
    if(userId===authData.user.id)return json({error:'You cannot delete the account currently signed in.'},400)
    const{data:target,error:targetError}=await admin.from('expense_profiles').select('role,username').eq('id',userId).single()
    if(targetError)return json({error:'Account was not found.'},404)
    if(target.role==='super_admin'&&caller?.role!=='super_admin')return json({error:'Only a super admin can delete a super admin account.'},403)
    const{error:deleteError}=await admin.auth.admin.deleteUser(userId)
    if(deleteError)return json({error:deleteError.message},400)
    return json({ok:true,username:target.username})
  }catch(error){return json({error:error instanceof Error?error.message:'Unexpected account delete error'},500)}
})
