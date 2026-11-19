/* Sessão, guarda de página por role e saída. Requer js/supabase.js (window.sb).
   O body fica oculto até a guarda liberar (evita piscar conteúdo de quem não pode ver).
   Isso é só UX: quem barra de verdade é o RLS / as funções do banco. */
(function () {
  const LOGIN = 'login.html';

  const estiloOculto = document.createElement('style');
  estiloOculto.id = 'ggc-oculto';
  estiloOculto.textContent = 'body{visibility:hidden}';
  document.head.appendChild(estiloOculto);

  function liberarPagina() {
    const e = document.getElementById('ggc-oculto');
    if (e) e.remove();
  }

  function destinoPorRole(role) {
    return role === 'admin' || role === 'dev' ? 'admin-menu.html' : 'inicio.html';
  }

  // -> { user, conta: {id, nome, apelido, numero, role} | null } | null (sem sessão)
  async function sessaoAtual() {
    const { data: { session } } = await sb.auth.getSession();
    if (!session) return null;
    const { data: conta, error } = await sb.from('contas')
      .select('id, nome, apelido, numero, foto_url, role')
      .eq('user_id', session.user.id)
      .maybeSingle();
    if (error) throw error;
    return { user: session.user, conta: conta || null };
  }

  const nunca = () => new Promise(() => {});

  // Sem sessão -> login; role fora de `roles` -> tela da role. Devolve a sessão quando libera.
  async function exigirSessao({ roles } = {}) {
    let s = null;
    try { s = await sessaoAtual(); } catch (e) { console.error(e); }
    if (!s) { location.replace(LOGIN); return nunca(); }
    if (!s.conta) {
      await sb.auth.signOut();
      location.replace(LOGIN + '?erro=sem_conta');
      return nunca();
    }
    if (roles && !roles.includes(s.conta.role)) {
      location.replace(destinoPorRole(s.conta.role));
      return nunca();
    }
    liberarPagina();
    return s;
  }

  async function sair() {
    try { await sb.auth.signOut(); } catch (e) { console.error(e); }
    location.replace(LOGIN);
  }

  // Mensagem amigável para erros do Postgres/Supabase
  function msgErro(e, padrao) {
    if (!e) return padrao;
    if (e.code === 'P0001' && e.message) return e.message;   // raise exception das funções/triggers
    if (e.code === '42501') return 'Sem permissão para isso.';
    if (e.code === '23505') {
      const m = String(e.message || '') + String(e.details || '');
      if (m.includes('numero')) return 'Esse número já tem dono.';
      if (m.includes('email')) return 'Esse e-mail já está na lista.';
    }
    return padrao;
  }

  // Avatar do usuário no topo: foto se tiver, senão a inicial (se a foto falhar, volta pra inicial)
  function preencherAvatar(el, conta, letra) {
    const inicial = (letra || '?').toUpperCase();
    el.textContent = inicial;
    if (!conta || !conta.foto_url) return;
    const img = new Image();
    img.alt = '';
    img.style.cssText = 'width:100%;height:100%;border-radius:50%;object-fit:cover;display:block';
    img.onload = () => { el.textContent = ''; el.appendChild(img); };
    img.src = conta.foto_url;
  }

  window.GGC = { sessaoAtual, exigirSessao, destinoPorRole, sair, liberarPagina, msgErro, preencherAvatar, LOGIN };
})();
