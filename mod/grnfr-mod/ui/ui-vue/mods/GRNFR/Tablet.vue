<template>
  <!-- Tablette du garage : s'ouvre seulement devant SON garage (touche O), jamais depuis le menu principal.
       Écran d'accueil à applications, comme une vraie tablette ; chaque application remplace l'écran. -->
  <div v-if="net.tablet.open" class="tbw" @focusin="focus($event, true)" @focusout="focus($event, false)">
    <div class="device">
      <div class="screen">
        <div class="status">
          <span class="clock">{{ clock }}</span>
          <span class="place">{{ net.tablet.name || L('Garage', 'Garage') }}</span>
          <span class="bal">{{ net.username }} · <b>{{ money(profile.balance) }}</b></span>
          <button type="button" class="x" :title="L('Fermer', 'Close')" @click="ui('tablet.close')">✕</button>
        </div>

        <div v-if="app" class="apphead">
          <button type="button" class="back" @click="go(null)">‹ {{ L('Accueil', 'Home') }}</button>
          <span class="apptitle">{{ appName(app) }}</span>
        </div>
        <p v-if="net.error" class="err">{{ net.error }}</p>
        <p v-if="msg" class="ok">{{ msg }}</p>

        <!-- ACCUEIL -->
        <div v-if="!app" class="home">
          <button v-for="a in apps" :key="a.id" type="button" class="icon" @click="go(a.id)">
            <span class="ic" :style="{ background: a.color }"><svg viewBox="0 0 24 24"><path :d="a.path" /></svg></span>
            <span class="lbl">{{ appName(a.id) }}</span>
            <span v-if="a.id === 'trades' && incoming" class="badge">{{ incoming }}</span>
          </button>
        </div>

        <!-- MES VOITURES : sortir (sur une place du garage), ranger, verrouiller, assurance, vendre -->
        <main v-else-if="app === 'garage'">
          <p class="mut">{{ L('Places utilisées', 'Slots used') }} : {{ vehicles.length }}/{{ profile.garage_slots || 0 }}</p>
          <div class="grid">
            <div v-for="v in vehicles" :key="v.id" class="tile veh">
              <VehImg :info="vi(v.model_key, v.config_key)" />
              <div class="tname">{{ v.nickname || fullName(vi(v.model_key, v.config_key), v.model_key) }}</div>
              <div class="mut">{{ specLine(vi(v.model_key, v.config_key)) || v.model_key }}</div>
              <div class="price">{{ money(v.value) }}</div>
              <div class="mut classes">{{ L('Perf', 'Perf') }} {{ stars(v.perf_class) }} · {{ L('Confort', 'Comfort') }} {{ stars(v.comfort_class) }}</div>
              <div class="tags">
                <span class="tag" :class="'ins-' + (v.insurance || 'none')">{{ planName(v.insurance) }}</span>
                <span v-if="v.listed" class="tag">{{ L('En vente', 'Listed') }}</span>
                <span v-if="out(v)" class="tag on">{{ L('Sorti', 'Out') }}</span>
                <span v-if="locked(v)" class="tag lock">🔒 {{ L('Verrouillé', 'Locked') }}</span>
              </div>
              <div class="acts">
                <button v-if="!out(v)" type="button" class="btn" :disabled="v.listed" @click="ui('garage.spawn', { id: v.id, model_key: v.model_key, config_key: v.config_key, nickname: v.nickname })">{{ L('Sortir au garage', 'Take out') }}</button>
                <template v-else>
                  <button type="button" class="btn" @click="ui('garage.store', { id: v.id })">{{ L('Ranger', 'Store') }}</button>
                  <button type="button" class="btn dim" @click="ui('garage.lock', { id: v.id, on: !locked(v) })">{{ locked(v) ? '🔓 ' + L('Déverrouiller', 'Unlock') : '🔒 ' + L('Verrouiller', 'Lock') }}</button>
                  <button type="button" class="btn dim" @click="openCustomize(v)">🛠️ {{ L('Personnaliser', 'Customize') }}</button>
                </template>
                <button type="button" class="btn dim" @click="insFor = insFor === v.id ? null : v.id">{{ L('Assurance', 'Insurance') }}</button>
                <template v-if="!v.listed">
                  <button type="button" class="btn dim" @click="sellDealer(v)">{{ L('Vendre au concessionnaire', 'Sell to dealer') }}</button>
                  <button type="button" class="btn dim" @click="sellVehicle(v)">{{ L('Vendre', 'Sell') }}</button>
                </template>
              </div>
              <div v-if="insFor === v.id" class="plans small">
                <button v-for="pl in plans" :key="pl.tier" type="button" class="plan" :class="{ on: (v.insurance || 'none') === pl.tier }"
                        @click="act(() => rpc('set_vehicle_insurance', { p_vehicle_id: v.id, p_insurance: pl.tier }), () => { insFor = null })">
                  <b>{{ planName(pl.tier) }}</b>
                  <span>{{ rank(pl.tier) > rank(v.insurance) ? money(premium(pl, v.value)) : L('gratuit', 'free') }}</span>
                </button>
              </div>
            </div>
            <div v-for="n in emptySlots" :key="'empty' + n" class="tile veh empty-slot">
              <div class="tname mut">{{ L('Place libre', 'Free slot') }}</div>
              <button type="button" class="btn" @click="go('dealer')">{{ L('Aller à la concession', 'Go to the dealership') }}</button>
            </div>
          </div>

          <!-- Salarié : livre et rapporte tout seul tant qu'on est en ligne, tous les 100 km un trajet est payé
               (revenu - salaire, tiré au hasard : pas forcément gagnant). -->
          <div class="tile employee">
            <h4>👷 {{ L('Salarié', 'Employee') }}</h4>
            <template v-if="employee.active">
              <p class="mut">{{ employee.level_label }} ({{ L('niveau', 'level') }} {{ employee.level }})</p>
              <p class="mut">{{ L('Progression', 'Progress') }} : {{ km(employee.distance_m) }} / 100 km</p>
              <p class="mut">{{ L('Revenu par trajet', 'Income per trip') }} : {{ money(employee.income_min_100km) }} – {{ money(employee.income_max_100km) }}
                ({{ L('salaire', 'wage') }} {{ money(employee.wage_per_100km) }})</p>
              <p class="mut">{{ L('Total gagné', 'Total earned') }} : {{ money(employee.total_earned) }}</p>
              <div class="acts">
                <button v-if="employee.next" type="button" class="btn" @click="act(() => rpc('upgrade_employee'))">
                  {{ L('Promouvoir', 'Promote') }} : {{ employee.next.label }} ({{ money(employee.next.upgrade_cost) }})
                </button>
                <span v-else class="mut">{{ L('Niveau maximum.', 'Max level.') }}</span>
                <button type="button" class="btn dim" @click="act(() => rpc('fire_employee'))">{{ L('Licencier', 'Fire') }}</button>
              </div>
            </template>
            <template v-else>
              <p class="mut">{{ L('Embauchez un salarié : il livre et rapporte de l\'argent automatiquement tous les 100 km, tant que vous êtes en ligne.',
                'Hire an employee: they deliver and bring back money automatically every 100 km, as long as you are online.') }}</p>
              <button type="button" class="btn" @click="act(() => rpc('hire_employee'))">
                {{ L('Embaucher', 'Hire') }} : {{ employee.next?.label }} ({{ money(employee.next?.upgrade_cost) }})
              </button>
            </template>
          </div>
        </main>

        <!-- JOUEURS : on choisit un joueur du serveur dans la liste, puis l'action -->
        <main v-else-if="app === 'players'" class="split">
          <aside class="plist">
            <p v-if="!net.players.length" class="empty">{{ L('Personne d\'autre sur le serveur.', 'Nobody else on the server.') }}</p>
            <button v-for="p in net.players" :key="p.username" type="button" class="pl" :class="{ on: sel === p.username }" @click="pick(p.username)">
              <span class="av">{{ p.username.slice(0, 1).toUpperCase() }}</span>
              <span><b>{{ p.username }}</b><br /><small class="mut">{{ p.level === net.game.level ? L('Sur votre carte', 'On your map') : L('Autre carte', 'Other map') }}<template v-if="p.veh"> · {{ p.veh.model }}</template></small></span>
            </button>
          </aside>
          <section v-if="sel" class="pact">
            <h3>{{ sel }}</h3>
            <div class="seg">
              <button v-for="m in ['money', 'car', 'trade']" :key="m" type="button" :class="{ on: mode === m }" @click="mode = m">{{ modeName(m) }}</button>
            </div>
            <div v-if="mode === 'money'" class="panel">
              <label>{{ L('Montant', 'Amount') }}</label>
              <div class="chips"><button v-for="a in [100, 500, 1000, 5000, 10000]" :key="a" type="button" class="chip" @click="f.amount = a">{{ money(a) }}</button></div>
              <input v-model.number="f.amount" type="number" min="1" />
              <button type="button" class="btn" :disabled="!(f.amount > 0)" @click="act(() => rpc('send_money', { p_username: sel, p_amount: f.amount }), () => { f.amount = null })">{{ L('Envoyer', 'Send') }} {{ money(f.amount) }}</button>
            </div>
            <div v-else-if="mode === 'car'" class="panel">
              <label>{{ L('Véhicule à donner (il devra accepter)', 'Vehicle to give (they must accept)') }}</label>
              <div class="pickrow">
                <button v-for="v in giftable" :key="v.id" type="button" class="pk" :class="{ on: f.gift === v.id }" @click="f.gift = v.id">{{ v.nickname || v.model_key }}<small>{{ money(v.value) }}</small></button>
              </div>
              <p v-if="!giftable.length" class="mut">{{ L('Aucun véhicule disponible (rangé et pas en vente).', 'No vehicle available (stored and not listed).') }}</p>
              <button type="button" class="btn" :disabled="!f.gift" @click="act(() => rpc('propose_trade', { p_username: sel, p_offered: f.gift, p_wanted: null, p_cash: 0 }), () => { f.gift = '' })">{{ L('Donner', 'Give') }}</button>
            </div>
            <div v-else class="panel">
              <label>{{ L('Je donne', 'I give') }}</label>
              <div class="pickrow">
                <button type="button" class="pk" :class="{ on: !f.offer }" @click="f.offer = ''">{{ L('Rien', 'Nothing') }}</button>
                <button v-for="v in giftable" :key="v.id" type="button" class="pk" :class="{ on: f.offer === v.id }" @click="f.offer = v.id">{{ v.nickname || v.model_key }}<small>{{ money(v.value) }}</small></button>
              </div>
              <label>{{ L('Je veux', 'I want') }}</label>
              <p v-if="theirsLoading" class="mut">…</p>
              <div v-else class="pickrow">
                <button type="button" class="pk" :class="{ on: !f.want }" @click="f.want = ''">{{ L('Rien', 'Nothing') }}</button>
                <button v-for="v in theirs" :key="v.id" type="button" class="pk" :class="{ on: f.want === v.id }" @click="f.want = v.id">{{ v.nickname || v.model_key }}<small>{{ money(v.value) }}</small></button>
              </div>
              <label>{{ L('Argent en plus de ma part (négatif = il me paie)', 'Cash from me (negative = they pay me)') }}</label>
              <input v-model.number="f.cash" type="number" />
              <button type="button" class="btn" :disabled="!f.offer && !f.want" @click="act(() => rpc('propose_trade', { p_username: sel, p_offered: f.offer || null, p_wanted: f.want || null, p_cash: f.cash || 0 }), loadTrades)">{{ L('Proposer l\'échange', 'Propose trade') }}</button>
            </div>
          </section>
          <section v-else class="pact empty">{{ L('Choisissez un joueur dans la liste.', 'Pick a player from the list.') }}</section>
        </main>

        <!-- ÉCHANGES REÇUS / ENVOYÉS -->
        <main v-else-if="app === 'trades'">
          <p v-if="!d.trades.length" class="empty">{{ L('Aucune proposition en cours.', 'No pending offer.') }}</p>
          <div v-for="x in d.trades" :key="x.id" class="tile wide">
            <div class="tname">{{ x.direction === 'in' ? L('De ', 'From ') + x.proposer : L('À ', 'To ') + x.target }}</div>
            <div class="swap">
              <span>{{ x.offered ? (x.offered.nickname || x.offered.model_key) : L('rien', 'nothing') }}</span><span class="arr">⇄</span>
              <span>{{ x.wanted ? (x.wanted.nickname || x.wanted.model_key) : L('rien', 'nothing') }}</span>
              <span v-if="x.cash_from_proposer" class="mut"> · {{ money(x.cash_from_proposer) }}</span>
            </div>
            <div class="acts">
              <template v-if="x.direction === 'in'">
                <button type="button" class="btn" @click="act(() => rpc('respond_trade', { p_trade_id: x.id, p_accept: true, p_slot: null }), loadTrades)">{{ L('Accepter', 'Accept') }}</button>
                <button type="button" class="btn dim" @click="act(() => rpc('respond_trade', { p_trade_id: x.id, p_accept: false, p_slot: null }), loadTrades)">{{ L('Refuser', 'Refuse') }}</button>
              </template>
              <button v-else type="button" class="btn dim" @click="act(() => rpc('cancel_trade', { p_trade_id: x.id }), loadTrades)">{{ L('Annuler', 'Cancel') }}</button>
            </div>
          </div>
        </main>

        <!-- CONCESSION : choisir un véhicule, négocier avec le vendeur (bot côté serveur), choisir l'assurance -->
        <main v-else-if="app === 'dealer' && !buy.c">
          <div class="grid">
            <div v-for="c in d.catalog" :key="c.id" class="tile click veh" @click="openBuy(c)">
              <VehImg :info="vi(c.model_key, c.config_key)" />
              <div class="tname">{{ c.name }}</div>
              <div class="mut">{{ specLine(vi(c.model_key, c.config_key)) }}</div>
              <div class="price">{{ money(c.price) }}</div>
              <div class="mut classes">{{ L('Perf', 'Perf') }} {{ stars(c.perf_class) }} · {{ L('Confort', 'Comfort') }} {{ stars(c.comfort_class) }}</div>
            </div>
          </div>
        </main>
        <main v-else-if="app === 'dealer'" class="buy">
          <section class="nego">
            <button type="button" class="back" @click="buy.c = null">‹ {{ L('Catalogue', 'Catalogue') }}</button>
            <div class="vhead">
              <VehImg :info="vi(buy.c.model_key, buy.c.config_key)" big />
              <div class="vtxt">
                <h3>{{ buy.c.name }}</h3>
                <div class="mut">{{ L('Prix affiché', 'List price') }} : <b>{{ money(buy.c.price) }}</b></div>
                <div class="mut classes">{{ L('Perf', 'Perf') }} {{ stars(buy.c.perf_class) }} · {{ L('Confort', 'Comfort') }} {{ stars(buy.c.comfort_class) }}</div>
                <div class="specs">
                  <div v-for="sp in specs(vi(buy.c.model_key, buy.c.config_key))" :key="sp[0]"><span>{{ sp[0] }}</span><b>{{ sp[1] }}</b></div>
                </div>
              </div>
            </div>
            <p v-if="vi(buy.c.model_key, buy.c.config_key).description" class="desc">{{ vi(buy.c.model_key, buy.c.config_key).description }}</p>
            <div class="chat">
              <div v-for="(m, i) in buy.log" :key="i" class="bubble" :class="m.who">{{ m.text }}</div>
            </div>
            <div class="pat">{{ L('Patience du vendeur', 'Seller patience') }} :
              <span v-for="k in 5" :key="k" class="pdot" :class="{ on: k <= (buy.neg.patience || 0) }" /></div>
            <template v-if="canOffer">
              <div class="inline">
                <input v-model.number="buy.offer" type="number" min="1" :placeholder="L('Votre offre', 'Your offer')" />
                <button type="button" class="btn" :disabled="!(buy.offer > 0) || buy.busy" @click="offer(buy.offer)">{{ L('Proposer', 'Offer') }}</button>
              </div>
              <div class="chips">
                <button v-for="k in [0.95, 0.9, 0.85]" :key="k" type="button" class="chip" @click="buy.offer = Math.round(buy.c.price * k / 50) * 50">-{{ Math.round((1 - k) * 100) }} %</button>
                <button v-if="buy.neg.asking < buy.c.price" type="button" class="chip" @click="offer(buy.neg.asking)">{{ L('Accepter son prix', 'Accept their price') }} ({{ money(buy.neg.asking) }})</button>
              </div>
            </template>
          </section>
          <section class="checkout">
            <h4>{{ L('Assurance', 'Insurance') }}</h4>
            <button v-for="pl in plans" :key="pl.tier" type="button" class="plan wide" :class="{ on: buy.ins === pl.tier }" @click="buy.ins = pl.tier">
              <b>{{ planName(pl.tier) }}</b>
              <span class="mut">{{ planDesc(pl) }}</span>
              <span class="pp">{{ money(premium(pl, buy.c.price)) }}</span>
            </button>
            <div class="total">
              <div><span>{{ L('Véhicule', 'Vehicle') }}</span><b>{{ money(buyPrice) }}</b></div>
              <div><span>{{ L('Assurance', 'Insurance') }}</span><b>{{ money(buyPremium) }}</b></div>
              <div class="sum"><span>Total</span><b>{{ money(buyPrice + buyPremium) }}</b></div>
            </div>
            <button type="button" class="btn big" :disabled="buy.busy || (profile.balance || 0) < buyPrice + buyPremium" @click="purchase">{{ L('Acheter', 'Buy') }}</button>
            <p v-if="(profile.balance || 0) < buyPrice + buyPremium" class="bad small">{{ L('Fonds insuffisants.', 'Not enough money.') }}</p>
          </section>
        </main>

        <!-- ANNONCES -->
        <main v-else-if="app === 'market'">
          <div class="seg">
            <button type="button" :class="{ on: marketTab === 'vehicles' }" @click="marketTab = 'vehicles'">{{ L('Véhicules', 'Vehicles') }}</button>
            <button type="button" :class="{ on: marketTab === 'parts' }" @click="marketTab = 'parts'">{{ L('Pièces', 'Parts') }}</button>
          </div>

          <div v-if="marketTab === 'vehicles'">
            <p v-if="!d.market.length" class="empty">{{ L('Aucune annonce.', 'No listing.') }}</p>
            <div class="grid">
              <div v-for="l in d.market" :key="l.id" class="tile">
                <div class="tname">{{ l.nickname || l.model_key }}</div>
                <div class="mut">{{ l.model_key }} · {{ l.seller }}</div>
                <div class="price">{{ money(l.price) }}</div>
                <div v-if="l.description" class="mut">{{ l.description }}</div>
                <div class="acts">
                  <button v-if="l.seller === net.username" type="button" class="btn dim" @click="act(() => rpc('cancel_listing', { p_listing_id: l.id }), loadMarket)">{{ L('Retirer', 'Withdraw') }}</button>
                  <button v-else type="button" class="btn" @click="act(() => rpc('buy_listing', { p_listing_id: l.id }), loadMarket)">{{ L('Acheter', 'Buy') }}</button>
                </div>
              </div>
            </div>

            <h4 class="submuted">{{ L('Mettre un de mes véhicules en vente', 'List one of my vehicles') }}</h4>
            <p v-if="!sellableVehicles.length" class="empty">{{ L('Aucun véhicule disponible (déjà en vente, ou aucun véhicule).', 'No vehicle available (already listed, or no vehicle).') }}</p>
            <div class="grid">
              <div v-for="v in sellableVehicles" :key="v.id" class="tile">
                <div class="tname">{{ v.nickname || v.model_key }}</div>
                <div class="mut">{{ v.model_key }} · {{ L('valeur', 'value') }} {{ money(v.value) }}</div>
                <div class="inline"><input v-model.number="f['v' + v.id]" type="number" min="1" :placeholder="L('Prix', 'Price')" />
                  <button type="button" class="btn dim" @click="act(() => rpc('create_listing', { p_vehicle_id: v.id, p_price: f['v' + v.id], p_description: null }), loadMarket)">{{ L('Mettre en vente', 'List') }}</button></div>
              </div>
            </div>
          </div>

          <div v-else>
            <h4 class="submuted">{{ L('Annonces de pièces', 'Part listings') }}</h4>
            <p v-if="!d.partMarket.length" class="empty">{{ L('Aucune pièce en vente.', 'No part for sale.') }}</p>
            <div class="grid">
              <div v-for="l in d.partMarket" :key="l.id" class="tile">
                <div class="tname">{{ l.name }}</div>
                <div class="mut">{{ l.model_key }} · {{ slotLabel(l.slot) }} · {{ l.seller }}</div>
                <div class="price">{{ money(l.price) }}</div>
                <div v-if="l.description" class="mut">{{ l.description }}</div>
                <div class="acts">
                  <button v-if="l.seller === net.username" type="button" class="btn dim" @click="act(() => rpc('cancel_part_listing', { p_listing_id: l.id }), loadPartMarket)">{{ L('Retirer', 'Withdraw') }}</button>
                  <button v-else type="button" class="btn" @click="act(() => rpc('buy_part_listing', { p_listing_id: l.id }), loadPartMarket)">{{ L('Acheter', 'Buy') }}</button>
                </div>
              </div>
            </div>

            <h4 class="submuted">{{ L('Mes pièces de rechange', 'My spare parts') }}</h4>
            <p v-if="!d.spareParts.length" class="empty">{{ L('Rien en stock (retirez une pièce à l\'ordinateur du garage pour la garder ici).', 'Nothing in stock (remove a part at the garage computer to keep it here).') }}</p>
            <div class="grid">
              <div v-for="sp in d.spareParts" :key="sp.id" class="tile">
                <div class="tname">{{ sp.name }}</div>
                <div class="mut">{{ sp.model_key }} · {{ slotLabel(sp.slot) }} · {{ L('valeur', 'value') }} {{ money(sp.value) }}</div>
                <div class="acts">
                  <button type="button" class="btn dim" :disabled="!compatibleVehicle(sp)" @click="installSpare(sp)">
                    {{ L('Installer', 'Install') }}<template v-if="compatibleVehicle(sp)"> ({{ compatibleVehicle(sp).nickname || compatibleVehicle(sp).model_key }})</template>
                  </button>
                  <div class="inline"><input v-model.number="f['sp' + sp.id]" type="number" min="1" :placeholder="L('Prix', 'Price')" />
                    <button type="button" class="btn dim" @click="act(() => rpc('create_part_listing', { p_spare_id: sp.id, p_price: f['sp' + sp.id], p_description: null }), loadPartMarket)">{{ L('Mettre en vente', 'List') }}</button></div>
                </div>
                <p v-if="!compatibleVehicle(sp)" class="mut small">{{ L('Aucun véhicule du même modèle pour l\'installer.', 'No vehicle of the same model to install it on.') }}</p>
              </div>
            </div>
          </div>
        </main>

        <!-- TRAVAIL : taxi et bus (les missions arrivent ici) -->
        <main v-else-if="app === 'work'">
          <div class="tile wide">
            <div class="tname">Taxi</div>
            <div class="mut">{{ taxi.duty ? L('En service', 'On duty') : L('Hors service', 'Off duty') }}<template v-if="taxi.duty"> · {{ taxi.rides || 0 }} {{ L('courses', 'rides') }} · {{ money(taxi.earned || 0) }}</template></div>
            <div class="acts">
              <button type="button" class="btn" @click="ui('taxi.duty', { on: !taxi.duty })">{{ taxi.duty ? L('Fin de service', 'Go off duty') : L('Prendre le service', 'Go on duty') }}</button>
              <button v-if="taxi.duty" type="button" class="btn dim" @click="ui('taxi.cancel')">{{ L('Annuler la course', 'Cancel ride') }}</button>
            </div>
          </div>
          <div class="tile wide">
            <div class="tname">Bus</div>
            <div class="mut" v-if="bus.active">
              <template v-if="bus.direction">{{ L('Ligne réelle, direction ', 'Real line, towards ') }}{{ bus.direction }} · </template>
              {{ bus.legs || 0 }} {{ L('arrêts', 'stops') }} · {{ money(bus.earned || 0) }}
            </div>
            <div class="acts">
              <button v-if="!bus.active" type="button" class="btn" @click="ui('bus.start')">{{ L('Commencer la ligne', 'Start the line') }}</button>
              <button v-else type="button" class="btn dim" @click="ui('bus.stop')">{{ L('Arrêter', 'Stop') }}</button>
            </div>
          </div>

          <!-- LIVRAISONS (phase 2) : colis entre vrais points de la carte, selon la capacité de stockage achetée
               à l'ordinateur du garage. Un véhicule déjà sorti avec assez de capacité est nécessaire pour accepter. -->
          <div class="tile wide">
            <div class="tname">{{ L('Livraisons', 'Deliveries') }}</div>
            <template v-if="delivery.active">
              <div class="mut">{{ delivery.senderName || '?' }} → {{ delivery.recipientName || '?' }} · {{ deliveryPhaseLabel(delivery.phase) }}
                <template v-if="delivery.dist != null"> · {{ delivery.dist }} m</template></div>
              <div class="price">{{ money(delivery.fare) }}</div>
              <div class="acts"><button type="button" class="btn dim" @click="ui('delivery.cancel')">{{ L('Annuler', 'Cancel') }}</button></div>
            </template>
            <template v-else>
              <div class="mut">{{ L('Gains de la session', 'Session earnings') }} : {{ money(delivery.earned || 0) }} · {{ delivery.deliveries || 0 }} {{ L('livraison(s)', 'delivery(ies)') }}</div>
              <div class="acts"><button type="button" class="btn" @click="refreshDeliveries">{{ L('Chercher des livraisons', 'Find deliveries') }}</button></div>
              <p v-if="net.deliveryError" class="bad small">{{ net.deliveryError }}</p>
              <div v-for="o in net.deliveryOffers" :key="o.id" class="tile">
                <div class="tname">{{ o.sender_name || '?' }} → {{ o.recipient_name || '?' }}</div>
                <div class="mut">{{ (o.pickup && o.pickup.name) || '?' }} → {{ (o.dropoff && o.dropoff.name) || '?' }} · {{ Math.round(o.route_m / 100) / 10 }} km · {{ o.weight_kg }} kg</div>
                <div class="price">{{ money(o.fare) }}</div>
                <div class="acts">
                  <button type="button" class="btn" :disabled="!vehicleFor(o)" @click="acceptDelivery(o)">
                    {{ L('Accepter', 'Accept') }}<template v-if="vehicleFor(o)"> ({{ vehicleFor(o).nickname || vehicleFor(o).model_key }})</template>
                  </button>
                </div>
                <p v-if="!vehicleFor(o)" class="mut small">{{ L('Aucun véhicule sorti avec assez de stockage.', 'No vehicle out with enough storage.') }}</p>
              </div>
              <p v-if="!net.deliveryOffers.length" class="empty">{{ L('Aucune livraison pour l\'instant : cliquez « Chercher ».', 'No deliveries yet: click "Find".') }}</p>
            </template>
          </div>
        </main>

        <!-- ORDINATEUR DU GARAGE : personnalisation du véhicule sorti (pièces, réglages, peinture, stockage) -->
        <main v-else-if="app === 'customize' && cust.v" class="customize">
          <div class="vhead">
            <VehImg :info="vi(cust.v.model_key, cust.v.config_key)" big />
            <div class="vtxt">
              <h3>{{ cust.v.nickname || fullName(vi(cust.v.model_key, cust.v.config_key), cust.v.model_key) }}</h3>
              <div class="mut">{{ L('Valeur', 'Value') }} : {{ money(cust.v.value) }}</div>
            </div>
          </div>
          <div class="seg">
            <button v-for="t in ['parts', 'tuning', 'paint', 'cargo']" :key="t" type="button" :class="{ on: cust.tab === t }" @click="cust.tab = t">{{ custTabName(t) }}</button>
          </div>

          <div v-if="cust.tab === 'parts'" class="panel wide">
            <p v-if="cust.catalogLoading" class="mut">{{ L('Chargement du catalogue…', 'Loading catalog…') }}</p>
            <p v-else-if="!catalogSlots.length" class="empty">{{ L('Aucune pièce connue pour ce véhicule.', 'No known parts for this vehicle.') }}</p>
            <template v-else>
              <input v-model="partSearch" type="search" class="partsearch" :placeholder="L('Rechercher une pièce…', 'Search for a part…')" />
              <p v-if="partSearch && !filteredSlots.length" class="empty">{{ L('Aucune pièce ne correspond.', 'No part matches.') }}</p>
            </template>
            <div v-for="s in filteredSlots" :key="s.slot" class="tile wide">
              <div class="tname">{{ slotLabel(s.slot) }}</div>
              <div class="mut">{{ currentPartName(s.slot) }}</div>
              <div class="chips">
                <button v-for="o in s.options" :key="o.part" type="button" class="chip" :class="{ on: isInstalled(s.slot, o.part) }"
                        :disabled="cust.busy || isInstalled(s.slot, o.part)" @click="buyPart(s.slot, o.part)">
                  {{ o.name }}<small>{{ money(o.price) }}</small>
                </button>
              </div>
              <button v-if="cust.v.parts && cust.v.parts[s.slot]" type="button" class="btn dim small" :disabled="cust.busy" @click="removePart(s.slot)">{{ L('Retirer', 'Remove') }}</button>
            </div>
          </div>

          <div v-else-if="cust.tab === 'tuning'" class="panel">
            <p class="mut">{{ L('Réglages gratuits. Effet en jeu non encore vérifié (voir CLAUDE.md).', 'Free settings. In-game effect not verified yet (see CLAUDE.md).') }}</p>
            <label>{{ L('Hauteur de caisse (mm)', 'Ride height (mm)') }} : {{ cust.tuning.ride }}</label>
            <input v-model.number="cust.tuning.ride" type="range" min="-30" max="30" />
            <label>{{ L('Pression des pneus (psi)', 'Tire pressure (psi)') }} : {{ cust.tuning.tire }}</label>
            <input v-model.number="cust.tuning.tire" type="range" min="20" max="40" />
            <button type="button" class="btn" :disabled="cust.busy" @click="saveTuning">{{ L('Enregistrer', 'Save') }}</button>
          </div>

          <div v-else-if="cust.tab === 'paint'" class="panel">
            <div v-for="i in cust.paintLayers" :key="i" class="inline">
              <label>{{ L('Couche', 'Layer') }} {{ i }}</label>
              <input v-model="cust.paintHex[i - 1]" type="color" />
            </div>
            <div class="chips">
              <button type="button" class="chip" :disabled="cust.paintLayers >= 3" @click="cust.paintLayers = Math.min(3, cust.paintLayers + 1)">{{ L('+ Couche', '+ Layer') }}</button>
              <button type="button" class="chip" :disabled="cust.paintLayers <= 1" @click="cust.paintLayers = Math.max(1, cust.paintLayers - 1)">{{ L('- Couche', '- Layer') }}</button>
            </div>
            <button type="button" class="btn" :disabled="cust.busy" @click="repaint">{{ L('Repeindre', 'Repaint') }} ({{ money(priceFor('paint')) }})</button>
          </div>

          <div v-else class="panel wide">
            <p class="mut">{{ L('Capacité de stockage actuelle', 'Current storage capacity') }} : <b>{{ cust.v.cargo_capacity || 0 }}</b> {{ L('unité(s)', 'unit(s)') }}</p>
            <p v-if="!catalogCargoSlots.length && !cust.catalogLoading" class="empty">{{ L('Pas d\'emplacement de stockage connu pour ce véhicule.', 'No known storage slot for this vehicle.') }}</p>
            <div v-for="s in catalogCargoSlots" :key="s.slot" class="tile wide">
              <div class="tname">{{ slotLabel(s.slot) }}</div>
              <div class="mut">{{ currentPartName(s.slot) }}</div>
              <div class="chips">
                <button v-for="o in s.options" :key="o.part" type="button" class="chip" :class="{ on: isInstalled(s.slot, o.part) }"
                        :disabled="cust.busy || isInstalled(s.slot, o.part)" @click="buyPart(s.slot, o.part)">
                  {{ o.name }} (+{{ o.cargo_units }})<small>{{ money(o.price) }}</small>
                </button>
              </div>
              <button v-if="cust.v.parts && cust.v.parts[s.slot]" type="button" class="btn dim small" :disabled="cust.busy" @click="removePart(s.slot)">{{ L('Retirer', 'Remove') }}</button>
            </div>
          </div>
        </main>

        <!-- CHAT : même salon que la fenêtre rapide (touche J), juste accessible aussi depuis la tablette -->
        <main v-else-if="app === 'chat'" class="chatapp">
          <div class="log" ref="chatLogEl">
            <p v-if="!chatMessages.length" class="empty">{{ L('Aucun message pour l\'instant.', 'No messages yet.') }}</p>
            <div v-for="m in chatMessages" :key="m.id" class="msg"><b>{{ m.username }}</b> {{ m.text }}</div>
          </div>
          <div class="inline">
            <input v-model="chatText" type="text" maxlength="200" :placeholder="L('Écrire un message…', 'Write a message…')" @keyup.enter="sendChat" />
            <button type="button" class="btn" :disabled="!chatText.trim()" @click="sendChat">{{ L('Envoyer', 'Send') }}</button>
          </div>
        </main>

        <!-- HISTORIQUE -->
        <main v-else-if="app === 'history'">
          <table class="tb"><tr v-for="x in d.tx" :key="x.id"><td class="mut">{{ x.created_at.slice(0, 16).replace('T', ' ') }}</td><td>{{ x.ref || x.kind }}</td><td :class="x.amount < 0 ? 'bad' : 'good'">{{ x.amount > 0 ? '+' : '' }}{{ money(x.amount) }}</td></tr></table>
        </main>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted, onBeforeUnmount, nextTick } from "vue"
import { net, ui, rpc, errText, refreshMe } from "./net.js"
import VehImg from "./VehImg.vue"

const L = (fr, en) => (net.lang === "en" ? en : fr)
const money = n => (Number(n) < 0 ? "-$" : "$") + Math.abs(Number(n || 0)).toLocaleString(net.lang === "en" ? "en-US" : "fr-FR")
const stars = n => "★".repeat(Math.max(0, Math.min(5, Number(n) || 0))) + "☆".repeat(5 - Math.max(0, Math.min(5, Number(n) || 0)))
const apps = [
  { id: "garage", color: "#ff6600", path: "M3 11l9-7 9 7M5 10v10h14V10M9 20v-6h6v6" },
  { id: "players", color: "#3b82f6", path: "M9 11a4 4 0 100-8 4 4 0 000 8zM2 21c0-4 3-6 7-6s7 2 7 6M17 11a3 3 0 100-6M22 21c0-3-2-5-5-5" },
  { id: "trades", color: "#a855f7", path: "M4 7h13M13 3l4 4-4 4M20 17H7M11 21l-4-4 4-4" },
  { id: "dealer", color: "#22c55e", path: "M6 7h12l-1 13H7L6 7zM9 7V5a3 3 0 016 0v2" },
  { id: "market", color: "#eab308", path: "M4 4h10l6 6-10 10-6-6V4zM8.5 8.5h.01" },
  { id: "work", color: "#ef4444", path: "M4 8h16v11H4zM9 8V5h6v3M4 13h16" },
  { id: "chat", color: "#06b6d4", path: "M4 4h16v12H9l-5 4V4z" },
  { id: "history", color: "#64748b", path: "M12 7v5l3 2M21 12a9 9 0 11-3-6.7M21 4v5h-5" },
]
const NAMES = {
  garage: ["Mes voitures", "My cars"], players: ["Joueurs", "Players"], trades: ["Échanges", "Trades"], dealer: ["Concession", "Dealership"],
  market: ["Annonces", "Listings"], work: ["Travail", "Work"], history: ["Historique", "History"], customize: ["Ordinateur", "Computer"],
  chat: ["Chat", "Chat"],
}
const appName = id => L(...NAMES[id])
const modeName = m => ({ money: L("Argent", "Money"), car: L("Donner une voiture", "Give a car"), trade: L("Échange", "Trade") })[m]

const app = ref(null), msg = ref(""), sel = ref(null), mode = ref("money"), insFor = ref(null)
const f = reactive({ amount: null, gift: "", offer: "", want: "", cash: null })
const d = reactive({ trades: [], catalog: [], market: [], tx: [], partMarket: [], spareParts: [] })
const marketTab = ref("vehicles")
const theirs = ref([]), theirsLoading = ref(false)
const profile = computed(() => net.me?.profile || {})
const vehicles = computed(() => net.me?.vehicles || [])
const emptySlots = computed(() => Math.max(0, (profile.value.garage_slots || 0) - vehicles.value.length))
const sellableVehicles = computed(() => vehicles.value.filter(v => !v.listed))
const employee = computed(() => net.me?.employee || { active: false, level: 0, distance_m: 0 })
const km = m => (Number(m || 0) / 1000).toFixed(1)
const out = v => !!(net.game.spawned && net.game.spawned[v.id])
const locked = v => !!(net.game.spawned && net.game.spawned[v.id] && net.game.spawned[v.id].locked)

// ------------------------------------------------------------------ fiches véhicules (lues dans le jeu, vehinfo.lua)
const askedInfo = new Set()
function needInfo(list) {
  const want = list.filter(x => x.model && !askedInfo.has(x.model + "|" + (x.config || "")))
  want.forEach(x => askedInfo.add(x.model + "|" + (x.config || "")))
  if (want.length) ui("veh.info", { list: want })
}
const vi = (model, config) => net.vehInfo[model + "|" + (config || "")] || {}
const fullName = (i, fallback) => [i.brand, i.name].filter(Boolean).join(" ") || fallback
const kmh = ms => Math.round(ms * 3.6)
// Puissance : les fiches du jeu la donnent en kW (supposé, non vérifié) ; affichée aussi en ch.
const power = p => `${Math.round(p)} kW · ${Math.round(p * 1.341)} ch`
function specLine(i) {
  return [i.configName, i.type, i.weight ? Math.round(i.weight) + " kg" : null, i.power ? Math.round(i.power * 1.341) + " ch" : null].filter(Boolean).join(" · ")
}
function specs(i) {
  return [
    [L("Marque", "Brand"), i.brand], [L("Modèle", "Model"), i.name], [L("Version", "Trim"), i.configName], [L("Type", "Type"), i.type || i.body],
    [L("Années", "Years"), i.years], [L("Pays", "Country"), i.country], [L("Poids", "Weight"), i.weight && Math.round(i.weight) + " kg"],
    [L("Puissance", "Power"), i.power && power(i.power)], [L("Couple", "Torque"), i.torque && Math.round(i.torque) + " N·m"],
    [L("Transmission", "Drivetrain"), [i.drivetrain, i.transmission].filter(Boolean).join(" · ")], [L("Carburant", "Fuel"), i.fuel],
    [L("Vitesse max", "Top speed"), i.topSpeed && kmh(i.topSpeed) + " km/h"], ["0–100 km/h", i.accel && i.accel.toFixed(1) + " s"],
  ].filter(x => x[1])
}
watch(() => d.catalog, list => needInfo(list.map(c => ({ model: c.model_key, config: c.config_key }))))
watch(vehicles, list => needInfo(list.map(v => ({ model: v.model_key, config: v.config_key }))), { immediate: true })

// ------------------------------------------------------------------ assurances (mêmes valeurs que private.insurance_plan, 0014)
const plans = ref([
  { tier: "none", rank: 0, rate: 0, deductible: 100, towing: false },
  { tier: "basic", rank: 1, rate: 2, deductible: 50, towing: false },
  { tier: "comfort", rank: 2, rate: 5, deductible: 20, towing: true },
  { tier: "premium", rank: 3, rate: 9, deductible: 0, towing: true },
])
const PLAN_NAMES = { none: ["Sans assurance", "No insurance"], basic: ["Essentielle", "Essential"], comfort: ["Confort", "Comfort"], premium: ["Premium", "Premium"] }
const planName = t => L(...(PLAN_NAMES[t || "none"] || PLAN_NAMES.none))
const rank = t => (plans.value.find(p => p.tier === (t || "none")) || { rank: 0 }).rank
const premium = (pl, value) => Math.ceil((value || 0) * pl.rate / 100)
const planDesc = pl => pl.tier === "none" ? L("Vous payez toutes les réparations.", "You pay all repairs.")
  : L(`Franchise ${pl.deductible} % des réparations`, `Deductible ${pl.deductible}% of repairs`) + (pl.towing ? L(" · remorquage offert", " · free towing") : "")

// ------------------------------------------------------------------ achat : négociation + assurance
const buy = reactive({ c: null, neg: {}, offer: null, log: [], ins: "basic", busy: false })
const canOffer = computed(() => ["open", "counter"].includes(buy.neg.status))
const buyPrice = computed(() => (buy.neg.status === "accepted" ? buy.neg.asking : buy.c?.price) || 0)
const buyPremium = computed(() => { const pl = plans.value.find(p => p.tier === buy.ins); return pl && buy.c ? premium(pl, buy.c.price) : 0 })
function botSays(r) {
  const p = money(r.asking)
  const t = {
    open: L(`Bonjour ! Il est à ${p}. Faites-moi une offre.`, `Hello! It's ${p}. Make me an offer.`),
    counter: L(`Hmm... je peux descendre à ${p}.`, `Hmm... I can go down to ${p}.`),
    final: L(`Dernier prix : ${p}. À prendre ou à laisser.`, `Final price: ${p}. Take it or leave it.`),
    accepted: L(`Marché conclu à ${p} !`, `Deal at ${p}!`),
    insulted: L("Vous vous moquez de moi ? Revenez plus tard.", "Are you kidding me? Come back later."),
    refused: L("Non. On en reste là pour aujourd'hui.", "No. We're done for today."),
    closed: L("Le vendeur ne veut plus négocier pour le moment (prix affiché seulement).", "The seller won't negotiate for now (list price only)."),
  }[r.status]
  if (t) buy.log.push({ who: "bot", text: t })
}
async function openBuy(c) {
  Object.assign(buy, { c, neg: { status: "open", asking: c.price, patience: 5 }, offer: null, log: [], ins: "basic", busy: false })
  try { const r = await rpc("negotiate_vehicle", { p_catalog_id: c.id, p_offer: null }); buy.neg = r; botSays(r) }
  catch (e) { buy.neg = { status: "closed", asking: c.price, patience: 0 }; buy.log.push({ who: "bot", text: L("Négociation indisponible : prix affiché.", "Negotiation unavailable: list price.") }) }
}
async function offer(amount) {
  const n = Math.floor(Number(amount))
  if (!n || n <= 0 || !buy.c) return
  buy.busy = true; net.error = ""
  buy.log.push({ who: "me", text: L(`Je vous en propose ${money(n)}.`, `I offer ${money(n)}.`) })
  try { const r = await rpc("negotiate_vehicle", { p_catalog_id: buy.c.id, p_offer: n }); buy.neg = { ...r, status: r.status === "insulted" || r.status === "refused" ? "closed" : r.status }; botSays(r) }
  catch (e) { net.error = errText(e) }
  buy.busy = false; buy.offer = null
}
async function purchase() {
  buy.busy = true
  await act(() => rpc("buy_vehicle_insured", { p_catalog_id: buy.c.id, p_insurance: buy.ins, p_color: null }), () => { buy.c = null; go("garage") })
  buy.busy = false
}
// ------------------------------------------------------------------ ordinateur du garage (personnalisation)
// Catalogue RÉEL (supabase/migrations/0018_vehicle_parts_catalog.sql, extrait des vrais fichiers .jbeam du jeu
// par scripts/extract-parts-catalog.mjs) : plus de libellés inventés, les emplacements et les pièces proposés
// sont ceux qui existent vraiment pour ce modèle, au vrai prix du jeu.
const PAINT_RATE = 2 // % de la valeur du véhicule, doit rester identique à private.part_rate('paint') (0015)
const TAB_NAMES = { parts: ["Pièces", "Parts"], tuning: ["Réglages", "Tuning"], paint: ["Peinture", "Paint"], cargo: ["Stockage", "Storage"] }
const custTabName = t => L(...TAB_NAMES[t])

const cust = reactive({ v: null, tab: "parts", busy: false, catalogLoading: false, paintLayers: 1, paintHex: ["#ffffff", "#ffffff", "#ffffff"], tuning: { ride: 0, tire: 30 } })
const partsCatalog = ref([]) // [{ slot, part, name, price, cargo_units }], pour le modèle de cust.v
const catalogSlots = computed(() => {
  const bySlot = {}
  for (const o of partsCatalog.value) {
    if (o.cargo_units != null) continue
    ;(bySlot[o.slot] = bySlot[o.slot] || { slot: o.slot, options: [] }).options.push(o)
  }
  return Object.values(bySlot)
})
const catalogCargoSlots = computed(() => {
  const bySlot = {}
  for (const o of partsCatalog.value) {
    if (o.cargo_units == null) continue
    ;(bySlot[o.slot] = bySlot[o.slot] || { slot: o.slot, options: [] }).options.push(o)
  }
  return Object.values(bySlot)
})
const slotLabel = slot => String(slot || "").replace(/^[a-z0-9]+_/i, "").replace(/_/g, " ")
// Recherche de pièces (grand chantier Phase H) : filtre par nom de pièce ou d'emplacement, insensible à la casse.
const partSearch = ref("")
const filteredSlots = computed(() => {
  const q = partSearch.value.trim().toLowerCase()
  if (!q) return catalogSlots.value
  return catalogSlots.value
    .map(s => ({ slot: s.slot, options: slotLabel(s.slot).toLowerCase().includes(q) ? s.options : s.options.filter(o => o.name.toLowerCase().includes(q)) }))
    .filter(s => s.options.length > 0)
})
const currentPartName = slot => {
  const p = cust.v && cust.v.parts && cust.v.parts[slot]
  return p ? (p.name || p.part_key) : L("Pièce d'origine", "Stock part")
}
const isInstalled = (slot, part) => !!(cust.v && cust.v.parts && cust.v.parts[slot] && cust.v.parts[slot].part_key === part)
const priceFor = cat => Math.max(200, Math.ceil(((cust.v && cust.v.value) || 0) * (cat === "paint" ? PAINT_RATE : 0) / 100))

function hexToRgb(hex) {
  const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex || "")
  if (!m) return { r: 1, g: 1, b: 1, a: 1 }
  return { r: parseInt(m[1], 16) / 255, g: parseInt(m[2], 16) / 255, b: parseInt(m[3], 16) / 255, a: 1 }
}
function rgbToHex(c) {
  const ch = v => Math.max(0, Math.min(255, Math.round((Number(v) || 0) * 255))).toString(16).padStart(2, "0")
  return c ? "#" + ch(c.r) + ch(c.g) + ch(c.b) : "#ffffff"
}
function refreshCustVeh() {
  if (!cust.v) return
  const updated = vehicles.value.find(x => x.id === cust.v.id)
  if (updated) cust.v = updated
}
function openCustomize(v) {
  cust.v = v; cust.tab = "parts"; cust.busy = false
  partSearch.value = ""
  cust.paintLayers = (v.paint && v.paint.length) || 1
  cust.paintHex = [0, 1, 2].map(i => rgbToHex(v.paint && v.paint[i]))
  cust.tuning = Object.assign({ ride: 0, tire: 30 }, v.tuning || {})
  app.value = "customize"; msg.value = ""; net.error = ""
  cust.catalogLoading = true
  safe(async () => { partsCatalog.value = await rpc("get_vehicle_parts_catalog", { p_model_key: v.model_key }) })
    .finally(() => { cust.catalogLoading = false })
}
async function buyPart(slot, part) {
  cust.busy = true
  await act(() => rpc("buy_vehicle_part", { p_vehicle_id: cust.v.id, p_slot: slot, p_part_key: part }), async () => {
    refreshCustVeh()
    await ui("computer.parts", { id: cust.v.id, parts: cust.v.parts })
  })
  cust.busy = false
}
async function removePart(slot) {
  cust.busy = true
  await act(() => rpc("remove_vehicle_part", { p_vehicle_id: cust.v.id, p_slot: slot }), async () => {
    refreshCustVeh()
    await ui("computer.parts", { id: cust.v.id, parts: cust.v.parts })
  })
  cust.busy = false
}
async function saveTuning() {
  cust.busy = true
  await act(() => rpc("save_vehicle_tuning", { p_vehicle_id: cust.v.id, p_tuning: cust.tuning }), async () => {
    refreshCustVeh()
    await ui("computer.tuning", { id: cust.v.id, tuning: cust.v.tuning })
  })
  cust.busy = false
}
async function repaint() {
  cust.busy = true
  const paint = []
  for (let i = 0; i < cust.paintLayers; i++) paint.push(hexToRgb(cust.paintHex[i]))
  await act(() => rpc("repaint_vehicle", { p_vehicle_id: cust.v.id, p_paint: paint }), async () => {
    refreshCustVeh()
    await ui("computer.paint", { id: cust.v.id, paint: cust.v.paint })
  })
  cust.busy = false
}

const giftable = computed(() => vehicles.value.filter(v => !v.listed && !out(v)))
const taxi = computed(() => net.game.taxi || {})
const bus = computed(() => net.game.bus || {})
const delivery = computed(() => net.game.delivery || {})
const DELIVERY_PHASE_NAMES = { pickup: ["Vers le ramassage", "To pickup"], dropoff: ["Vers la livraison", "To drop-off"] }
const deliveryPhaseLabel = p => (DELIVERY_PHASE_NAMES[p] ? L(...DELIVERY_PHASE_NAMES[p]) : "")
const vehicleFor = o => vehicles.value.find(v => out(v) && (v.cargo_capacity || 0) >= o.cargo_units)
function refreshDeliveries() { net.deliveryError = ""; ui("delivery.refresh") }
function acceptDelivery(o) { const v = vehicleFor(o); if (!v) return; net.deliveryError = ""; ui("delivery.accept", { id: o.id, vehicle_id: v.id }) }

// ------------------------------------------------------------------ chat (même salon que QuickPanel.vue, touche J)
const chatText = ref(""), chatLogEl = ref(null)
const chatMessages = computed(() => net.game.chat?.messages || [])
function sendChat() {
  const v = chatText.value.trim()
  if (!v) return
  ui("chat.send", { text: v })
  chatText.value = ""
}
watch(chatMessages, async () => { await nextTick(); if (chatLogEl.value) chatLogEl.value.scrollTop = chatLogEl.value.scrollHeight })
const incoming = computed(() => d.trades.filter(x => x.direction === "in").length)

const clock = ref("")
function tick() { clock.value = new Date().toLocaleTimeString(net.lang === "en" ? "en-US" : "fr-FR", { hour: "2-digit", minute: "2-digit" }) }

function focus(e, on) { const tg = e.target?.tagName; if (tg === "INPUT" || tg === "SELECT" || tg === "TEXTAREA") ui("typing", { on }) }

async function act(fn, after) {
  net.error = ""; msg.value = ""
  try { await fn(); msg.value = L("C'est fait.", "Done."); await refreshMe(); if (after) await after() } catch (e) { net.error = errText(e) }
}
const safe = async fn => { try { await fn() } catch (e) { net.error = errText(e) } }
const loadTrades = () => safe(async () => { d.trades = await rpc("get_trades") })
const loadMarket = () => safe(async () => { d.market = await rpc("get_market", { p_limit: 50, p_offset: 0 }) })
const loadPartMarket = () => safe(async () => {
  d.partMarket = await rpc("get_part_market", { p_limit: 50, p_offset: 0 })
  d.spareParts = await rpc("get_my_spare_parts")
})
const compatibleVehicle = sp => vehicles.value.find(v => v.model_key === sp.model_key)
async function installSpare(sp) {
  const v = compatibleVehicle(sp)
  if (!v) return
  await act(() => rpc("install_spare_part", { p_spare_id: sp.id, p_vehicle_id: v.id }), loadPartMarket)
}
async function sellDealer(v) { await act(async () => { if (out(v)) await ui("garage.store", { id: v.id }); await rpc("sell_vehicle_to_dealer", { p_vehicle_id: v.id }) }) }
// Vente à prix libre : juste "Vendre", pas de détail ici (demandé explicitement) -- la procédure (choisir un
// prix) se passe dans son propre onglet (Annonces > Véhicules), même principe que la vente de pièces.
function sellVehicle() { marketTab.value = "vehicles"; go("market") }

async function pick(name) {
  sel.value = name; f.gift = ""; f.offer = ""; f.want = ""; f.cash = null; msg.value = ""; net.error = ""
  theirsLoading.value = true
  try { theirs.value = await rpc("get_player_garage", { p_username: name }) } catch (e) { theirs.value = [] }
  theirsLoading.value = false
}
// le joueur choisi a quitté le serveur : on le désélectionne
watch(() => net.players.map(p => p.username).join(), () => { if (sel.value && !net.players.some(p => p.username === sel.value)) sel.value = null })

function go(id) {
  app.value = id; msg.value = ""; net.error = ""
  if (id === "trades" || id === "players") loadTrades()
  else if (id === "dealer") { buy.c = null; safe(async () => { d.catalog = await rpc("get_catalog") }) }
  else if (id === "market") { loadMarket(); loadPartMarket() }
  else if (id === "history") safe(async () => { d.tx = await rpc("get_my_transactions", { p_limit: 40 }) })
  if (id === "garage" || id === "players") refreshMe().catch(() => {})
}
watch(() => net.tablet.open, o => { if (o) { go(null); loadTrades(); refreshMe().catch(() => {}); safe(async () => { const p = await rpc("get_insurance_plans"); if (Array.isArray(p) && p.length) plans.value = p }) } })

let timer = null
onMounted(() => { tick(); timer = setInterval(tick, 10000) })
onBeforeUnmount(() => clearInterval(timer))
</script>

<style lang="scss" scoped>
.tbw { position: fixed; inset: 0; z-index: 2147482500; display: flex; align-items: center; justify-content: center; background: rgba(0, 0, 0, 0.35); pointer-events: auto; }
.device { --ac: #ff6600; width: 1120px; max-width: 96vw; height: 720px; max-height: 92vh; padding: 16px; border-radius: 34px; background: linear-gradient(145deg, #1c1c1f, #0b0b0d);
  box-shadow: 0 30px 80px rgba(0, 0, 0, 0.85), inset 0 0 0 2px #2a2a2e, inset 0 0 0 5px #111; * { box-sizing: border-box; } }
.screen { height: 100%; display: flex; flex-direction: column; border-radius: 20px; overflow: hidden; color: #f2f2f2; font: 14px/1.35 "Overpass", "Segoe UI", sans-serif;
  background: radial-gradient(circle at 20% 0%, #2b2118 0%, #121214 55%, #0c0c0e 100%); }
.status { display: flex; align-items: center; gap: 14px; padding: 8px 18px; font-size: 13px; background: rgba(0, 0, 0, 0.35);
  .clock { font-weight: 700; } .place { flex: 1; text-align: center; color: var(--ac); font-weight: 700; letter-spacing: 0.03em; } .bal b { color: #4ade80; }
  .x { width: 28px; height: 28px; border-radius: 50%; border: 0; color: #fff; background: rgba(255, 255, 255, 0.1); cursor: pointer; &:hover { background: #ef4444; } } }
.apphead { display: flex; align-items: center; gap: 14px; padding: 10px 18px; border-bottom: 1px solid rgba(255, 255, 255, 0.07);
  .back { border: 0; background: none; color: var(--ac); font: 600 15px inherit; cursor: pointer; padding: 4px 0; }
  .apptitle { font: 700 18px "Overpass", sans-serif; } }
.home { flex: 1; display: grid; grid-template-columns: repeat(4, 150px); grid-auto-rows: 150px; gap: 26px; justify-content: center; align-content: center; }
.icon { position: relative; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px; border: 0; background: none; color: #fff; cursor: pointer; border-radius: 18px;
  transition: transform 0.15s ease, background 0.15s ease; &:hover { transform: translateY(-3px); background: rgba(255, 255, 255, 0.05); }
  .ic { width: 78px; height: 78px; border-radius: 22px; display: flex; align-items: center; justify-content: center; box-shadow: 0 8px 22px rgba(0, 0, 0, 0.45); }
  svg { width: 40px; height: 40px; fill: none; stroke: #fff; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
  .lbl { font-weight: 600; } .badge { position: absolute; top: 14px; right: 30px; min-width: 22px; height: 22px; padding: 0 6px; border-radius: 11px; background: #ef4444; font: 700 12px/22px sans-serif; } }
main { flex: 1; overflow-y: auto; padding: 16px 20px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 14px; }
.tile { display: flex; flex-direction: column; gap: 4px; padding: 14px; border-radius: 14px; background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.08);
  &.wide { margin-bottom: 12px; } .tname { font: 700 16px "Overpass", sans-serif; } .price { font: 800 20px "Overpass", sans-serif; color: var(--ac); }
  .tags { display: flex; gap: 6px; min-height: 4px; } .acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; } .inline { display: flex; gap: 6px; width: 100%; input { flex: 1; min-width: 0; } .btn { white-space: nowrap; flex: none; } } }
.tag { padding: 1px 8px; font-size: 11px; border-radius: 10px; background: rgba(255, 102, 0, 0.2); color: var(--ac); &.on { background: rgba(74, 222, 128, 0.2); color: #4ade80; } }
.tile.veh { padding-top: 0; overflow: hidden; :deep(.vimg) { margin: 0 -14px 6px; } }
.tile.empty-slot { align-items: center; justify-content: center; text-align: center; min-height: 140px; padding-top: 14px;
  border-style: dashed; opacity: 0.7; }
.vhead { display: flex; gap: 16px; align-items: flex-start; .vtxt { flex: 1; min-width: 0; } }
.specs { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 4px 14px; margin-top: 8px; font-size: 12px;
  div { display: flex; justify-content: space-between; gap: 8px; border-bottom: 1px solid rgba(255, 255, 255, 0.06); padding: 2px 0; } span { color: rgba(255, 255, 255, 0.55); } b { text-align: right; } }
.desc { margin: 0; font-size: 13px; color: rgba(255, 255, 255, 0.75); line-height: 1.45; }
.tile.click { cursor: pointer; transition: border-color 0.15s, transform 0.15s; &:hover { border-color: var(--ac); transform: translateY(-2px); } }
.tag.lock { background: rgba(239, 68, 68, 0.2); color: #f87171; } .tag.ins-none { background: rgba(255, 255, 255, 0.08); color: rgba(255, 255, 255, 0.7); }
.tag.ins-basic { background: rgba(59, 130, 246, 0.2); color: #93c5fd; } .tag.ins-comfort { background: rgba(168, 85, 247, 0.2); color: #d8b4fe; } .tag.ins-premium { background: rgba(234, 179, 8, 0.2); color: #fde047; }
.plans { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
.plan { display: flex; flex-direction: column; align-items: flex-start; gap: 2px; padding: 8px 12px; border-radius: 10px; border: 1px solid rgba(255, 255, 255, 0.12); background: rgba(255, 255, 255, 0.04);
  color: #fff; font: inherit; cursor: pointer; text-align: left; &.on, &:hover { border-color: var(--ac); background: rgba(255, 102, 0, 0.12); }
  &.wide { width: 100%; display: grid; grid-template-columns: 1fr auto; margin-bottom: 6px; .mut { grid-column: 1; font-size: 12px; } .pp { grid-row: 1 / span 2; grid-column: 2; align-self: center; font-weight: 800; color: var(--ac); } } }
.buy { display: flex; gap: 20px; }
.nego { flex: 1; display: flex; flex-direction: column; gap: 8px; min-width: 0; h3 { margin: 0; font: 700 22px "Overpass", sans-serif; }
  .back { align-self: flex-start; border: 0; background: none; color: var(--ac); font: 600 14px inherit; cursor: pointer; padding: 0; } }
.chat { flex: 1; min-height: 160px; max-height: 300px; overflow-y: auto; display: flex; flex-direction: column; gap: 6px; padding: 10px; border-radius: 12px; background: rgba(0, 0, 0, 0.3); }
.bubble { max-width: 80%; padding: 8px 12px; border-radius: 14px; font-size: 13px; &.bot { align-self: flex-start; background: rgba(255, 255, 255, 0.08); border-bottom-left-radius: 4px; }
  &.me { align-self: flex-end; background: var(--ac); border-bottom-right-radius: 4px; } }
.pat { font-size: 12px; color: rgba(255, 255, 255, 0.6); display: flex; align-items: center; gap: 4px; }
.pdot { width: 10px; height: 10px; border-radius: 50%; background: rgba(255, 255, 255, 0.12); &.on { background: #4ade80; } }
.checkout { width: 330px; flex: none; h4 { margin: 0 0 8px; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; color: rgba(255, 255, 255, 0.6); } }
.total { margin: 10px 0; padding: 10px 12px; border-radius: 12px; background: rgba(0, 0, 0, 0.3); > div { display: flex; justify-content: space-between; padding: 3px 0; }
  .sum { border-top: 1px solid rgba(255, 255, 255, 0.1); margin-top: 4px; padding-top: 6px; font-size: 16px; b { color: var(--ac); } } }
.btn.big { width: 100%; padding: 12px; font-size: 15px; }
.small { font-size: 12px; }
.swap { display: flex; align-items: center; gap: 8px; .arr { color: var(--ac); font-size: 18px; } }
.split { display: flex; gap: 16px; padding: 0; overflow: hidden; }
.plist { width: 280px; flex: none; overflow-y: auto; padding: 14px; border-right: 1px solid rgba(255, 255, 255, 0.07); }
.pl { width: 100%; display: flex; align-items: center; gap: 10px; padding: 10px; margin-bottom: 6px; border: 1px solid transparent; border-radius: 12px; background: rgba(255, 255, 255, 0.04);
  color: #fff; font: inherit; text-align: left; cursor: pointer; &:hover { background: rgba(255, 255, 255, 0.08); } &.on { border-color: var(--ac); background: rgba(255, 102, 0, 0.12); }
  .av { width: 36px; height: 36px; flex: none; border-radius: 50%; display: flex; align-items: center; justify-content: center; background: #3b82f6; font-weight: 800; } }
.pact { flex: 1; overflow-y: auto; padding: 14px 20px 14px 0; h3 { margin: 0 0 10px; font: 700 22px "Overpass", sans-serif; } &.empty { display: flex; align-items: center; justify-content: center; } }
.seg { display: inline-flex; padding: 3px; margin-bottom: 14px; border-radius: 10px; background: rgba(255, 255, 255, 0.06);
  button { border: 0; padding: 7px 14px; border-radius: 8px; background: none; color: rgba(255, 255, 255, 0.7); font: 600 13px inherit; cursor: pointer; &.on { background: var(--ac); color: #fff; } } }
.panel { display: flex; flex-direction: column; gap: 8px; max-width: 560px; label { font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; color: rgba(255, 255, 255, 0.6); margin-top: 6px; } &.wide { max-width: none; } }
.partsearch { width: 100%; margin-bottom: 10px; }
input[type="color"] { width: 46px; height: 32px; padding: 2px; border-radius: 8px; cursor: pointer; }
input[type="range"] { width: 100%; max-width: 320px; accent-color: var(--ac); }
.customize .vhead { margin-bottom: 4px; }
.chatapp { display: flex; flex-direction: column; }
.chatapp .log { flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 4px; padding: 10px; border-radius: 12px; background: rgba(0, 0, 0, 0.3); margin-bottom: 10px; }
.chatapp .msg { font-size: 13px; word-break: break-word; }
.chatapp .msg b { color: var(--ac); margin-right: 4px; }
.chatapp .inline input { flex: 1; }
h4.submuted { margin: 18px 0 10px; font: 700 13px "Overpass", sans-serif; text-transform: uppercase; letter-spacing: 0.05em; color: rgba(255, 255, 255, 0.5); }
h4.submuted:first-child { margin-top: 0; }
.chips, .pickrow { display: flex; flex-wrap: wrap; gap: 6px; }
.chip, .pk { padding: 6px 12px; border-radius: 10px; border: 1px solid rgba(255, 255, 255, 0.12); background: rgba(255, 255, 255, 0.05); color: #fff; font: 600 13px inherit; cursor: pointer;
  display: flex; flex-direction: column; align-items: flex-start; small { font-weight: 400; color: rgba(255, 255, 255, 0.6); } &.on, &:hover { border-color: var(--ac); background: rgba(255, 102, 0, 0.15); } }
input { padding: 8px 10px; color: #fff; background: rgba(0, 0, 0, 0.45); border: 1px solid rgba(255, 255, 255, 0.15); border-radius: 10px; font: inherit; &:focus { outline: none; border-color: var(--ac); } }
.btn { align-self: flex-start; padding: 8px 16px; color: #fff; font: 600 13px "Overpass", sans-serif; cursor: pointer; background: var(--ac); border: 0; border-radius: 10px; transition: filter 0.15s, transform 0.15s;
  &:hover:not(:disabled) { filter: brightness(1.12); transform: translateY(-1px); } &:disabled { opacity: 0.4; cursor: default; } &.dim { background: rgba(255, 255, 255, 0.1); } }
.tb { width: 100%; border-collapse: collapse; td { padding: 6px 8px; border-bottom: 1px solid rgba(255, 255, 255, 0.06); } td:last-child { text-align: right; font-weight: 700; } }
.empty { color: rgba(255, 255, 255, 0.55); text-align: center; padding: 30px 0; }
.err { margin: 8px 20px 0; color: #ff6b6b; } .ok { margin: 8px 20px 0; color: #4ade80; } .good { color: #4ade80; } .bad { color: #ff6b6b; } .mut { color: rgba(255, 255, 255, 0.6); }
</style>
