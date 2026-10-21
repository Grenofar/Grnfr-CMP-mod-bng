// Adresse du serveur Supabase. Les deux valeurs sont remplacées par scripts/build.mjs au moment de fabriquer le zip
// (variables SUPABASE_URL et SUPABASE_ANON_KEY). La clé « anon » est publique par conception : la sécurité est
// assurée par les fonctions SQL. Ne JAMAIS mettre la clé service_role ici.
export default { url: "__SUPABASE_URL__", anonKey: "__SUPABASE_ANON_KEY__" }
