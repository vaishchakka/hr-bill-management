# Email sign-in setup

1. Apply migrations 001–009 in order (only run unapplied migrations). For this change, run 202611180009_email_roster.sql. Then run the entire supabase/tests/email_roster.sql separately. Tests roll back their fixtures.
2. In Supabase Authentication settings, ensure the Email provider and new user signups are enabled. Verification still does not grant app membership.
3. In Authentication email templates, set both **Magic Link** and **Confirm signup** bodies to include the OTP, e.g. `<h2>House Leadership</h2><p>Your sign-in code is: <strong>{{ .Token }}</strong></p>`. This application uses code entry; do not send only a ConfirmationURL link. Existing users may use the password option.
4. Configure a production SMTP provider for real members. Supabase's default email service restricts recipients and delivery volume; project connection alone does not establish email delivery to arbitrary GT addresses. Keep Supabase's email rate limits; the UI also waits 60 seconds before resend. Confirm OTP expiry/length in Auth settings.
5. Add approved emails with trusted SQL, after obtaining the actual roster:

```sql
insert into house_private.email_roster(email)
values ('approved-person@gatech.edu')
on conflict(email) do nothing;
```

Replace the example before running it. The roster accepts exact lowercase @gatech.edu addresses only; aliases must match the email used at verification. Do not put real membership rosters in the public GitHub repo. No roster has been imported automatically.

6. Restart `npm run dev` or rebuild the frontend, request a code, verify it, and check the assigned role. Test an approved new user, an unapproved verified user, an expired/invalid code, and the existing admin password option. Live delivery and SQL tests have not been run automatically.

The claim RPC reads auth.users.email and email_confirmed_at using auth.uid(), never a supplied email or editable metadata. Roster matches create member roles only. Existing manually assigned memberships/admin roles remain intact. An email can be claimed by one user ID. Clients cannot list or modify the roster.

Removing a roster email alone does not revoke an already-linked house_members row: revoke access explicitly by deleting that membership row too. Email changes do not automatically transfer membership; revoke/reapprove the account as needed. Full roster import/revocation administration is a later feature.
