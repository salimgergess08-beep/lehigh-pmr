begin;
insert into auth.users(id,email,email_confirmed_at) values
('d1111111-1111-4111-8111-111111111111','approval-employee@example.invalid',now()),
('d2222222-2222-4222-8222-222222222222','approval-admin@example.invalid',now()),
('d4444444-4444-4444-8444-444444444444','approval-outsider@example.invalid',now());
insert into public.staff(email,role) values ('approval-employee@example.invalid','employee'),('approval-admin@example.invalid','admin');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"d1111111-1111-4111-8111-111111111111","role":"authenticated"}',true);
insert into public.listings(id,title,address,city,price,status) values ('d3333333-3333-4333-8333-333333333333','Approval test','123 Test Street','Test City',1000,'draft');
do $$ begin
 begin
  insert into public.listings(title,address,city,price,status) values ('Publish bypass','123 Test Street','Test City',1000,'published');
  raise exception 'Employee inserted published listing';
 exception when insufficient_privilege then null;end;
 begin
  update public.listings set status='published' where id='d3333333-3333-4333-8333-333333333333';
  raise exception 'Employee published draft';
 exception when insufficient_privilege then null;end;
end $$;
set local role anon;
do $$ begin if exists(select 1 from public.listings where id='d3333333-3333-4333-8333-333333333333') then raise exception 'Draft publicly visible';end if;end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"d2222222-2222-4222-8222-222222222222","role":"authenticated"}',true);
do $$ declare n integer;begin
 update public.listings set status='published' where id='d3333333-3333-4333-8333-333333333333' and revision=1;
 get diagnostics n=row_count;if n<>1 then raise exception 'Admin approval failed';end if;
end $$;
set local role anon;
do $$ begin if not exists(select 1 from public.listings where id='d3333333-3333-4333-8333-333333333333' and status='published') then raise exception 'Approved listing not public';end if;end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"d1111111-1111-4111-8111-111111111111","role":"authenticated"}',true);
do $$ begin
 begin
  update public.listings set title='Unapproved public edit' where id='d3333333-3333-4333-8333-333333333333';
  raise exception 'Employee modified public listing without draft';
 exception when insufficient_privilege then null;end;
 update public.listings set title='Revised draft',status='draft' where id='d3333333-3333-4333-8333-333333333333';
end $$;
set local role anon;
do $$ begin if exists(select 1 from public.listings where id='d3333333-3333-4333-8333-333333333333') then raise exception 'Revised draft public';end if;end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"d2222222-2222-4222-8222-222222222222","role":"authenticated"}',true);
do $$ declare n integer;begin
 update public.listings set status='published' where id='d3333333-3333-4333-8333-333333333333' and revision=2;
 get diagnostics n=row_count;if n<>0 then raise exception 'Stale approval accepted';end if;
 update public.listings set status='published' where id='d3333333-3333-4333-8333-333333333333' and revision=3;
 get diagnostics n=row_count;if n<>1 then raise exception 'Current approval failed';end if;
end $$;
select set_config('request.jwt.claims','{"sub":"d4444444-4444-4444-8444-444444444444","role":"authenticated"}',true);
do $$ begin
 begin
  insert into public.listings(title,address,city,price,status) values ('Outsider draft','123 Test Street','Test City',1000,'draft');
  raise exception 'Nonstaff inserted draft';
 exception when insufficient_privilege then null;end;
end $$;
rollback;
select 'PASS: employee draft creation; direct publish denied; public draft isolation; admin approval; edits require reapproval; stale approval rejected; nonstaff denied. Fixtures rolled back.' as result;
