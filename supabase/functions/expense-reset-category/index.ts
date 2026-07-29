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

    if(!authHeader.startsWith('Bearer ')){
      return json({error:'Missing signed-in user token'},401)
    }

    // Validate the signed-in user inside the Function.
    // This is intentional so the Function can be deployed with gateway JWT
    // verification disabled if Supabase rejects the request before runtime.
    const userClient=createClient(url,anonKey,{global:{headers:{Authorization:authHeader}}})
    const{data:authData,error:authError}=await userClient.auth.getUser()
    if(authError||!authData.user){
      return json({error:'Invalid or expired session'},401)
    }

    const admin=createClient(url,serviceRoleKey)
    const{data:caller,error:callerError}=await admin
      .from('expense_profiles')
      .select('role')
      .eq('id',authData.user.id)
      .single()

    if(callerError||!['admin','super_admin'].includes(caller?.role)){
      return json({error:'Admin access required'},403)
    }

    const body=await req.json()
    const categoryId=String(body.category_id||'').trim()
    const secret=String(body.admin_secret||'').trim()

    if(!categoryId)return json({error:'Category is required.'},400)
    if(!configured||secret!==configured){
      return json({error:'Invalid category reset secret password.'},403)
    }

    // RESET ONLY:
    // Keep expense_categories, expense_category_members and
    // expense_weekly_budgets. Clear only expense content/history.
    //
    // Delete items first, then list titles. Child deletes can create activity
    // rows through triggers, so activity logs are cleared last.
    const{error:itemError}=await admin
      .from('expense_items')
      .delete()
      .eq('category_id',categoryId)
    if(itemError)return json({error:`Unable to clear expense_items: ${itemError.message}`},400)

    const{error:listError}=await admin
      .from('expense_list_sections')
      .delete()
      .eq('category_id',categoryId)
    if(listError)return json({error:`Unable to clear expense_list_sections: ${listError.message}`},400)

    const{error:logError}=await admin
      .from('expense_activity_logs')
      .delete()
      .eq('category_id',categoryId)
    if(logError)return json({error:`Unable to clear expense_activity_logs: ${logError.message}`},400)

    return json({
      ok:true,
      message:'Category expense data reset successfully.'
    })
  }catch(error){
    return json({error:error instanceof Error?error.message:'Unexpected reset error'},500)
  }
})
