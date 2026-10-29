package com.impactinformatique.apps;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;

import org.json.JSONObject;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Scanner;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

/**
 * La position du livreur pendant ses courses, même application fermée
 * (BIZZOO Admin). BIZZOO Personnel la montre sur « Localiser un livreur ».
 *
 * (3.70.0) ET QUAND IL EST LIBRE, S'IL S'EST DIT « DISPONIBLE » : la course
 * va d'abord au livreur le plus proche, encore faut-il savoir où il est. Le
 * service appelle « position_livreur », qui dit s'il faut continuer et si le
 * livreur est en course : en course, une position toutes les 20 secondes ;
 * libre, toutes les 3 minutes (la batterie compte). Une base d'avant (sans
 * « position_livreur ») : il revient à « position_en_course », comme avant.
 *
 * Le service tourne au premier plan (notification permanente « BIZZOO
 * suit votre position pendant vos courses »), comme l'exige Android pour
 * une localisation hors de l'écran. Il envoie la position toutes les
 * 20 secondes environ, et au moins toutes les 2 minutes s'il ne bouge
 * pas, à « position_en_course », avec un JETON DE SUIVI que la page lui
 * a donné : il ne tient pas la session du compte, et ce jeton ne permet
 * que cela. Quand la base répond « continuer : false » (plus de course),
 * ou refuse le jeton, il s'arrête de lui-même.
 */
public class ServiceSuiviPosition extends Service implements LocationListener {

    static final String EXTRA_URL = "bizzoo.suivi.url";
    static final String EXTRA_CLE = "bizzoo.suivi.cle";
    static final String EXTRA_JETON = "bizzoo.suivi.jeton";
    private static final String PREFERENCES = "bizzoo-suivi-position";
    private static final String CANAL = "suivi-position";
    private static final int NUMERO = 7310;
    private static final long INTERVALLE_MS = 20_000;
    private static final long BATTEMENT_MS = 120_000;
    private static final float DISTANCE_M = 15f;
    /* (3.70.0) Libre et disponible : plus rarement. */
    private static final long INTERVALLE_LIBRE_MS = 180_000;
    private static final float DISTANCE_LIBRE_M = 50f;

    private final ExecutorService envois = Executors.newSingleThreadExecutor();
    private final Handler horloge = new Handler(Looper.getMainLooper());
    private LocationManager localisation;
    private Location derniere;
    private long dernierEnvoi = 0;
    private String url = "";
    private String cle = "";
    private volatile String jeton = "";
    /* (3.70.0) Le service tourne-t-il vraiment ? La page le demande au pont
       (« suiviActif ») avant de croire qu'il n'y a rien à relancer. */
    static volatile boolean actif = false;
    private volatile boolean detruit = false;
    /* (3.70.0) En course (rythme serré) ou libre et disponible (rythme lâche). */
    private volatile boolean enCourse = false;
    private volatile boolean ancienneBase = false;

    /** Démarrer (ou relancer avec un nouveau jeton) depuis la page. */
    static void demarrer(Context contexte, String url, String cle, String jeton) {
        Intent intention = new Intent(contexte, ServiceSuiviPosition.class)
                .putExtra(EXTRA_URL, url).putExtra(EXTRA_CLE, cle).putExtra(EXTRA_JETON, jeton);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) contexte.startForegroundService(intention);
        else contexte.startService(intention);
    }

    static void arreter(Context contexte) {
        contexte.getSharedPreferences(PREFERENCES, MODE_PRIVATE).edit().clear().apply();
        contexte.stopService(new Intent(contexte, ServiceSuiviPosition.class));
    }

    @Override
    public int onStartCommand(Intent intention, int drapeaux, int numero) {
        SharedPreferences prefs = getSharedPreferences(PREFERENCES, MODE_PRIVATE);
        if (intention != null && intention.hasExtra(EXTRA_JETON)) {
            url = intention.getStringExtra(EXTRA_URL);
            cle = intention.getStringExtra(EXTRA_CLE);
            jeton = intention.getStringExtra(EXTRA_JETON);
            prefs.edit().putString(EXTRA_URL, url).putString(EXTRA_CLE, cle)
                    .putString(EXTRA_JETON, jeton).apply();
        } else {
            /* Relancé par Android après l'avoir arrêté : le jeton gardé. */
            url = prefs.getString(EXTRA_URL, "");
            cle = prefs.getString(EXTRA_CLE, "");
            jeton = prefs.getString(EXTRA_JETON, "");
        }
        if (url == null || url.isEmpty() || jeton == null || jeton.isEmpty() || !positionPermise()) {
            arreterTout();
            return START_NOT_STICKY;
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NUMERO, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
            } else {
                startForeground(NUMERO, notification());
            }
        } catch (Exception e) {
            /* Android refuse un service de localisation lancé hors de
               l'écran : il repartira à la prochaine ouverture des courses. */
            arreterTout();
            return START_NOT_STICKY;
        }
        actif = true;
        ecouter();
        /* Une première position tout de suite : celle qu'on connaît. */
        if (derniere != null) envoyer(derniere);
        return START_STICKY;
    }

    private boolean positionPermise() {
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                || checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    @SuppressWarnings("MissingPermission")
    private void ecouter() {
        if (localisation == null) localisation = (LocationManager) getSystemService(LOCATION_SERVICE);
        if (localisation == null) return;
        try {
            localisation.removeUpdates(this);
            for (String fournisseur : new String[]{LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER}) {
                if (localisation.isProviderEnabled(fournisseur)) {
                    /* Libre : distance minimale 0, pour qu'Android réveille le
                       téléphone toutes les 3 minutes même s'il ne bouge pas —
                       un livreur qui attend à son point, écran éteint, doit
                       rester « récent » pour la cascade. */
                    localisation.requestLocationUpdates(fournisseur,
                            enCourse ? INTERVALLE_MS : INTERVALLE_LIBRE_MS,
                            enCourse ? DISTANCE_M : 0f, this, Looper.getMainLooper());
                    Location connue = localisation.getLastKnownLocation(fournisseur);
                    if (connue != null && (derniere == null || connue.getTime() > derniere.getTime())) derniere = connue;
                }
            }
        } catch (SecurityException e) {
            arreterTout();
            return;
        }
        horloge.removeCallbacksAndMessages(null);
        horloge.post(battement);
    }

    /* Immobile, le téléphone ne donne plus de position : on renvoie la
       dernière toutes les 2 minutes, ce qui dit aussi « toujours là » et
       demande à la base s'il reste une course. */
    private final Runnable battement = new Runnable() {
        @Override
        public void run() {
            long battement = enCourse ? BATTEMENT_MS : INTERVALLE_LIBRE_MS;
            if (derniere != null && System.currentTimeMillis() - dernierEnvoi >= battement - 1000) {
                envoyer(derniere);
            }
            horloge.postDelayed(this, battement);
        }
    };

    @Override
    public void onLocationChanged(Location position) {
        if (derniere != null && position.getAccuracy() > 200 && derniere.getAccuracy() < position.getAccuracy()
                && position.getTime() - derniere.getTime() < 60_000) {
            return;   // moins précise qu'une position récente : on la laisse
        }
        derniere = position;
        if (System.currentTimeMillis() - dernierEnvoi >= (enCourse ? INTERVALLE_MS : INTERVALLE_LIBRE_MS - 5_000)) {
            envoyer(position);
        }
    }

    @Override public void onStatusChanged(String fournisseur, int etat, Bundle extras) { }
    @Override public void onProviderEnabled(String fournisseur) { }
    @Override public void onProviderDisabled(String fournisseur) { }

    private void envoyer(final Location position) {
        if (detruit) return;
        dernierEnvoi = System.currentTimeMillis();
        final double lat = position.getLatitude();
        final double lng = position.getLongitude();
        final int precision = Math.round(position.getAccuracy());
        /* (3.70.0) Le jeton de CET envoi : si la page en a donné un nouveau
           entre-temps, le refus de l'ancien ne coupe pas le service. */
        final String jetonEnvoye = jeton;
        /* Le processeur ne s'endort pas au milieu de l'envoi. */
        PowerManager energie = (PowerManager) getSystemService(POWER_SERVICE);
        final PowerManager.WakeLock eveil = energie == null ? null
                : energie.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "bizzoo:position");
        if (eveil != null) eveil.acquire(30_000);
        try {
            envois.execute(() -> {
            HttpURLConnection connexion = null;
            try {
                JSONObject corps = new JSONObject();
                corps.put("jeton", jetonEnvoye);
                corps.put("lat", lat);
                corps.put("lng", lng);
                corps.put("precision_m", precision);
                connexion = (HttpURLConnection) new URL(url + "/rest/v1/rpc/"
                        + (ancienneBase ? "position_en_course" : "position_livreur")).openConnection();
                connexion.setRequestMethod("POST");
                connexion.setConnectTimeout(15_000);
                connexion.setReadTimeout(15_000);
                connexion.setDoOutput(true);
                connexion.setRequestProperty("apikey", cle);
                connexion.setRequestProperty("Content-Type", "application/json");
                try (OutputStream sortie = connexion.getOutputStream()) {
                    sortie.write(corps.toString().getBytes(StandardCharsets.UTF_8));
                }
                int statut = connexion.getResponseCode();
                if (statut == 404 && !ancienneBase) {
                    /* Base d'avant la 3.70.0 : pas de « position_livreur ». Elle
                       ne suit que les courses : même point, tout de suite, à
                       « position_en_course ». */
                    ancienneBase = true;
                    horloge.post(() -> { changerDeRythme(true); envoyer(position); });
                    return;
                }
                if (statut >= 400 && statut < 500) {
                    /* Jeton expiré ou refusé : la page en redonnera un. */
                    horloge.post(() -> { if (jetonEnvoye.equals(jeton)) arreterTout(); });
                    return;
                }
                if (statut >= 200 && statut < 300) {
                    String reponse;
                    try (InputStream entree = connexion.getInputStream();
                         Scanner lecteur = new Scanner(entree, "UTF-8").useDelimiter("\\A")) {
                        reponse = lecteur.hasNext() ? lecteur.next() : "";
                    }
                    if (reponse.contains("\"continuer\": false") || reponse.contains("\"continuer\":false")) {
                        horloge.post(() -> { if (jetonEnvoye.equals(jeton)) arreterTout(); });
                        return;
                    }
                    /* (3.70.0) En course, ou libre : le rythme et la notification suivent. */
                    final boolean course = ancienneBase
                            || reponse.contains("\"en_course\": true") || reponse.contains("\"en_course\":true");
                    horloge.post(() -> changerDeRythme(course));
                }
            } catch (Exception e) {
                /* Réseau absent : la prochaine position repartira. */
            } finally {
                if (connexion != null) connexion.disconnect();
                if (eveil != null && eveil.isHeld()) eveil.release();
            }
            });
        } catch (RejectedExecutionException e) {
            /* Service déjà arrêté : rien à envoyer. */
            if (eveil != null && eveil.isHeld()) eveil.release();
        }
    }

    /** (3.70.0) Passe du rythme « course » au rythme « libre », ou l'inverse. */
    private void changerDeRythme(boolean course) {
        if (detruit || course == enCourse) return;
        enCourse = course;
        NotificationManager gestionnaire = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (gestionnaire != null) gestionnaire.notify(NUMERO, notification());
        ecouter();
    }

    private Notification notification() {
        Notification.Builder constructeur;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager gestionnaire = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            NotificationChannel canal = new NotificationChannel(CANAL, "Position pour les courses",
                    NotificationManager.IMPORTANCE_LOW);
            canal.setDescription("Pendant vos courses, et tant que vous êtes disponible, BIZZOO voit où vous êtes "
                    + "pour vous proposer les courses les plus proches.");
            canal.setShowBadge(false);
            if (gestionnaire != null) gestionnaire.createNotificationChannel(canal);
            constructeur = new Notification.Builder(this, CANAL);
        } else {
            constructeur = new Notification.Builder(this).setPriority(Notification.PRIORITY_LOW);
        }
        Intent ouverture = new Intent(this, MainActivity.class);
        ouverture.putExtra(MainActivity.EXTRA_LIEN, "#/livraisons");
        ouverture.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        int drapeaux = PendingIntent.FLAG_UPDATE_CURRENT
                | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0);
        return constructeur
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(enCourse ? "Course en cours" : "Disponible pour les courses")
                .setContentText(enCourse
                        ? "BIZZOO suit votre position jusqu'à la fin de vos courses."
                        : "BIZZOO vous propose les courses les plus proches. Livraisons → « Disponible » pour arrêter.")
                .setContentIntent(PendingIntent.getActivity(this, NUMERO, ouverture, drapeaux))
                .setOngoing(true)
                .build();
    }

    private void arreterTout() {
        actif = false;
        if (detruit) return;
        horloge.removeCallbacksAndMessages(null);
        if (localisation != null) {
            try { localisation.removeUpdates(this); } catch (Exception e) { /* vide */ }
        }
        getSharedPreferences(PREFERENCES, MODE_PRIVATE).edit().clear().apply();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE);
        else stopForeground(true);
        stopSelf();
    }

    @Override
    public void onDestroy() {
        detruit = true;
        actif = false;
        horloge.removeCallbacksAndMessages(null);
        if (localisation != null) {
            try { localisation.removeUpdates(this); } catch (Exception e) { /* vide */ }
        }
        envois.shutdown();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intention) {
        return null;
    }
}
