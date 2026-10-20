# Lehigh Property Management & Realty

Live site: https://lehigh-pmr.onrender.com/
Staff workspace: https://lehigh-pmr.onrender.com/#admin
Supabase project: https://supabase.com/dashboard/project/jqkoejmtkvclfakrcpeh

## Delivered

Responsive public home, management services, about, rentals, contact and privacy pages; Supabase-backed rental filters and detail galleries; staff sign-in, activation and password recovery interfaces; draft/published/rented listings; photo upload, cover selection and removal; inquiry inbox and status updates; admin employee allowlist and public contact settings.

No sample listings or fictional contact details were published. Photos on the home page are illustrative stock images. Uploaded screenshots were design references, not assets deployed into the website.

## First administrator setup

Admin access is reserved for the owner email configured in the database. This is a database authorization entry, not a completed Auth account. No password was generated or shared.

1. Open Supabase Authentication > URL Configuration:
   https://supabase.com/dashboard/project/jqkoejmtkvclfakrcpeh/auth/url-configuration
2. Set Site URL to https://lehigh-pmr.onrender.com/ and add https://lehigh-pmr.onrender.com/** to Redirect URLs. Add the final domain URLs after the domain is connected.
3. Open the Staff workspace, click First time? Activate account, enter the reserved email and choose a unique password of at least 12 characters.
4. Confirm the email, then sign in. Use Company settings to enter the real agency email, phone and office address.

Email confirmation is required before access is granted. Supabase's default sender is for testing and may only deliver to organization members. Configure a production SMTP provider in Supabase Authentication before onboarding employees or depending on recovery mail. This project did not configure an SMTP provider because none was supplied. Do not disable email verification to work around mail issues.

## Employees

Admin > Team access > enter employee email > Grant access. This does not send email. Employees open Staff sign in, activate an account with exactly that approved email, confirm it, then sign in. Employees can manage properties and inquiries but cannot grant access or change company settings. Removing a staff entry revokes database and Storage access on subsequent requests. Staff authorization is checked against confirmed Auth users and the database, not user-editable metadata.

## Property workflow

Add property, enter details, upload JPG/PNG/WebP files (10 MB each, maximum 20 photos), choose cover, and select Draft, Published or Rented. Published listings appear publicly; Draft and Rented listings are staff-only. Delete requires confirmation. Removing a photo and saving removes its storage object. Deleting a listing cleans up its attached photos. Photos uploaded into an abandoned editor may remain as orphaned storage objects and should be periodically cleaned up. Published bucket URLs are public, including photos attached to drafts; never upload sensitive material.

## Inquiries

Public requests are stored in the staff inbox. They do not trigger an email notification. Staff can mark requests New, Contacted or Closed. Contact details are collected with consent. Honeypot and field validation are included; a production CAPTCHA/rate-limit service is not configured. The app does not process rental applications, background checks, payments, leases, or maintenance tickets.

## Render hosting

Deploy this repository as a Render Static Site on branch `main`.

- Build command: `npm ci && npm run build`
- Publish directory: `dist`
- Supabase continues to handle authentication, database and photo storage.

After Render returns the deployed URL, set the Supabase Authentication Site URL to that address and add its `/**` pattern to Redirect URLs. Keep any existing redirect URLs needed during migration. Add the custom domain through Render's settings and use only the DNS targets Render supplies.

Render deployment is live. The homepage, rental list backed by Supabase, and staff sign-in screen were verified. Configure Supabase authentication URLs for the Render address before relying on confirmation and recovery links. The custom domain has not yet been connected.

## Repository

Source: https://github.com/salimgergess08-beep/lehigh-pmr

The database bootstrap email is a placeholder in this public repository. Existing production admin access is unchanged. Do not rerun the initial schema against the existing database.

## Local development

Install Node.js 22 or later. From this folder:

    npm ci
    npm run dev

Production build:

    npm run build

The frontend contains only a public Supabase publishable key. Database RLS is the authorization boundary. Never place service-role keys in browser code. database/schema.sql records the already-applied initial schema; do not rerun it on this existing project.

## Verification

- TypeScript and production Vite build passed.
- Supabase security advisors: no findings at creation.
- Transactional SQL tests passed: anonymous cannot view drafts, create listings or read inquiry records; approved employees can create/publish/delete listings; employees cannot grant staff access or change settings; owner can manage staff and settings.
- Test fixtures rolled back; no temporary Auth users or properties were retained.
- AppDeploy status: ready; frontend and network error arrays empty.
- Live owner sign-in, email delivery, authenticated browser CRUD and photo-upload journeys still require the owner to activate their account. These were not falsely treated as completed browser tests.
- tests/tests.json contains public inquiry, rental navigation/filter and authentication-boundary browser scenarios. The deployment status did not separately return their execution results.

The local source package is functionally equivalent to the deployed app. AppDeploy normalized remote formatting and includes its starter config; the local Vite setup builds independently without Tailwind.
