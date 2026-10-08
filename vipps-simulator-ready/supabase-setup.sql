-- Run once in a new Supabase project's SQL Editor. All funds are fictional.
begin;
create schema if not exists vipps_private;
revoke all on schema vipps_private from public,anon,authenticated;
create table vipps_private.players(id uuid primary key references auth.users(id) on delete cascade,username text not null check(length(username) between 2 and 30),avatar text not null default '',balance numeric not null default 1000 check(balance>=0),levels numeric[] not null default array[0,0,0,0]::numeric[],pending numeric not null default 0,stamp timestamptz not null default now(),paid timestamptz not null default now());
create unique index players_name on vipps_private.players(lower(username));
create table vipps_private.transactions(id uuid primary key default gen_random_uuid(),from_id uuid references vipps_private.players(id),to_id uuid not null references vipps_private.players(id),amount numeric not null check(amount>0),message text not null default '',kind text not null default 'transfer',created_at timestamptz not null default now(),nonce uuid unique);
create index transactions_from on vipps_private.transactions(from_id,created_at desc);
create index transactions_to on vipps_private.transactions(to_id,created_at desc);
create table vipps_private.requests(id uuid primary key default gen_random_uuid(),from_id uuid not null references vipps_private.players(id),to_id uuid not null references vipps_private.players(id),amount numeric not null check(amount>0),message text not null default '',created_at timestamptz not null default now());
create index requests_to on vipps_private.requests(to_id);
alter table vipps_private.players enable row level security;
alter table vipps_private.transactions enable row level security;
alter table vipps_private.requests enable row level security;
-- No direct table privileges. Only the checked game operations below can mutate money.
create function vipps_private.settle(p_id uuid) returns void language plpgsql set search_path='' as $$
declare p vipps_private.players%rowtype;r numeric;hours numeric;remainder numeric;pay numeric;t timestamptz:=now();
begin
 select * into strict p from vipps_private.players where id=p_id for update;
 r:=10+p.levels[1]*2+p.levels[2]*8+p.levels[3]*30+p.levels[4]*120;
 p.pending:=p.pending+greatest(0,extract(epoch from(t-p.stamp))/60)*r;
 hours:=floor(extract(epoch from(t-p.paid))/3600);
 if hours>0 then
  remainder:=greatest(0,extract(epoch from(t-(p.paid+make_interval(secs=>(hours*3600)::double precision))))/60)*r;
  pay:=greatest(0,p.pending-remainder);p.balance:=p.balance+pay;p.pending:=remainder;p.paid:=p.paid+make_interval(secs=>(hours*3600)::double precision);
  if pay>0 then insert into vipps_private.transactions(to_id,amount,message,kind)values(p_id,pay,'Timelønn','salary');end if;
 end if;
 update vipps_private.players set balance=p.balance,pending=p.pending,paid=p.paid,stamp=t where id=p_id;
end;$$;
create function vipps_private.game(p_action text,p_args jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();target uuid;amount numeric;idx integer;price numeric;v_levels numeric[];row_request vipps_private.requests%rowtype;v_nonce uuid;result jsonb;uname text;
begin
 if actor is null then raise exception 'Logg inn først';end if;
 if p_action='state' then
  select coalesce(nullif(trim(raw_user_meta_data->>'username'),''),'Spiller') into uname from auth.users where id=actor;
  if not found then raise exception 'Ugyldig konto';end if;
  if not exists(select 1 from vipps_private.players where id=actor) then
   uname:=left(uname,21);if length(uname)<2 then uname:='Spiller';end if;
   -- Stable suffix makes creation conflict-free for users with identical initial names.
   uname:=uname||' '||left(actor::text,8);
   insert into vipps_private.players(id,username)values(actor,uname) on conflict(id) do nothing;
  end if;
 end if;
 if not exists(select 1 from vipps_private.players where id=actor)then raise exception 'Åpne spillet først';end if;
 if p_action in ('send','request') then target:=(p_args->>'to')::uuid;amount:=(p_args->>'amount')::numeric;
  if target=actor or not exists(select 1 from vipps_private.players where id=target) then raise exception 'Ugyldig mottaker';end if;
  if amount is null or amount<=0 or amount::text in ('NaN','Infinity','-Infinity') or amount<>round(amount,2) then raise exception 'Ugyldig beløp';end if;
  if length(coalesce(p_args->>'message',''))>140 then raise exception 'For lang melding';end if;
 end if;
 if p_action='answer' then
  select * into row_request from vipps_private.requests where id=(p_args->>'id')::uuid and to_id=actor for update;
  if not found then raise exception 'Forespørselen finnes ikke';end if;
  if (p_args->>'accept')::boolean then target:=row_request.from_id;amount:=row_request.amount;end if;
 end if;
 -- Deterministic lock order prevents opposite transfers from deadlocking.
 perform id from vipps_private.players where id=actor or id=target order by id for update;
 perform vipps_private.settle(actor);
 if p_action='profile' then
  uname:=trim(p_args->>'username');if uname is null or length(uname)not between 2 and 30 then raise exception 'Bruk 2–30 tegn';end if;
  if length(coalesce(p_args->>'avatar',''))>180000 or (coalesce(p_args->>'avatar','')<>'' and (p_args->>'avatar')!~'^data:image/jpeg;base64,[A-Za-z0-9+/=]+$')then raise exception 'Ugyldig profilbilde';end if;
  update vipps_private.players set username=uname,avatar=coalesce(p_args->>'avatar','')where id=actor;
 elsif p_action='upgrade' then
  idx:=(p_args->>'index')::integer+1;if idx is null or idx<1 or idx>4 then raise exception 'Ugyldig oppgradering';end if;
  select p.levels into v_levels from vipps_private.players p where id=actor;
  price:=(array[100,400,1500,6000])[idx]*(v_levels[idx]+1)^2;
  update vipps_private.players set balance=balance-price where id=actor and balance>=price;
  if not found then raise exception 'Ikke nok penger';end if;
  v_levels[idx]:=v_levels[idx]+1;update vipps_private.players set levels=v_levels where id=actor;
 elsif p_action='send' or (p_action='answer' and target is not null) then
  v_nonce:=case when p_action='send' then (p_args->>'nonce')::uuid else row_request.id end;
  if v_nonce is null then raise exception 'Manglende betalings-ID';end if;
  if exists(select 1 from vipps_private.transactions where transactions.nonce=v_nonce)then return '{"ok":true}'::jsonb;end if;
  update vipps_private.players set balance=balance-amount where id=actor and balance>=amount;
  if not found then raise exception 'Ikke nok penger';end if;
  update vipps_private.players set balance=balance+amount where id=target;
  insert into vipps_private.transactions(from_id,to_id,amount,message,nonce)values(actor,target,amount,case when p_action='answer' then row_request.message else coalesce(p_args->>'message','')end,v_nonce);
 elsif p_action='request' then
  if (select count(*)from vipps_private.requests where from_id=actor and created_at>now()-interval '1 hour')>=30 then raise exception 'For mange forespørsler. Prøv senere.';end if;
  insert into vipps_private.requests(from_id,to_id,amount,message)values(actor,target,amount,coalesce(p_args->>'message',''));
 elsif p_action not in ('state','answer') then raise exception 'Ukjent handling';
 end if;
 if p_action='answer' then delete from vipps_private.requests where id=row_request.id;end if;
 if p_action='state' then
  select jsonb_build_object('me',(select to_jsonb(p)from vipps_private.players p where id=actor),'people',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'avatar',p.avatar)order by lower(p.username))from vipps_private.players p where id<>actor),'[]'::jsonb),'transactions',coalesce((select jsonb_agg(to_jsonb(t)order by t.created_at desc)from(select * from vipps_private.transactions where from_id=actor or to_id=actor order by created_at desc limit 100)t),'[]'::jsonb),'requests',coalesce((select jsonb_agg(to_jsonb(r))from vipps_private.requests r where to_id=actor),'[]'::jsonb))into result;
  return result;
 end if;
 return '{"ok":true}'::jsonb;
end;$$;
revoke all on all functions in schema vipps_private from public,anon,authenticated;
grant usage on schema vipps_private to authenticated;
grant execute on function vipps_private.game(text,jsonb)to authenticated;
-- Public wrappers run as the caller; the private checked routine enforces all authorization.
create function public.game_state()returns jsonb language sql security invoker set search_path='' as $$select vipps_private.game('state');$$;
create function public.game_profile(p_username text,p_avatar text)returns jsonb language sql security invoker set search_path='' as $$select vipps_private.game('profile',jsonb_build_object('username',p_username,'avatar',p_avatar));$$;
create function public.game_upgrade(p_index integer)returns jsonb language sql security invoker set search_path='' as $$select vipps_private.game('upgrade',jsonb_build_object('index',p_index));$$;
create function public.game_send(p_to uuid,p_amount numeric,p_message text,p_nonce uuid)returns jsonb language sql security invoker set search_path='' as $$select vipps_private.game('send',jsonb_build_object('to',p_to,'amount',p_amount,'message',p_message,'nonce',p_nonce));$$;
create function public.game_request(p_to uuid,p_amount numeric,p_message text)returns jsonb language sql security invoker set search_path='' as $$select vipps_private.game('request',jsonb_build_object('to',p_to,'amount',p_amount,'message',p_message));$$;
create function public.game_request_answer(p_id uuid,p_accept boolean)returns jsonb language sql security invoker set search_path='' as $$select vipps_private.game('answer',jsonb_build_object('id',p_id,'accept',p_accept));$$;
revoke all on function public.game_state(),public.game_profile(text,text),public.game_upgrade(integer),public.game_send(uuid,numeric,text,uuid),public.game_request(uuid,numeric,text),public.game_request_answer(uuid,boolean)from public,anon;
grant execute on function public.game_state(),public.game_profile(text,text),public.game_upgrade(integer),public.game_send(uuid,numeric,text,uuid),public.game_request(uuid,numeric,text),public.game_request_answer(uuid,boolean)to authenticated;
notify pgrst,'reload schema';
commit;
