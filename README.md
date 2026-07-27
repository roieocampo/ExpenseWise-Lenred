# ExpenseWise PH — shared SLIC_DashBoards Supabase version

This version is designed to use an existing Supabase project without touching existing SLIC tables. New database objects are prefixed with `expense_`.

## Frontend environment variables

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

## Database
Run `supabase/schema.sql` in Supabase SQL Editor.

## First admin
Create an Auth user with email `admin@expensewise.app` and metadata:

```json
{"app":"expensewise","full_name":"Administrator","username":"admin"}
```

Then run:

```sql
update public.expense_profiles set role='admin' where username='admin';
```

## Edge Function
Create/deploy the function at `supabase/functions/expense-create-user/index.ts` using the Supabase Dashboard or CLI.

## Cloudflare Pages
- Build command: `npm run build`
- Build output: `dist`
- Variables: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`
