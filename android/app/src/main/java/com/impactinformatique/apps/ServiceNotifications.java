package com.impactinformatique.apps;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.util.Log;

import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import java.util.Map;

/**
 * Les notifications envoyées par BIZZOO (Firebase Cloud Messaging) :
 * aujourd'hui, « telle boutique est en live sur TikTok ».
 *
 * L'APPLICATION S'ABONNE AU SUJET « tous » à son ouverture : la fonction
 * Edge « annoncer-live » n'a pas à connaître chaque téléphone, elle
 * envoie au sujet.
 *
 * LE MESSAGE NE PORTE QUE DES DONNÉES. C'est donc ici, et pas chez
 * Firebase, que la notification se construit — application ouverte ou
 * fermée. C'est ce qui permet que la toucher ouvre DIRECTEMENT la page
 * TikTok de la boutique (l'application TikTok si elle est installée),
 * au lieu de rouvrir seulement BIZZOO.
 *
 * Sans réglages Firebase dans l'APK (android/firebase.properties), rien
 * ne s'initialise et rien ne s'abonne : l'application marche comme avant.
 */
public class ServiceNotifications extends FirebaseMessagingService {

    static final String SUJET_TOUS = "tous";
    private static final String CANAL_LIVES = "lives";
    private static final String JOURNAL = "BizzooNotifications";

    /** À l'ouverture de l'application client : s'abonner au sujet « tous ». */
    static void abonner(Context contexte) {
        try {
            if (FirebaseApp.getApps(contexte).isEmpty()) return;  // Firebase pas réglé
            FirebaseMessaging.getInstance().subscribeToTopic(SUJET_TOUS);
        } catch (RuntimeException e) {
            /* Pas de services Google sur ce téléphone, ou Firebase mal réglé :
               l'application continue sans les notifications de live. */
            Log.w(JOURNAL, "Abonnement impossible : " + e.getMessage());
        }
    }

    @Override
    public void onNewToken(String jeton) {
        /* Rien à envoyer : on écrit au sujet, pas à chaque téléphone. */
    }

    @Override
    public void onMessageReceived(RemoteMessage message) {
        Map<String, String> donnees = message.getData();
        if (donnees == null || !"live".equals(donnees.get("type"))) return;
        String lien = valeur(donnees, "lien");
        if (!lienTikTok(lien)) return;   // on n'ouvre que des pages TikTok
        String titre = valeur(donnees, "titre");
        String corps = valeur(donnees, "corps");
        notifierLive(this,
                titre.isEmpty() ? "Une boutique est en live sur TikTok" : titre,
                corps.isEmpty() ? "Touchez pour regarder le live." : corps,
                lien, valeur(donnees, "boutique"));
    }

    private static String valeur(Map<String, String> donnees, String cle) {
        String v = donnees.get(cle);
        return v == null ? "" : v.trim();
    }

    /** Une adresse https sur tiktok.com — rien d'autre ne s'ouvre d'une notification. */
    static boolean lienTikTok(String lien) {
        if (lien == null || lien.isEmpty()) return false;
        Uri uri = Uri.parse(lien);
        String hote = uri.getHost() == null ? "" : uri.getHost().toLowerCase();
        return "https".equals(uri.getScheme())
                && (hote.equals("tiktok.com") || hote.endsWith(".tiktok.com"));
    }

    private static void notifierLive(Context contexte, String titre, String corps,
                                     String lien, String boutique) {
        NotificationManager gestionnaire =
                (NotificationManager) contexte.getSystemService(Context.NOTIFICATION_SERVICE);
        if (gestionnaire == null) return;

        Notification.Builder constructeur;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            /* Importance HAUTE : un live, c'est maintenant ou jamais. Le client
               peut couper ce seul canal dans les réglages du téléphone sans
               perdre les nouveautés du catalogue. */
            NotificationChannel canal = new NotificationChannel(CANAL_LIVES,
                    "Lives TikTok des boutiques", NotificationManager.IMPORTANCE_HIGH);
            canal.setDescription("Prévient quand une boutique BIZZOO passe en direct sur TikTok.");
            gestionnaire.createNotificationChannel(canal);
            constructeur = new Notification.Builder(contexte, CANAL_LIVES);
        } else {
            constructeur = new Notification.Builder(contexte)
                    .setPriority(Notification.PRIORITY_HIGH);
        }

        /* La touche ouvre la page TikTok : l'application TikTok si elle est
           là, sinon le navigateur. */
        Intent ouverture = new Intent(Intent.ACTION_VIEW, Uri.parse(lien));
        ouverture.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        int drapeaux = PendingIntent.FLAG_UPDATE_CURRENT
                | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0);
        int numero = ("live:" + boutique).hashCode();
        PendingIntent action = PendingIntent.getActivity(contexte, numero, ouverture, drapeaux);

        Notification notification = constructeur
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(titre)
                .setContentText(corps)
                .setStyle(new Notification.BigTextStyle().bigText(corps))
                .setAutoCancel(true)
                .setContentIntent(action)
                .build();
        try {
            /* Une notification par boutique : un second message du même live
               remplace le premier au lieu de s'empiler. */
            gestionnaire.notify(numero, notification);
        } catch (SecurityException e) {
            /* Le client a refusé les notifications : rien à faire. */
        }
    }
}
