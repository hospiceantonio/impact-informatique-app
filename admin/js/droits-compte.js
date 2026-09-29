/* Interface commune, copiée dans les deux applications par generer-mentions.py. */
const DroitsCompte = (() => {
  const carte = (connecte) => '<div class="carte">' +
    '<div class="carte-titre">Vos données et vos droits</div>' +
    '<p><a href="legal/confidentialite.html">Politique de confidentialité</a></p>' +
    '<p><a href="legal/mentions-legales.html">Mentions légales</a> · ' +
    '<a href="legal/conditions.html">Conditions d’utilisation</a></p>' +
    '<p><a href="mailto:contact@bizzoomarket.com">Contacter BIZZOO</a></p>' +
    (connecte ? '<button type="button" class="btn btn-clair" data-supprimer-mon-compte>Supprimer mon compte</button>' : '') +
    '</div>';

  async function supprimer(bouton) {
    const question = 'Supprimer définitivement votre compte BIZZOO ? Votre profil, vos favoris, vos adresses, vos avis, vos signalements et vos réclamations seront supprimés. Les pièces de commandes et les traces métier nécessaires restent conservées. Cette action est irréversible.';
    if (!window.confirm(question)) return;
    bouton.disabled = true;
    try {
      if (typeof Compte !== 'undefined') await Compte.rpc('supprimer_mon_compte', { confirmation: 'SUPPRIMER' });
      else await Supabase.rpc('supprimer_mon_compte', { confirmation: 'SUPPRIMER' });
    } catch (error) {
      UI.toast(error.message || 'Suppression indisponible. Réessayez en ligne ou contactez contact@bizzoomarket.com.', 'err');
      bouton.disabled = false;
      return;
    }
    // La suppression distante a réussi : un stockage local indisponible ne doit
    // pas la faire passer pour un échec. Nettoyer ce qui est accessible.
    try {
      for (const key of Object.keys(localStorage)) {
        if (/^(bizzoo|impact)[-_]/i.test(key) && key !== 'impact-config') localStorage.removeItem(key);
      }
    } catch (_) { /* le compte est déjà supprimé sur le serveur */ }
    try {
      if ('caches' in window) {
        const names = await caches.keys();
        await Promise.allSettled(names.filter(name => /^(bizzoo|impact)[-_]/i.test(name)).map(name => caches.delete(name)));
      }
    } catch (_) { /* le compte est déjà supprimé sur le serveur */ }
    window.alert('Votre compte a été supprimé.');
    location.replace(location.pathname);
  }
  document.addEventListener('click', (event) => {
    const bouton = event.target.closest('[data-supprimer-mon-compte]');
    if (bouton) supprimer(bouton);
  });
  return { carte };
})();
