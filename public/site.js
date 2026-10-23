// Petit client Supabase sans dépendance pour le site (fetch seulement, RPC publiques uniquement : plus de page
// compte/admin sur le site -- voir git log si la partie authentifiée (signIn/signUp/rpc authentifié) est utile
// à retrouver un jour). La clé « anon » est publique ; la sécurité est dans les fonctions SQL.
(function () {
  const cfg = window.GRNFR_CONFIG || {}
  const configured = !!(cfg.url && cfg.anonKey)

  async function http(path, body) {
    if (!configured) throw new Error("not_configured")
    let res
    try { res = await fetch(cfg.url + path, { method: "POST", headers: { apikey: cfg.anonKey, "Content-Type": "application/json", Authorization: "Bearer " + cfg.anonKey }, body: JSON.stringify(body || {}) }) }
    catch (e) { throw new Error("network") }
    let d = null; try { d = await res.json() } catch (e) { /* vide */ }
    if (!res.ok) { const e = new Error((d && (d.message || d.msg || d.error_description)) || "http_" + res.status); e.status = res.status; throw e }
    return d
  }
  const MSG = {
    network: "Serveur injoignable.", not_configured: "Site non configuré (variables SUPABASE_URL / SUPABASE_ANON_KEY).",
  }
  window.GRNFR = {
    configured,
    msg: e => MSG[e && e.message] || ("Erreur : " + (e && e.message || e)),
    rpcPublic: (fn, args) => http("/rest/v1/rpc/" + fn, args),
    money: n => "$" + Number(n || 0).toLocaleString("fr-FR"),
    esc: s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])),
    // URL publique d'un fichier du bucket Storage "releases" (bucket public : pas besoin de jeton).
    releaseUrl: file_path => cfg.url + "/storage/v1/object/public/releases/" + encodeURIComponent(file_path),
  }
})()
