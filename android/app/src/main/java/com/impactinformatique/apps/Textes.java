package com.impactinformatique.apps;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.Locale;

/**
 * (3.73.0) Les quelques textes que l'application Android écrit elle-même —
 * noms des canaux de notification, messages de position, d'enregistrement,
 * de partage — dans la langue de l'application : celle choisie au bouton
 * FR / EN (la page la dit au téléphone par AndroidPont.langue), sinon celle
 * du téléphone.
 *
 * Le reste — les écrans, et les notifications venues de la base — est
 * traduit par la page (js/langue.js) et par le serveur (envoyer-push).
 */
final class Textes {

    private static final String PREFS = "bizzoo-langue";
    private static final String CLE = "langue";

    private Textes() { }

    /** La page dit la langue en cours ; on la garde pour les textes du téléphone. */
    static void retenir(Context contexte, String langue) {
        if (contexte == null || langue == null) return;
        String l = langue.trim().toLowerCase(Locale.ROOT);
        if (!l.equals("fr") && !l.equals("en")) return;
        contexte.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(CLE, l).apply();
    }

    static boolean enAnglais(Context contexte) {
        if (contexte != null) {
            SharedPreferences p = contexte.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            String l = p.getString(CLE, null);
            if (l != null) return l.equals("en");
        }
        return Locale.getDefault().getLanguage().equals("en");
    }

    /** Le texte français, ou l'anglais si l'application est en anglais. */
    static String t(Context contexte, String francais, String anglais) {
        return enAnglais(contexte) ? anglais : francais;
    }
}
