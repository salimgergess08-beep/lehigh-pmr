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
