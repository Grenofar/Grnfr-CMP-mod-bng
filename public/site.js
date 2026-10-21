// Petit client Supabase sans dépendance pour le site (fetch seulement). La clé « anon » est publique ; la sécurité est dans les fonctions SQL.
(function () {
  const cfg = window.GRNFR_CONFIG || {}
  const KEY = "grnfr_site_auth"
  const S = { auth: null }
  try { S.auth = JSON.parse(localStorage.getItem(KEY) || "null") } catch (e) { /* ignoré */ }
  const save = () => { try { S.auth ? localStorage.setItem(KEY, JSON.stringify(S.auth)) : localStorage.removeItem(KEY) } catch (e) { /* ignoré */ } }
  const configured = !!(cfg.url && cfg.anonKey)

  async function http(path, body, token) {
    if (!configured) throw new Error("not_configured")
    let res
    try { res = await fetch(cfg.url + path, { method: "POST", headers: { apikey: cfg.anonKey, "Content-Type": "application/json", Authorization: "Bearer " + (token || cfg.anonKey) }, body: JSON.stringify(body || {}) }) }
    catch (e) { throw new Error("network") }
    let d = null; try { d = await res.json() } catch (e) { /* vide */ }
    if (!res.ok) { const e = new Error((d && (d.message || d.msg || d.error_description)) || "http_" + res.status); e.status = res.status; throw e }
    return d
  }
  function setSession(d) { S.auth = { access: d.access_token, refresh: d.refresh_token, exp: Date.now() + (d.expires_in || 3600) * 1000 }; save() }
  async function token() {
    if (!S.auth) throw new Error("not_authenticated")
    if (S.auth.exp - Date.now() < 60000) setSession(await http("/auth/v1/token?grant_type=refresh_token", { refresh_token: S.auth.refresh }))
    return S.auth.access
  }
  const MSG = {
    "Invalid login credentials": "E-mail ou mot de passe incorrect.", "User already registered": "Un compte existe déjà avec cet e-mail.",
    username_taken: "Ce pseudo est déjà pris.", username_invalid: "Pseudo invalide : 3 à 20 lettres, chiffres ou _.", "Database error saving new user": "Pseudo invalide ou déjà pris.",
    network: "Serveur injoignable.", not_configured: "Site non configuré (variables SUPABASE_URL / SUPABASE_ANON_KEY).", forbidden: "Réservé aux administrateurs.",
    insufficient_funds: "Fonds insuffisants.", garage_full: "Garage plein.", not_authenticated: "Connectez-vous d'abord.",
  }
  window.GRNFR = {
    configured,
    get loggedIn() { return !!S.auth },
    msg: e => MSG[e && e.message] || ("Erreur : " + (e && e.message || e)),
    rpc: async (fn, args) => http("/rest/v1/rpc/" + fn, args, await token()),
    rpcPublic: (fn, args) => http("/rest/v1/rpc/" + fn, args),
    async signIn(email, password) { setSession(await http("/auth/v1/token?grant_type=password", { email, password })) },
    async signUp(email, password, username) {
      if (!/^[A-Za-z0-9_]{3,20}$/.test(username)) throw new Error("username_invalid")
      if ((await http("/rest/v1/rpc/username_available", { p_username: username })) !== true) throw new Error("username_taken")
      const d = await http("/auth/v1/signup", { email, password, data: { username } })
      if (d && d.access_token) { setSession(d); return true }
      return false // e-mail à confirmer
    },
    signOut() { S.auth = null; save() },
    money: n => "$" + Number(n || 0).toLocaleString("fr-FR"),
    esc: s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])),
  }
})()
