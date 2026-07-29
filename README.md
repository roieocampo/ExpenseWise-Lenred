# ExpenseWise Lenred v1.2 — Home/Admin/Currency Upgrade

Use this version with the existing `SLIC_DashBoards` Supabase project.

## Upgrade order from v1.1

1. In Supabase SQL Editor run:
   `supabase/migrations/20260728_home_admin_currency_upgrade.sql`
2. Replace/redeploy Edge Function `expense-create-user` using:
   `supabase/functions/expense-create-user/index.ts`
3. Create/deploy Edge Function `expense-manage-user` using:
   `supabase/functions/expense-manage-user/index.ts`
4. In Supabase Edge Functions > Secrets add:
   `EXPENSE_ADMIN_SECRET`
   Set its value to the private admin-creation secret you chose/requested. Do not put that value in React, GitHub, or Cloudflare frontend variables.
5. For the protected super-admin account:
   - Create the requested username as a Supabase Authentication user using a synthetic email such as `roieocampo@expensewise.app` and the requested password.
   - Metadata: `{"app":"expensewise","full_name":"Super Administrator","username":"roieocampo"}`
   - Then run: `update public.expense_profiles set role='super_admin' where username='roieocampo';`
   - The password is intentionally NOT stored in this source package.
6. Copy your existing `.env` into this project folder.
7. Run `npm install` then `npm run dev` and test locally before GitHub/Cloudflare.

## v1.2 behavior

- Home is the first page after login.
- Selecting any date maps to Sunday–Saturday.
- Home only lists visible categories whose `available_date` falls within that selected week.
- Users select a category and use its share code the first time. Existing members can open it directly.
- Hidden categories are removed from Home and expense edits are blocked at the RLS layer.
- Expenses no longer contains category/share-code controls.
- Home icon and browser/phone Back return to Home from non-Home pages.
- Expenses tab is hidden while already on Home.
- Category owns one currency; list titles/items inherit that currency.
- Currency choices include PHP, USD, SGD and other common ISO currencies.
- Errors appear in a modal dialog.
- Admin can edit account name, username, password and role.
- Additional admins require `EXPENSE_ADMIN_SECRET` validated inside Edge Functions.
- Protected `super_admin` cannot be assigned through the website.
- Mobile layouts are refined for Home, Expenses, admin forms and dialogs.

## Frontend environment variables

Only:

```
VITE_SUPABASE_URL=...
VITE_SUPABASE_PUBLISHABLE_KEY=...
```

Never put `SUPABASE_SERVICE_ROLE_KEY` or `EXPENSE_ADMIN_SECRET` in frontend `.env`, GitHub, or Cloudflare Pages variables.
