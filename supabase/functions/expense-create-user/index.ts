import { createClient } from 'npm:@supabase/supabase-js@2'
const corsHeaders={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'}
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,'Content-Type':'application/json'}})
Deno.serve(async(req)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:corsHeaders})
  if(req.method!=='POST')return json({error:'Method not allowed'},405)
  try{
    const url=Deno.env.get('SUPABASE_URL')!,anonKey=Deno.env.get('SUPABASE_ANON_KEY')!,serviceRoleKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const authHeader=req.headers.get('Authorization')||''
    if(!authHeader.startsWith('Bearer '))return json({error:'Missing signed-in user token'},401)
    const userClient=createClient(url,anonKey,{global:{headers:{Authorization:authHeader}}})
    const{data:authData,error:authError}=await userClient.auth.getUser()
    if(authError||!authData.user)return json({error:'Invalid or expired session'},401)
    const{data:caller,error:profileError}=await userClient.from('expense_profiles').select('role').eq('id',authData.user.id).single()
    if(profileError||!['admin','super_admin'].includes(caller?.role))return json({error:'Admin access required'},403)
    const body=await req.json(),fullName=String(body.full_name||'').trim(),username=String(body.username||'').trim().toLowerCase().replace(/[^a-z0-9._-]/g,''),password=String(body.password||''),role=body.role==='admin'?'admin':'user'
    if(!fullName||!username||password.length<6)return json({error:'Name, username and password of at least 6 characters are required.'},400)
    if(role==='admin'){
      const configured=(Deno.env.get('EXPENSE_ADMIN_SECRET')||'').trim()
      if(!configured||String(body.admin_secret||'').trim()!==configured)return json({error:'Invalid admin creation secret.'},403)
    }
    const admin=createClient(url,serviceRoleKey),email=`${username}@expensewise.app`
    const{data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{app:'expensewise',full_name:fullName,username}})
    if(error)return json({error:error.message},400)
    if(role==='admin'&&data.user){const{error:re}=await admin.from('expense_profiles').update({role:'admin'}).eq('id',data.user.id);if(re)return json({error:`Account created but role update failed: ${re.message}`},500)}
    return json({id:data.user?.id,username,role})
  }catch(error){return json({error:error instanceof Error?error.message:'Unexpected error'},500)}
})
