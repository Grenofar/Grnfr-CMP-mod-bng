\set ON_ERROR_STOP on
create schema t;
create function t.login(u uuid) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub', u::text, false); execute 'set role authenticated'; end $$;
create function t.anon() returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub', '', false); execute 'set role anon'; end $$;
create function t.root() returns void language plpgsql as $$ begin execute 'reset role'; end $$;
-- exécute une requête et vérifie qu'elle échoue avec ce message
create function t.fails(q text, msg text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then
    if sqlerrm like '%' || msg || '%' then return; end if;
    raise exception 'FAUX MESSAGE pour [%] : attendu "%", reçu "%"', q, msg, sqlerrm;
  end;
  raise exception 'AURAIT DÛ ÉCHOUER (%): %', msg, q;
end $$;
create function t.eq(a anyelement, b anyelement, what text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ECHEC %: attendu %, obtenu %', what, b, a; end if; raise notice 'ok  %', what; end $$;
create function t.cat(m text) returns uuid language sql security definer as $$ select id from public.dealership_catalog where model_key = m $$;
create function t.vid(m text) returns uuid language sql security definer as $$ select id from public.garage_vehicles where model_key = m $$;
create function t.lid() returns uuid language sql security definer as $$ select id from public.listings where status = 'open' limit 1 $$;
create function t.trid() returns uuid language sql security definer as $$ select id from public.trades where status = 'pending' limit 1 $$;
create function t.rid() returns uuid language sql security definer as $$ select id from public.taxi_requests order by created_at desc limit 1 $$;
create function t.rid_req() returns uuid language sql security definer as $$ select id from public.taxi_requests where status = 'requested' limit 1 $$;
grant usage on schema t to anon, authenticated;
grant execute on all functions in schema t to anon, authenticated;

-- ---------- inscriptions
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a', 'a@x', '{"username":"alice"}'),
 ('00000000-0000-0000-0000-00000000000b', 'b@x', '{"username":"bob"}'),
 ('00000000-0000-0000-0000-00000000000c', 'c@x', '{"username":"carol"}');
select t.eq((select count(*) from profiles)::int, 3, 'trois profils créés');
select t.eq((select balance from profiles where username = 'alice'), 25000::bigint, 'argent de départ');
select t.fails($$insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), 'd@x', '{"username":"ALICE"}')$$, 'username_taken');
select t.fails($$insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), 'e@x', '{"username":"bad name!"}')$$, 'username_invalid');
select t.fails($$insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), 'f@x', '{}')$$, 'username_invalid');
select t.eq((select count(*) from profiles)::int, 3, 'inscriptions refusées : aucun profil en plus');

-- ---------- sécurité : aucune écriture directe
select t.login('00000000-0000-0000-0000-00000000000a');
select t.fails($$update public.profiles set balance = 999999 where username = 'alice'$$, 'permission denied');
select t.fails($$insert into public.garage_vehicles (owner_id, slot, model_key) values (auth.uid(), 0, 'covet')$$, 'permission denied');
select t.fails($$update public.server_config set value = '0'$$, 'permission denied');
select t.fails($$select private.add_money(auth.uid(), 1000000, 'admin')$$, 'permission denied');
select t.eq((select count(*) from public.profiles)::int, 1, 'RLS : un joueur ne voit que son profil');
select t.anon();
select t.fails($$select public.get_me()$$, 'permission denied');
select t.eq(jsonb_array_length(public.get_leaderboard(10)), 3, 'classement public (anon)');
select t.root();

-- ---------- argent entre joueurs
select t.login('00000000-0000-0000-0000-00000000000a');
select public.send_money('bob', 1000);
select t.fails($$select public.send_money('bob', 99999999)$$, 'over_limit');
select t.fails($$select public.send_money('bob', 1000000)$$, 'insufficient_funds');
select t.fails($$select public.send_money('alice', 10)$$, 'self_transfer');
select t.fails($$select public.send_money('bob', -5)$$, 'bad_amount');
select t.fails($$select public.send_money('nobody', 5)$$, 'unknown_user');
select t.root();
select t.eq((select balance from profiles where username = 'alice'), 24000::bigint, 'alice a payé');
select t.eq((select balance from profiles where username = 'bob'), 26000::bigint, 'bob a reçu');

-- ---------- admin
select t.login('00000000-0000-0000-0000-00000000000b');
select t.fails($$select public.admin_give_money('bob', 1000000)$$, 'forbidden');
select t.fails($$select public.admin_set_config('starting_money', '1')$$, 'forbidden');
select t.root();
update profiles set is_admin = true where username = 'alice';
select t.login('00000000-0000-0000-0000-00000000000a');
select public.admin_give_money('bob', 5000, 'cadeau');
select t.eq((select balance from public.profiles where username = 'alice'), 24000::bigint, 'admin : son solde ne bouge pas');
select public.admin_give_money('carol', -999999);
select public.admin_give_money('carol', 20000);
select t.root();
select t.eq((select balance from profiles where username = 'bob'), 31000::bigint, 'admin a donné 5000 à bob');
select t.eq((select balance from profiles where username = 'carol'), 20000::bigint, 'retrait admin plafonné à 0 puis don');

-- ---------- concessionnaire & garage (4 places)
select t.login('00000000-0000-0000-0000-00000000000a');
select public.admin_give_money('bob', 30000);          -- bob : 61000
select public.admin_give_money('alice', 40000);        -- alice : 64000
select t.login('00000000-0000-0000-0000-00000000000b');
select public.buy_vehicle(t.cat('covet'));
select public.buy_vehicle(t.cat('pessima'));
select public.buy_vehicle(t.cat('sunburst2'));
select public.buy_vehicle(t.cat('vivace'));
select t.fails($$select public.buy_vehicle(t.cat('miramar'))$$, 'garage_full');
select t.fails($$select public.buy_vehicle(t.cat('miramar'), 9)$$, 'bad_slot');
select t.eq(jsonb_array_length(public.get_me() -> 'vehicles'), 4, 'garage de 4 places rempli');
select t.eq((public.get_me() -> 'profile' ->> 'balance')::bigint, 61000::bigint - 45500, 'achats débités');
select t.root();
-- vente au concessionnaire : 50 % de la valeur
select t.login('00000000-0000-0000-0000-00000000000b');
select public.sell_vehicle_to_dealer(t.vid('vivace'));   -- +8000
select t.eq((public.get_me() -> 'profile' ->> 'balance')::bigint, 61000::bigint - 45500 + 8000, 'rachat à 50 %');
select t.eq(jsonb_array_length(public.get_me() -> 'vehicles'), 3, 'place libérée');
select t.root();

-- ---------- annonces (vente privée) : alice achète la Covet de bob
select t.login('00000000-0000-0000-0000-00000000000b');
select public.create_listing(t.vid('covet'), 8000, 'Peu servie');
select t.fails($$select public.create_listing(t.vid('covet'), 9000)$$, 'already_listed');
select t.fails($$select public.sell_vehicle_to_dealer(t.vid('covet'))$$, 'vehicle_listed');
select t.fails($$select public.buy_listing(t.lid())$$, 'own_listing');
select t.root();
select t.login('00000000-0000-0000-0000-00000000000a');
select t.eq(jsonb_array_length(public.get_market()), 1, 'annonce visible par les autres');
select t.fails($$select public.buy_listing(gen_random_uuid())$$, 'listing_unavailable');
select public.buy_listing(t.lid());
select t.fails($$select public.buy_listing(t.lid())$$, 'listing_unavailable');
select t.root();
select t.eq((select owner_id from garage_vehicles where model_key = 'covet'), '00000000-0000-0000-0000-00000000000a'::uuid, 'véhicule transféré');
select t.eq((select balance from profiles where username = 'alice'), 64000::bigint - 8000, 'acheteur débité');
select t.eq((select balance from profiles where username = 'bob'), 61000::bigint - 45500 + 8000 + 7600, 'vendeur payé moins 5 % de commission');

-- ---------- échanges directs : Alice (Covet) <-> Bob (Pessima) + 500 de Bob
select t.login('00000000-0000-0000-0000-00000000000a');
select public.propose_trade('bob', t.vid('covet'), t.vid('pessima'), -500);
select t.fails($$select public.propose_trade('alice', null, null, 0)$$, 'self_trade');
select t.fails($$select public.propose_trade('bob', t.vid('pessima'), null, 0)$$, 'not_found');
select t.fails($$select public.respond_trade(t.trid(), true)$$, 'not_found');   -- le proposeur ne peut pas accepter
select t.root();
select t.login('00000000-0000-0000-0000-00000000000b');
select t.eq(jsonb_array_length(public.get_trades()), 1, 'échange visible par la cible');
select public.respond_trade(t.trid(), true);
select t.root();
select t.eq((select owner_id from garage_vehicles where model_key = 'pessima'), '00000000-0000-0000-0000-00000000000a'::uuid, 'pessima chez alice');
select t.eq((select owner_id from garage_vehicles where model_key = 'covet'), '00000000-0000-0000-0000-00000000000b'::uuid, 'covet chez bob');
select t.eq((select count(*) from garage_vehicles where owner_id = '00000000-0000-0000-0000-00000000000a')::int, 1, 'pas de véhicule perdu / dupliqué');
-- échange à sens unique (don) + refus
select t.login('00000000-0000-0000-0000-00000000000a');
select public.propose_trade('carol', t.vid('pessima'), null, 1000);   -- alice vend à carol 1000 : carol doit payer... (cash>0 = alice paie)
select t.root();
select t.login('00000000-0000-0000-0000-00000000000c');
select public.respond_trade(t.trid(), false);
select t.root();
select t.eq((select status from trades order by created_at desc limit 1), 'declined', 'refus enregistré');

-- ---------- taxi entre joueurs : carol (passagère) -> bob (chauffeur)
update server_config set value = '1000' where key = 'max_speed_mps';          -- pour pouvoir tester 'too_fast' avec une seule course longue
update server_config set value = '60' where key = 'max_speed_mps';
select t.login('00000000-0000-0000-0000-00000000000c');
select t.fails($$select public.request_taxi('west_coast_usa', '{"x":0,"y":0}', '{"x":10,"y":10}')$$, 'too_short');
select t.fails($$select public.request_taxi('west_coast_usa', '{"x":"a"}', '{"x":10,"y":10}')$$, 'bad_position');
select public.request_taxi('west_coast_usa', '{"x":0,"y":0}', '{"x":3000,"y":0}', 3600);   -- 3.6 km : 8 + 3*3.6 = 19
select t.fails($$select public.request_taxi('west_coast_usa', '{"x":0,"y":0}', '{"x":3000,"y":0}')$$, 'already_active');
select t.root();
select t.eq((select balance from profiles where username = 'carol'), 20000::bigint - 19, 'course réservée (séquestre)');
select t.login('00000000-0000-0000-0000-00000000000b');
select t.eq(jsonb_array_length(public.get_open_taxi_requests('west_coast_usa')), 1, 'demande visible du chauffeur');
select public.accept_taxi_request(t.rid());
select t.fails($$select public.taxi_pickup(t.rid(), '{"x":900,"y":0}')$$, 'too_far');
select public.taxi_pickup(t.rid(), '{"x":20,"y":0}');
select t.fails($$select public.taxi_complete(t.rid(), '{"x":0,"y":0}')$$, 'too_far');
select t.fails($$select public.taxi_complete(t.rid(), '{"x":3000,"y":0}')$$, 'too_fast');
select t.root();
update taxi_requests set picked_up_at = now() - interval '10 minutes';
select t.login('00000000-0000-0000-0000-00000000000b');
select public.taxi_complete(t.rid(), '{"x":3010,"y":0}');
select t.fails($$select public.taxi_complete(t.rid(), '{"x":3010,"y":0}')$$, 'request_unavailable');
select t.root();
select t.eq((select balance from profiles where username = 'bob'), 61000::bigint - 45500 + 8000 + 7600 - 500 + 19, 'chauffeur payé (course +19, échange -500)');
select t.eq((select status from taxi_requests), 'completed', 'course terminée');
-- annulation par la passagère : remboursée ; expiration : remboursée
select t.login('00000000-0000-0000-0000-00000000000c');
select public.request_taxi('west_coast_usa', '{"x":0,"y":0}', '{"x":2000,"y":0}');
select public.cancel_taxi_request(t.rid_req());
select public.request_taxi('west_coast_usa', '{"x":0,"y":0}', '{"x":2000,"y":0}');
select t.root();
update taxi_requests set expires_at = now() - interval '1 second' where status = 'requested';
select t.login('00000000-0000-0000-0000-00000000000c');
select public.get_me();
select t.root();
select t.eq((select count(*) from taxi_requests where status = 'expired')::int, 1, 'demande expirée');
select t.eq((select balance from profiles where username = 'carol'), 20000::bigint - 19, 'remboursements (annulation + expiration)');

-- ---------- jobs : taxi PNJ, bus, taxi IA
select t.login('00000000-0000-0000-0000-00000000000b');
select t.fails($$select public.start_job('hack', 'x', '{"x":0,"y":0}', '{"x":2000,"y":0}')$$, 'bad_kind');
create temp table jid (id uuid, kind text);
grant all on jid to authenticated;
insert into jid select (public.start_job('npc_taxi', 'west_coast_usa', '{"x":0,"y":0}', '{"x":2000,"y":0}', 2200) ->> 'id')::uuid, 'npc';
select t.fails($$select public.complete_job((select id from jid where kind = 'npc'), '{"x":2000,"y":0}')$$, 'job_unavailable');   -- pas embarqué
select t.fails($$select public.board_job((select id from jid where kind = 'npc'), '{"x":900,"y":0}')$$, 'too_far');
select public.board_job((select id from jid where kind = 'npc'), '{"x":10,"y":0}');
select t.fails($$select public.complete_job((select id from jid where kind = 'npc'), '{"x":2000,"y":0}')$$, 'too_fast');
select t.root();
update jobs set boarded_at = now() - interval '10 minutes';
select t.login('00000000-0000-0000-0000-00000000000b');
select t.eq((public.complete_job((select id from jid where kind = 'npc'), '{"x":2000,"y":0}') ->> 'paid')::int, 15, 'taxi PNJ payé (8 + 3 x 2,2 km)');
-- plafond horaire : on le baisse, le gain est tronqué
select t.root();
update server_config set value = '20' where key = 'npc_income_cap_per_hour';
select t.login('00000000-0000-0000-0000-00000000000b');
insert into jid select (public.start_job('bus_leg', 'west_coast_usa', '{"x":0,"y":0}', '{"x":5000,"y":0}') ->> 'id')::uuid, 'bus';
select public.board_job((select id from jid where kind = 'bus'), '{"x":0,"y":0}');
select t.root();
update jobs set boarded_at = now() - interval '1 hour';
select t.login('00000000-0000-0000-0000-00000000000b');
select t.eq((public.complete_job((select id from jid where kind = 'bus'), '{"x":5000,"y":0}') ->> 'capped')::boolean, true, 'plafond horaire appliqué au bus');
select t.eq((select sum(amount) from public.transactions where kind in ('npc_taxi', 'bus'))::int, 20, 'gains serveur limités au plafond');
-- taxi IA : séquestre puis remboursement si annulé avant d'embarquer
select t.eq((public.get_me() -> 'profile' ->> 'balance')::bigint > 0, true, 'solde ok');
select t.root();
select balance as bob_before from profiles where username = 'bob' \gset
select t.login('00000000-0000-0000-0000-00000000000b');
insert into jid select (public.start_job('bot_taxi', 'west_coast_usa', '{"x":0,"y":0}', '{"x":4000,"y":0}') ->> 'id')::uuid, 'bot';
select public.cancel_job((select id from jid where kind = 'bot'));
select t.root();
select t.eq((select balance from profiles where username = 'bob'), :bob_before::bigint, 'taxi IA annulé = remboursé');

-- ---------- classement et invariant comptable
select t.eq((public.get_leaderboard(3) -> 0 ->> 'username') is not null, true, 'classement');
select t.eq((select count(*) from profiles p where p.balance <> (select coalesce(sum(amount), 0) from transactions x where x.user_id = p.id))::int, 0,
            'INVARIANT : solde = somme du journal pour chaque joueur');
select t.eq((select count(*) from profiles where balance < 0)::int, 0, 'aucun solde négatif');

-- ---------- serveurs de jeu (4 joueurs, pseudo obligatoire, positions des autres joueurs)
select t.root();
create function t.srv(n text) returns uuid language sql security definer as $$ select id from public.game_servers where name = n $$;
grant execute on function t.srv(text) to anon, authenticated;
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000d', 'd@x', '{"username":"dave"}'),
 ('00000000-0000-0000-0000-00000000000e', 'e@x', '{"username":"erin"}'),
 ('00000000-0000-0000-0000-00000000000f', 'f@x', '{"username":"frank"}');
select t.eq((select count(*) from game_servers)::int, 3, 'trois serveurs de départ');
select t.eq((select max_players from game_servers where name = 'Serveur 1'), 4, '4 joueurs max par serveur');

select t.anon();
select t.fails($$select public.join_server(t.srv('Serveur 1'))$$, 'permission denied');
select t.login('00000000-0000-0000-0000-00000000000a');
select t.fails($$select * from public.server_members$$, 'permission denied');
select t.fails($$select * from public.game_servers$$, 'permission denied');
select t.fails($$select public.server_sync('l', null, null, null, null)$$, 'not_in_server');

select public.join_server(t.srv('Serveur 1'));
select t.login('00000000-0000-0000-0000-00000000000b'); select public.join_server(t.srv('Serveur 1'));
select t.login('00000000-0000-0000-0000-00000000000c'); select public.join_server(t.srv('Serveur 1'));
select t.login('00000000-0000-0000-0000-00000000000d'); select public.join_server(t.srv('Serveur 1'));
select t.login('00000000-0000-0000-0000-00000000000e');
select t.fails($$select public.join_server(t.srv('Serveur 1'))$$, 'server_full');
select t.login('00000000-0000-0000-0000-00000000000a');
select public.join_server(t.srv('Serveur 1'));   -- déjà dedans : pas d'erreur, pas de doublon
select t.eq((public.get_servers() -> 0 ->> 'count')::int, 4, 'serveur plein : 4 joueurs');
select t.eq(public.get_servers() -> 0 -> 'players', '["alice","bob","carol","dave"]'::jsonb, 'les pseudos sont visibles dans la liste');

-- pseudo obligatoire
select t.root();
update profiles set username_confirmed = false where username = 'erin';
select t.login('00000000-0000-0000-0000-00000000000e');
select t.fails($$select public.join_server(t.srv('Serveur 2'))$$, 'username_required');
select t.fails($$select public.set_username('alice')$$, 'username_taken');
select t.fails($$select public.set_username('ALICE')$$, 'username_taken');
select t.fails($$select public.set_username('x')$$, 'username_invalid');
select public.set_username('erin_ok');
select t.fails($$select public.set_username('erin_two')$$, 'username_already_set');
select public.join_server(t.srv('Serveur 2'));
select t.root();
select t.eq((select username from profiles where id = '00000000-0000-0000-0000-00000000000e'), 'erin_ok', 'pseudo choisi enregistré');

-- synchro : je reçois les autres (pas moi), avec pseudo, position et véhicule
select t.login('00000000-0000-0000-0000-00000000000b');
select public.server_sync('west_coast_usa', '{"x":10.5,"y":20,"z":3}', '[0,0,0,1]', '[1,2,3]', '{"model":"covet","config":"base"}');
select t.login('00000000-0000-0000-0000-00000000000a');
select t.eq(jsonb_array_length(public.server_sync('west_coast_usa', '{"x":1,"y":2,"z":3}', '[0,0,0,1]', '[0,0,0]', '{"model":"unicycle"}') -> 'players'), 3, 'alice voit les 3 autres joueurs');
select t.eq((public.server_sync('west_coast_usa', '{"x":1,"y":2,"z":3}', null, null, null) -> 'players' -> 0 ->> 'username'), 'bob', 'pseudo de bob reçu');
select t.eq((public.server_sync('west_coast_usa', null, null, null, null) -> 'players' -> 0 -> 'pos' ->> 'x')::float8, 10.5::float8, 'position de bob reçue');
select t.eq((public.server_sync('west_coast_usa', null, null, null, null) -> 'players' -> 0 -> 'veh' ->> 'model'), 'covet', 'véhicule de bob reçu');
select t.eq((public.server_sync('west_coast_usa', null, null, null, null) -> 'players' -> 0 -> 'rot'), '[0, 0, 0, 1]'::jsonb, 'rotation de bob reçue');
-- données absurdes ignorées, pas d'injection dans le véhicule
select public.server_sync('west_coast_usa', '{"x":"abc"}', '[1,2]', '[1e99,0,0]', '{"model":"../../x; drop"}');
select t.root();
select t.eq((select m.veh ->> 'model' from server_members m join profiles p on p.id = m.user_id where p.username = 'alice'), 'unicycle', 'véhicule invalide ignoré (ancien conservé)');
select t.eq((select m.pos ->> 'x' from server_members m join profiles p on p.id = m.user_id where p.username = 'alice'), '1', 'position invalide ignorée');

-- changer de serveur = quitter l'ancien ; un joueur absent depuis trop longtemps libère sa place
select t.login('00000000-0000-0000-0000-00000000000b');
select public.join_server(t.srv('Serveur 3'));
select t.eq((public.server_sync('l', null, null, null, null) -> 'server' ->> 'name'), 'Serveur 3', 'bob est sur le serveur 3');
select t.login('00000000-0000-0000-0000-00000000000e');
select public.join_server(t.srv('Serveur 1'));   -- la place laissée par bob est libre
select t.eq((public.get_servers() -> 0 ->> 'count')::int, 4, 'place de bob reprise par erin');
select t.root();
update server_members set last_seen = now() - interval '5 minutes' where user_id = '00000000-0000-0000-0000-00000000000c';
select t.login('00000000-0000-0000-0000-00000000000f');
select public.join_server(t.srv('Serveur 1'));   -- carol inactive : sa place est libérée
select t.eq((select count(*) from (select jsonb_array_elements_text(public.get_servers() -> 0 -> 'players')) x)::int, 4, 'joueur inactif retiré');
select t.root();
select t.eq((select count(*) from server_members where user_id = '00000000-0000-0000-0000-00000000000c')::int, 0, 'carol n''est plus sur le serveur');
select t.login('00000000-0000-0000-0000-00000000000c');
select t.fails($$select public.server_sync('l', null, null, null, null)$$, 'not_in_server');

-- garage d'un autre joueur
select t.login('00000000-0000-0000-0000-00000000000b');
select t.eq(jsonb_typeof(public.get_player_garage('ALICE')), 'array', 'garage d''un autre joueur lisible (liste)');
select t.anon();
select t.fails($$select public.get_player_garage('alice')$$, 'permission denied');

-- quitter, administration
select t.login('00000000-0000-0000-0000-00000000000f');
select public.leave_server();
select t.fails($$select public.server_sync('l', null, null, null, null)$$, 'not_in_server');
select t.fails($$select public.admin_create_server('Pirate', 4)$$, 'forbidden');
select t.fails($$select public.admin_kick('alice')$$, 'forbidden');
select t.login('00000000-0000-0000-0000-00000000000a');
select t.root(); update profiles set is_admin = true where username = 'alice'; select t.login('00000000-0000-0000-0000-00000000000a');
select public.admin_create_server('Serveur 4', 4);
select t.fails($$select public.admin_create_server('serveur 4', 4)$$, 'duplicate key');
select public.admin_kick('alice');
select t.fails($$select public.server_sync('l', null, null, null, null)$$, 'not_in_server');
select t.root(); update profiles set is_admin = false where username = 'alice';
select t.eq((select count(*) from game_servers)::int, 4, 'serveur créé par un admin');
select t.eq((select count(*) from profiles p where p.balance <> (select coalesce(sum(amount), 0) from transactions x where x.user_id = p.id))::int, 0,
            'INVARIANT toujours vrai après les tests de serveurs');

\echo === TOUS LES TESTS PASSENT ===
