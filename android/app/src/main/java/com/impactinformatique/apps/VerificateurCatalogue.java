package com.impactinformatique.apps;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/**
 * Va voir régulièrement si la boutique a mis son catalogue à jour et,
 * le cas échéant, dépose une notification — même application fermée.
 *
 * Aucun serveur n'est nécessaire : la tâche interroge directement la
 * base, comme le fait l'application quand elle est ouverte.
 */
public class VerificateurCatalogue extends Worker {

    private static final String NOM_TACHE = "verification-catalogue";
    private static final String CANAL = "catalogue";
    private static final String PREFS = "impact-notifications";
    private static final String CLE_VUE = "derniere-vue";
    private static final int ID_NOTIFICATION = 4201;

    public VerificateurCatalogue(@NonNull Context contexte, @NonNull WorkerParameters parametres) {
        super(contexte, parametres);
    }

    /** Programme la vérification (application client uniquement). */
    public static void programmer(Context contexte) {
        if (!contexte.getResources().getBoolean(R.bool.notifications_actives)) return;

        Constraints contraintes = new Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build();
        PeriodicWorkRequest demande = new PeriodicWorkRequest.Builder(
                VerificateurCatalogue.class, 15, TimeUnit.MINUTES)
                .setConstraints(contraintes)
                .build();
        WorkManager.getInstance(contexte).enqueueUniquePeriodicWork(
                NOM_TACHE, ExistingPeriodicWorkPolicy.KEEP, demande);
    }

    /** Ce que le client a déjà vu dans l'application : pas de doublon. */
    public static void memoriserVue(Context contexte, String signature) {
        contexte.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(CLE_VUE, signature).apply();
    }

    @NonNull
    @Override
    public Result doWork() {
        Context contexte = getApplicationContext();
        if (!contexte.getResources().getBoolean(R.bool.notifications_actives)) return Result.success();

        String[] config = lireConfiguration(contexte);
        if (config == null) return Result.success(); // application pas encore reliée à une base

        try {
            JSONArray produits = lireProduits(config[0], config[1]);
            if (produits == null || produits.length() == 0) return Result.success();

            JSONObject recent = produits.getJSONObject(0);
            String signature = recent.optString("id") + "|" + recent.optString("modifie_le");

            SharedPreferences prefs = contexte.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            String connue = prefs.getString(CLE_VUE, "");
            prefs.edit().putString(CLE_VUE, signature).apply();

            /* Première vérification : on retient l'état, sans déranger. */
            if (connue.isEmpty() || connue.equals(signature)) return Result.success();

            notifier(contexte, recent);
            return Result.success();
        } catch (Exception e) {
            return Result.retry(); // réseau capricieux : on retentera
        }
    }

    /* ---------- Lecture de la base ---------- */

    /** URL et clé publiable, lues dans les fichiers embarqués de l'application. */
    private String[] lireConfiguration(Context contexte) {
        try (InputStream flux = contexte.getAssets().open("www/config.js")) {
            StringBuilder texte = new StringBuilder();
            BufferedReader lecteur = new BufferedReader(new InputStreamReader(flux, StandardCharsets.UTF_8));
            String ligne;
            while ((ligne = lecteur.readLine()) != null) texte.append(ligne);
            String contenu = texte.toString();
            String url = extraire(contenu, "SUPABASE_URL");
            String cle = extraire(contenu, "SUPABASE_ANON_KEY");
            if (url.isEmpty() || cle.isEmpty()) return null;
            return new String[]{url, cle};
        } catch (Exception e) {
            return null;
        }
    }

    private static String extraire(String contenu, String nom) {
        int debut = contenu.indexOf(nom);
        if (debut < 0) return "";
        int guillemet = contenu.indexOf('"', debut);
        if (guillemet < 0) return "";
        int fin = contenu.indexOf('"', guillemet + 1);
        if (fin < 0) return "";
        return contenu.substring(guillemet + 1, fin);
    }

    private JSONArray lireProduits(String url, String cle) throws Exception {
        String adresse = url + "/rest/v1/produits"
                + "?select=id,nom,prix,cree_le,modifie_le&order=modifie_le.desc&limit=5";
        HttpURLConnection connexion = (HttpURLConnection) new URL(adresse).openConnection();
        connexion.setRequestProperty("apikey", cle);
        connexion.setRequestProperty("Accept", "application/json");
        connexion.setConnectTimeout(15000);
        connexion.setReadTimeout(15000);
        try {
            if (connexion.getResponseCode() != 200) return null;
            StringBuilder corps = new StringBuilder();
            BufferedReader lecteur = new BufferedReader(
                    new InputStreamReader(connexion.getInputStream(), StandardCharsets.UTF_8));
            String ligne;
            while ((ligne = lecteur.readLine()) != null) corps.append(ligne);
            return new JSONArray(corps.toString());
        } finally {
            connexion.disconnect();
        }
    }

    /* ---------- Notification ---------- */

    private void notifier(Context contexte, JSONObject produit) {
        NotificationManagerCompat gestionnaire = NotificationManagerCompat.from(contexte);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel canal = new NotificationChannel(CANAL,
                    "Nouveautés du catalogue", NotificationManager.IMPORTANCE_DEFAULT);
            canal.setDescription("Prévient quand la boutique ajoute ou met à jour des produits.");
            gestionnaire.createNotificationChannel(canal);
        }

        String nom = produit.optString("nom", "");
        boolean nouveau = produit.optString("cree_le", "").equals(produit.optString("modifie_le", ""));
        long prix = produit.optLong("prix", 0);

        String titre = nouveau ? "Nouveau dans la boutique" : "Catalogue mis à jour";
        String texte = nom.isEmpty()
                ? "De nouveaux articles vous attendent."
                : (nouveau ? nom : nom + " vient d'être mis à jour")
                  + (prix > 0 ? " — " + montant(prix) : "");

        Intent ouverture = new Intent(contexte, MainActivity.class);
        ouverture.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        int drapeaux = PendingIntent.FLAG_UPDATE_CURRENT
                | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0);
        PendingIntent action = PendingIntent.getActivity(contexte, 0, ouverture, drapeaux);

        Notification notification = new NotificationCompat.Builder(contexte, CANAL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(titre)
                .setContentText(texte)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(texte))
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .setContentIntent(action)
                .build();

        try {
            gestionnaire.notify(ID_NOTIFICATION, notification);
        } catch (SecurityException e) {
            /* Le client a refusé les notifications : rien à faire. */
        }
    }

    /** "145 000 FCFA" — même présentation que dans l'application. */
    private static String montant(long valeur) {
        String chiffres = String.valueOf(valeur);
        StringBuilder sortie = new StringBuilder();
        int compte = 0;
        for (int i = chiffres.length() - 1; i >= 0; i--) {
            sortie.insert(0, chiffres.charAt(i));
            if (++compte % 3 == 0 && i > 0) sortie.insert(0, ' ');
        }
        return sortie + " FCFA";
    }
}
