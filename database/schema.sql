create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
create table public.staff (
 email text primary key check (email = lower(email)),
 role text not null check (role in ('admin','employee')),
 created_at timestamptz not null default now()
);
alter table public.staff enable row level security;
create function private.staff_role() returns text language sql stable security definer set search_path = '' as $$
 select s.role from public.staff s join auth.users u on lower(u.email) = s.email
 where u.id = (select auth.uid()) and u.email_confirmed_at is not null
$$;
revoke all on function private.staff_role() from public;
grant execute on function private.staff_role() to authenticated;
create policy staff_read on public.staff for select to authenticated using (email = lower(auth.jwt()->>'email') or (select private.staff_role()) = 'admin');
create policy staff_add on public.staff for insert to authenticated with check ((select private.staff_role()) = 'admin' and role = 'employee');
create policy staff_remove on public.staff for delete to authenticated using ((select private.staff_role()) = 'admin' and role = 'employee');
grant select, insert, delete on public.staff to authenticated;
insert into public.staff(email,role) values ('replace-with-owner@example.com','admin');
create table public.listings (
 id uuid primary key default gen_random_uuid(),
 title text not null check (length(title) between 3 and 160),
 address text not null check (length(address) between 3 and 300),
 city text not null check(length(city) between 2 and 80),
 price numeric not null check(price > 0 and price < 10000000),
 beds integer not null default 0 check (beds between 0 and 30),
 baths numeric not null default 1 check (baths between 0 and 30),
 sqft integer check(sqft > 0),
 property_type text not null default 'Apartment' check(property_type in ('Apartment','House','Townhouse','Condo','Commercial')),
 description text not null default '' check(length(description) <= 15000),
 amenities text not null default '' check(length(amenities) <= 2000),
 images text[] not null default '{}' check(cardinality(images) <= 20),
 status text not null default 'draft' check(status in ('draft','published','rented')),
 available_date date,
 created_at timestamptz not null default now()
);
alter table public.listings enable row level security;
create policy listings_public on public.listings for select to anon, authenticated using(status = 'published');
create policy listings_staff on public.listings for all to authenticated using((select private.staff_role()) is not null) with check((select private.staff_role()) is not null);
grant select on public.listings to anon;
grant select, insert, update, delete on public.listings to authenticated;
create index listings_status_city on public.listings(status,city);
create table public.inquiries (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(name) between 2 and 100),
 email text not null check(length(email) between 5 and 254 and email like '%@%.%'),
 phone text not null default '' check(length(phone) <= 40),
 kind text not null check(kind in ('management','rental','general')),
 message text not null check(length(message) between 10 and 5000),
 listing_id uuid references public.listings(id) on delete set null,
 status text not null default 'new' check(status in ('new','contacted','closed')),
 consent boolean not null check(consent),
 created_at timestamptz not null default now()
);
alter table public.inquiries enable row level security;
create policy inquiries_submit on public.inquiries for insert to anon,authenticated with check(status='new' and consent=true);
create policy inquiries_staff_read on public.inquiries for select to authenticated using((select private.staff_role()) is not null);
create policy inquiries_staff_update on public.inquiries for update to authenticated using((select private.staff_role()) is not null) with check((select private.staff_role()) is not null);
grant insert(name,email,phone,kind,message,listing_id,consent) on public.inquiries to anon,authenticated;
grant select,update(status) on public.inquiries to authenticated;
create index inquiries_listing on public.inquiries(listing_id);
create table public.settings (
 id boolean primary key default true check(id),
 phone text not null default '' check(length(phone)<=40),
 email text not null default '' check(length(email)<=254),
 address text not null default '' check(length(address)<=300)
);
alter table public.settings enable row level security;
create policy settings_read on public.settings for select to anon,authenticated using(true);
create policy settings_update on public.settings for update to authenticated using((select private.staff_role())='admin') with check((select private.staff_role())='admin');
grant select on public.settings to anon,authenticated;
grant update on public.settings to authenticated;
insert into public.settings(id) values(true);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('property-photos','property-photos',true,10485760,array['image/jpeg','image/png','image/webp']);
create policy photos_staff on storage.objects for all to authenticated using(bucket_id='property-photos' and (select private.staff_role()) is not null) with check(bucket_id='property-photos' and (select private.staff_role()) is not null);

-- Inquiry completion tracking (applied separately to the existing deployment).
alter table public.inquiries add column handled_by text, add column completed_at timestamptz;
create function private.track_inquiry_status() returns trigger language plpgsql security invoker set search_path = '' as $$
begin
 if new.status is distinct from old.status then
  if new.status='new' then new.handled_by:=null; new.completed_at:=null;
  else
   new.handled_by:=auth.jwt()->>'email';
   new.completed_at:=case when new.status='closed' then now() else null end;
  end if;
 end if;
 return new;
end $$;
revoke all on function private.track_inquiry_status() from public;
create trigger track_inquiry_status before update of status on public.inquiries for each row execute function private.track_inquiry_status();
drop policy inquiries_staff_update on public.inquiries;
create policy inquiries_staff_update on public.inquiries for update to authenticated using ((select private.staff_role()) is not null and status <> 'closed') with check ((select private.staff_role()) is not null);
grant delete on public.inquiries to authenticated;
create policy inquiries_admin_clear_logs on public.inquiries for delete to authenticated using ((select private.staff_role())='admin' and status='closed');

-- Admin restore, private session activity, and employee log isolation.
drop policy inquiries_staff_read on public.inquiries;
create policy inquiries_staff_read on public.inquiries for select to authenticated using ((select private.staff_role())='admin' or ((select private.staff_role())='employee' and status<>'closed'));
drop policy inquiries_staff_update on public.inquiries;
revoke update(status) on public.inquiries from authenticated;
create function private.change_inquiry_status(p_id uuid,p_expected text,p_status text) returns boolean language plpgsql security definer set search_path='' as $$
declare r text; n integer;
begin
 r:=private.staff_role();
 if auth.uid() is null or r is null then raise exception 'Staff access required' using errcode='42501'; end if;
 if p_status is null or p_status not in ('new','contacted','closed') then raise exception 'Invalid status'; end if;
 if p_expected='closed' and (r<>'admin' or p_status<>'new') then raise exception 'Only administrators can restore completed inquiries' using errcode='42501'; end if;
 update public.inquiries set status=p_status where id=p_id and status=p_expected;
 get diagnostics n=row_count; return n=1;
end $$;
revoke all on function private.change_inquiry_status(uuid,text,text) from public;
grant execute on function private.change_inquiry_status(uuid,text,text) to authenticated;
create function public.change_inquiry_status(p_id uuid,p_expected text,p_status text) returns boolean language sql security invoker set search_path='' as $$select private.change_inquiry_status(p_id,p_expected,p_status)$$;
revoke all on function public.change_inquiry_status(uuid,text,text) from public;
grant execute on function public.change_inquiry_status(uuid,text,text) to authenticated;

create table private.staff_sessions(
 session_id uuid primary key,
 user_id uuid not null,
 email text not null,
 signed_in_at timestamptz not null,
 first_seen_at timestamptz not null default now(),
 last_seen_at timestamptz not null default now(),
 signed_out_at timestamptz
);
alter table private.staff_sessions enable row level security;
revoke all on private.staff_sessions from public,anon,authenticated;
create index staff_sessions_email_time on private.staff_sessions(email,signed_in_at desc);
create function private.record_staff_session(p_sign_out boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare sid uuid; started timestamptz; who text;
begin
 if auth.uid() is null or private.staff_role() is null then raise exception 'Staff access required' using errcode='42501'; end if;
 sid:=(auth.jwt()->>'session_id')::uuid;
 select s.created_at,lower(u.email) into started,who from auth.sessions s join auth.users u on u.id=s.user_id where s.id=sid and s.user_id=auth.uid();
 if started is null then raise exception 'Valid session required' using errcode='42501'; end if;
 insert into private.staff_sessions(session_id,user_id,email,signed_in_at,signed_out_at)
 values(sid,auth.uid(),who,started,case when p_sign_out then now() end)
 on conflict(session_id) do update set last_seen_at=now(),signed_out_at=case when p_sign_out then coalesce(private.staff_sessions.signed_out_at,now()) else private.staff_sessions.signed_out_at end;
end $$;
revoke all on function private.record_staff_session(boolean) from public;
grant execute on function private.record_staff_session(boolean) to authenticated;
create function public.record_staff_session(p_sign_out boolean default false) returns void language sql security invoker set search_path='' as $$select private.record_staff_session(p_sign_out)$$;
revoke all on function public.record_staff_session(boolean) from public;
grant execute on function public.record_staff_session(boolean) to authenticated;
create function private.employee_activity(p_email text,p_before timestamptz default null) returns table(session_id uuid,signed_in_at timestamptz,signed_out_at timestamptz,last_seen_at timestamptz) language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or private.staff_role() is distinct from 'admin' then raise exception 'Administrator access required' using errcode='42501'; end if;
 return query select s.session_id,s.signed_in_at,s.signed_out_at,s.last_seen_at from private.staff_sessions s where s.email=lower(p_email) and (p_before is null or s.signed_in_at<p_before) order by s.signed_in_at desc limit 50;
end $$;
revoke all on function private.employee_activity(text,timestamptz) from public;
grant execute on function private.employee_activity(text,timestamptz) to authenticated;
create function public.employee_activity(p_email text,p_before timestamptz default null) returns table(session_id uuid,signed_in_at timestamptz,signed_out_at timestamptz,last_seen_at timestamptz) language sql security invoker set search_path='' as $$select * from private.employee_activity(p_email,p_before)$$;
revoke all on function public.employee_activity(text,timestamptz) from public;
grant execute on function public.employee_activity(text,timestamptz) to authenticated;
revoke all on function public.change_inquiry_status(uuid,text,text),public.record_staff_session(boolean),public.employee_activity(text,timestamptz) from anon;
revoke all on function private.change_inquiry_status(uuid,text,text),private.record_staff_session(boolean),private.employee_activity(text,timestamptz) from anon;

-- Role-scoped handled property and customer directory.
create function private.handled_customers(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare r text; who text; result jsonb;
begin
 r:=private.staff_role();
 if auth.uid() is null or r is null then raise exception 'Staff access required' using errcode='42501'; end if;
 select lower(email) into who from auth.users where id=auth.uid();
 select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into result from (
 select i.id,i.name,i.email,i.phone,i.kind,i.message,i.status,i.listing_id,i.created_at,i.handled_by,i.completed_at,l.title as property_title,l.address as property_address,l.city as property_city
 from public.inquiries i left join public.listings l on l.id=i.listing_id
 where i.status in ('contacted','closed') and i.handled_by is not null and (r='admin' or lower(i.handled_by)=who)
 order by i.created_at desc,i.id limit 200 offset greatest(coalesce(p_offset,0),0)
 ) q;
 return result;
end $$;
revoke all on function private.handled_customers(integer) from public,anon;
grant execute on function private.handled_customers(integer) to authenticated;
create function public.handled_customers(p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select private.handled_customers(p_offset)$$;
revoke all on function public.handled_customers(integer) from public,anon;
grant execute on function public.handled_customers(integer) to authenticated;
