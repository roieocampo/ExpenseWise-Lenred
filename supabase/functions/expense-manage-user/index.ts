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
    const{data:caller}=await userClient.from('expense_profiles').select('role').eq('id',authData.user.id).single()
    if(!['admin','super_admin'].includes(caller?.role))return json({error:'Admin access required'},403)
    const body=await req.json(),userId=String(body.user_id||''),fullName=String(body.full_name||'').trim(),username=String(body.username||'').trim().toLowerCase().replace(/[^a-z0-9._-]/g,''),password=String(body.password||''),requestedRole=body.role==='admin'?'admin':body.role==='super_admin'?'super_admin':'user'
    if(!userId||!fullName||!username)return json({error:'User, full name and username are required.'},400)
    if(password&&password.length<6)return json({error:'New password must be at least 6 characters.'},400)
    const admin=createClient(url,serviceRoleKey)
    const{data:target,error:targetError}=await admin.from('expense_profiles').select('role,username').eq('id',userId).single()
    if(targetError)return json({error:targetError.message},404)
    if(target.role==='super_admin'&&caller.role!=='super_admin')return json({error:'Only the super admin can edit the super-admin account.'},403)
    if(requestedRole==='super_admin'&&target.role!=='super_admin')return json({error:'Super-admin role cannot be assigned from the website.'},403)
    if(requestedRole==='admin'&&target.role!=='admin'){
      const configured=(Deno.env.get('EXPENSE_ADMIN_SECRET')||'').trim()
      if(!configured||String(body.admin_secret||'').trim()!==configured)return json({error:'Invalid admin creation secret.'},403)
    }
    const updates:any={email:`${username}@expensewise.app`,user_metadata:{app:'expensewise',full_name:fullName,username}}
    if(password)updates.password=password
    const{error:authUpdateError}=await admin.auth.admin.updateUserById(userId,updates)
    if(authUpdateError)return json({error:authUpdateError.message},400)
    const finalRole=target.role==='super_admin'?'super_admin':requestedRole
    const{error:profileUpdateError}=await admin.from('expense_profiles').update({full_name:fullName,username,role:finalRole}).eq('id',userId)
    if(profileUpdateError)return json({error:profileUpdateError.message},400)
    return json({ok:true,username,role:finalRole})
  }catch(error){return json({error:error instanceof Error?error.message:'Unexpected error'},500)}
})
