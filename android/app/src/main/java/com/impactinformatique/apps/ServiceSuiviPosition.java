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

import org.json.JSONObject;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Scanner;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * La position du livreur pendant ses courses, même application fermée
 * (BIZZOO Admin). BIZZOO Personnel la montre sur « Localiser un livreur ».
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

    private final ExecutorService envois = Executors.newSingleThreadExecutor();
    private final Handler horloge = new Handler(Looper.getMainLooper());
    private LocationManager localisation;
    private Location derniere;
    private long dernierEnvoi = 0;
    private String url = "";
    private String cle = "";
    private String jeton = "";

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
        ecouter();
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
                    localisation.requestLocationUpdates(fournisseur, INTERVALLE_MS, DISTANCE_M, this, Looper.getMainLooper());
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
            if (derniere != null && System.currentTimeMillis() - dernierEnvoi >= BATTEMENT_MS - 1000) {
                envoyer(derniere);
            }
            horloge.postDelayed(this, BATTEMENT_MS);
        }
    };

    @Override
    public void onLocationChanged(Location position) {
        if (derniere != null && position.getAccuracy() > 200 && derniere.getAccuracy() < position.getAccuracy()
                && position.getTime() - derniere.getTime() < 60_000) {
            return;   // moins précise qu'une position récente : on la laisse
        }
        derniere = position;
        if (System.currentTimeMillis() - dernierEnvoi >= INTERVALLE_MS) envoyer(position);
    }

    @Override public void onStatusChanged(String fournisseur, int etat, Bundle extras) { }
    @Override public void onProviderEnabled(String fournisseur) { }
    @Override public void onProviderDisabled(String fournisseur) { }

    private void envoyer(Location position) {
        dernierEnvoi = System.currentTimeMillis();
        final double lat = position.getLatitude();
        final double lng = position.getLongitude();
        final int precision = Math.round(position.getAccuracy());
        envois.execute(() -> {
            HttpURLConnection connexion = null;
            try {
                JSONObject corps = new JSONObject();
                corps.put("jeton", jeton);
                corps.put("lat", lat);
                corps.put("lng", lng);
                corps.put("precision_m", precision);
                connexion = (HttpURLConnection) new URL(url + "/rest/v1/rpc/position_en_course").openConnection();
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
                if (statut >= 400 && statut < 500) {
                    /* Jeton expiré ou refusé : la page en redonnera un. */
                    horloge.post(this::arreterTout);
                    return;
                }
                if (statut >= 200 && statut < 300) {
                    String reponse;
                    try (InputStream entree = connexion.getInputStream();
                         Scanner lecteur = new Scanner(entree, "UTF-8").useDelimiter("\\A")) {
                        reponse = lecteur.hasNext() ? lecteur.next() : "";
                    }
                    if (reponse.contains("\"continuer\": false") || reponse.contains("\"continuer\":false")) {
                        horloge.post(this::arreterTout);
                    }
                }
            } catch (Exception e) {
                /* Réseau absent : la prochaine position repartira. */
            } finally {
                if (connexion != null) connexion.disconnect();
            }
        });
    }

    private Notification notification() {
        Notification.Builder constructeur;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager gestionnaire = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            NotificationChannel canal = new NotificationChannel(CANAL, "Position pendant les courses",
                    NotificationManager.IMPORTANCE_LOW);
            canal.setDescription("Tant que vous avez une course en cours, BIZZOO voit où vous êtes.");
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
                .setContentTitle("Course en cours")
                .setContentText("BIZZOO suit votre position jusqu'à la fin de vos courses.")
                .setContentIntent(PendingIntent.getActivity(this, NUMERO, ouverture, drapeaux))
                .setOngoing(true)
                .build();
    }

    private void arreterTout() {
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
