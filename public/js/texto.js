/* Formatação simples para textos editados pelo admin (boas-vindas).
   Escapa o HTML primeiro (nada do texto vira código) e depois aplica:
     **negrito**   *itálico*   linha em branco = novo parágrafo   quebra simples = <br>
*/
(function () {
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  function inline(s) {
    return esc(s)
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/(^|[^*])\*([^*\n]+?)\*(?!\*)/g, '$1<em>$2</em>');
  }

  function formatarTexto(texto) {
    const normal = String(texto ?? '').replace(/\r\n?/g, '\n').trim();
    if (!normal) return '';
    return normal
      .split(/\n{2,}/)
      .map((p) => `<p>${inline(p).replace(/\n/g, '<br>')}</p>`)
      .join('');
  }

  window.GGC = Object.assign(window.GGC || {}, { formatarTexto });
})();
