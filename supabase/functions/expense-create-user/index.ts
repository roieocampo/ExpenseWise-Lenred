import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const authHeader = req.headers.get('Authorization') || ''

    const callerClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    })

    const { data: { user: caller }, error: callerError } = await callerClient.auth.getUser()
    if (callerError || !caller) return json({ error: 'Unauthorized' }, 401)

    const adminClient = createClient(url, serviceKey, { auth: { persistSession: false } })
    const { data: profile, error: profileError } = await adminClient
      .from('expense_profiles')
      .select('role')
      .eq('id', caller.id)
      .single()

    if (profileError || profile?.role !== 'admin') return json({ error: 'Admin access required' }, 403)

    const body = await req.json()
    const fullName = String(body.full_name || '').trim()
    const username = String(body.username || '').trim().toLowerCase().replace(/[^a-z0-9._-]/g, '')
    const password = String(body.password || '')

    if (!fullName || !username || password.length < 8) {
      return json({ error: 'Full name, valid username, and password of at least 8 characters are required.' }, 400)
    }

    const email = `${username}@expensewise.app`
    const { data, error } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { app: 'expensewise', full_name: fullName, username },
    })

    if (error) return json({ error: error.message }, 400)
    return json({ id: data.user.id, username })
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : 'Unexpected error' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
