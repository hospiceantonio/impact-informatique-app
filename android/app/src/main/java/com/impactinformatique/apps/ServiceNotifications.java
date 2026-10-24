package com.impactinformatique.apps;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.media.AudioAttributes;
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
 * « telle boutique est en live sur TikTok » (application client), et
 * (3.65.0) les courses et les commandes de l'équipe (application admin),
 * qui SONNENT même application fermée.
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
    /* (3.65.0) Les identifiants d'un canal ne se réutilisent pas : son son
       et son importance sont figés à sa création. Changer l'un, c'est
       changer d'identifiant. */
    private static final String CANAL_COURSES = "courses_v1";
    private static final String CANAL_COMMANDES = "commandes_v1";
    private static final String JOURNAL = "BizzooNotifications";
    private static final String PREFS = "bizzoo-push";
    private static final String CLE_JETON = "jeton";

    /* ---------- (3.65.0) Le jeton de CE téléphone ----------
       Firebase le donne quand il veut — au premier lancement, puis à
       chaque renouvellement. On le garde ici ; la page le demande par
       le pont (« jetonPush ») et le déclare elle-même à la base, avec la
       session du compte connecté. */
    static void preparerPush(Context contexte) {
        try {
            if (FirebaseApp.getApps(contexte).isEmpty()) return;  // Firebase pas réglé
            final Context app = contexte.getApplicationContext();
            FirebaseMessaging.getInstance().getToken().addOnCompleteListener(tache -> {
                if (tache.isSuccessful() && tache.getResult() != null) garderJeton(app, tache.getResult());
            });
        } catch (RuntimeException e) {
            Log.w(JOURNAL, "Jeton indisponible : " + e.getMessage());
        }
    }

    static String jeton(Context contexte) {
        return contexte.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(CLE_JETON, "");
    }

    private static void garderJeton(Context contexte, String jeton) {
        SharedPreferences.Editor e = contexte.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit();
        e.putString(CLE_JETON, jeton == null ? "" : jeton);
        e.apply();
    }

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
        /* Les lives s'écrivent au sujet ; mais l'équipe (3.65.0) reçoit à
           SON téléphone : le nouveau jeton est gardé, et la page le
           redéclarera à sa prochaine ouverture. */
        garderJeton(this, jeton);
    }

    @Override
    public void onMessageReceived(RemoteMessage message) {
        Map<String, String> donnees = message.getData();
        if (donnees == null) return;
        if ("notification".equals(donnees.get("type"))) {
            notifierEquipe(this, donnees);
            return;
        }
        if (!"live".equals(donnees.get("type"))) return;
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

    /* ---------- (3.65.0) Une course, une commande : ça sonne ----------
       LA COURSE SONNE JUSQU'À CE QU'ON LA TOUCHE (« insistante ») — comme
       dans l'application ouverte : rater une course coûte plus cher qu'un
       son qui insiste. La commande d'une boutique sonne une fois, fort.
       Application au premier plan : rien ici, l'application sonne déjà. */
    private static void notifierEquipe(Context contexte, Map<String, String> donnees) {
        if (MainActivity.auPremierPlan) return;
        NotificationManager gestionnaire =
                (NotificationManager) contexte.getSystemService(Context.NOTIFICATION_SERVICE);
        if (gestionnaire == null) return;
        boolean course = "courses".equals(valeur(donnees, "canal"));
        String titre = valeur(donnees, "titre");
        String corps = valeur(donnees, "corps");
        String lien = valeur(donnees, "lien");
        if (!lien.startsWith("#/")) lien = course ? "#/livraisons" : "#/commandes";

        Uri son = Uri.parse("android.resource://" + contexte.getPackageName() + "/" + R.raw.sonnerie_course);
        long[] vibration = new long[]{0, 600, 250, 600, 250, 600};
        Notification.Builder constructeur;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            String id = course ? CANAL_COURSES : CANAL_COMMANDES;
            NotificationChannel canal = new NotificationChannel(id,
                    course ? "Courses à livrer" : "Commandes de la boutique",
                    NotificationManager.IMPORTANCE_HIGH);
            canal.setDescription(course
                    ? "Sonne jusqu'à ce que vous touchiez la notification : une course vous attend."
                    : "Sonne à chaque commande payée pour votre boutique.");
            canal.setSound(son, new AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(course ? AudioAttributes.USAGE_NOTIFICATION_RINGTONE
                                     : AudioAttributes.USAGE_NOTIFICATION_EVENT)
                    .build());
            canal.enableVibration(true);
            canal.setVibrationPattern(vibration);
            canal.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            gestionnaire.createNotificationChannel(canal);
            constructeur = new Notification.Builder(contexte, id);
        } else {
            constructeur = new Notification.Builder(contexte)
                    .setPriority(Notification.PRIORITY_MAX)
                    .setSound(son)
                    .setVibrate(vibration);
        }

        /* La touche ouvre BIZZOO Admin à l'écran de la course ou de la
           commande. */
        Intent ouverture = new Intent(contexte, MainActivity.class);
        ouverture.putExtra(MainActivity.EXTRA_LIEN, lien);
        ouverture.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        int numero = ("equipe:" + valeur(donnees, "id")).hashCode();
        int drapeaux = PendingIntent.FLAG_UPDATE_CURRENT
                | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0);
        PendingIntent action = PendingIntent.getActivity(contexte, numero, ouverture, drapeaux);

        Notification notification = constructeur
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(titre.isEmpty() ? "BIZZOO" : titre)
                .setContentText(corps)
                .setStyle(new Notification.BigTextStyle().bigText(corps))
                .setCategory(Notification.CATEGORY_MESSAGE)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setContentIntent(action)
                .build();
        if (course) notification.flags |= Notification.FLAG_INSISTENT;
        try {
            gestionnaire.notify(numero, notification);
        } catch (SecurityException e) {
            /* Notifications refusées dans les réglages du téléphone. */
        }
    }

    /** L'application s'ouvre : les sonneries en cours s'arrêtent, elle prend le relais. */
    static void taireEquipe(Context contexte) {
        NotificationManager gestionnaire =
                (NotificationManager) contexte.getSystemService(Context.NOTIFICATION_SERVICE);
        if (gestionnaire != null) gestionnaire.cancelAll();
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
