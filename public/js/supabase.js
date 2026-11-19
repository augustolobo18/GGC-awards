/* Cria o client do Supabase uma única vez (window.sb).
   Requer, antes deste arquivo: o CDN do supabase-js e js/config.js. */
(function () {
  const cfg = window.GGC_CONFIG || {};
  if (!window.supabase || !cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY) {
    console.warn('Supabase não configurado: confira js/config.js e o script do CDN.');
    return;
  }
  window.sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });
})();
