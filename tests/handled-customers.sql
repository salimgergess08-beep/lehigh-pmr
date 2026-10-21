begin;
insert into auth.users(id,email,email_confirmed_at) values('c1111111-1111-4111-8111-111111111111','work-employee@example.invalid',now()),('c2222222-2222-4222-8222-222222222222','work-admin@example.invalid',now());
insert into public.staff(email,role) values('work-employee@example.invalid','employee'),('work-admin@example.invalid','admin');
insert into public.inquiries(id,name,email,kind,message,consent,status,handled_by) values
('c3333333-3333-4333-8333-333333333333','Own customer','own@example.invalid','rental','Testing own handled record',true,'closed','work-employee@example.invalid'),
('c4444444-4444-4444-8444-444444444444','Other customer','other@example.invalid','general','Testing other handled record',true,'contacted','work-admin@example.invalid');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated"}',true);
do $$ declare r jsonb; begin r:=public.handled_customers(0);
if not r @> '[{"id":"c3333333-3333-4333-8333-333333333333"}]'::jsonb then raise exception 'Own customer missing'; end if;
if r @> '[{"id":"c4444444-4444-4444-8444-444444444444"}]'::jsonb then raise exception 'Other customer leaked'; end if;
if exists(select 1 from public.inquiries where id='c3333333-3333-4333-8333-333333333333') then raise exception 'Logs exposed directly';end if;
end $$;
select set_config('request.jwt.claims','{"sub":"c2222222-2222-4222-8222-222222222222","role":"authenticated"}',true);
do $$ declare r jsonb; begin r:=public.handled_customers(0);
if not r @> '[{"id":"c3333333-3333-4333-8333-333333333333"},{"id":"c4444444-4444-4444-8444-444444444444"}]'::jsonb then raise exception 'Admin view incomplete';end if;end $$;
reset role;
do $$ begin if has_function_privilege('anon','public.handled_customers(integer)','execute') then raise exception 'Anonymous access';end if;end $$;
rollback;
select 'PASS: own completed customer visible, other employee customers denied, admin team view, Logs remain restricted, anonymous denied; fixtures rolled back' as result;
