// Relais réseau du mod BeamNG. Depuis BeamNG 0.40, l'interface du jeu n'a plus le droit de contacter un hôte
// extérieur (Content-Security-Policy connect-src limitée à localhost) et le Lua du jeu n'a pas de HTTPS (pas de
// LuaSec). Le mod charge donc cette page dans un cadre invisible : elle n'est pas soumise à la règle du jeu, fait la
// requête vers Supabase et renvoie la réponse par postMessage.
// Ce n'est pas un proxy ouvert : on ne reçoit qu'un CHEMIN (/rest/v1/..., /auth/v1/...), toujours envoyé à l'URL
// Supabase de config.js. Les identifiants (jeton) viennent de la page qui intègre le cadre, exactement comme si elle
// appelait Supabase elle-même : rien de plus n'est exposé que ce que l'API publique permet déjà.
(() => {
  const cfg = window.GRNFR_CONFIG || {}
  const base = String(cfg.url || "").replace(/\/+$/, "")
  const reply = m => window.parent.postMessage(Object.assign({ grnfr: "bridge" }, m), "*")

  window.addEventListener("message", async ev => {
    const r = ev.data
    if (!r || r.grnfr !== "req" || typeof r.path !== "string" || !/^\/(rest|auth)\/v1\//.test(r.path)) return
    if (!base) return reply({ id: r.id, status: 0, error: "relais non configuré (config.js sans URL Supabase)" })
    const get = r.method === "get"
    try {
      const res = await fetch(base + r.path, {
        method: get ? "GET" : "POST",
        headers: { apikey: cfg.anonKey, "Content-Type": "application/json", Authorization: String(r.authorization || "Bearer " + cfg.anonKey) },
        body: get ? undefined : (r.body || undefined),
      })
      reply({ id: r.id, status: res.status, body: await res.text() })
    } catch (e) {
      reply({ id: r.id, status: 0, error: "relais : " + ((e && (e.message || e.name)) || String(e)) })
    }
  })

  reply({ ready: true, configured: !!base })
})()
