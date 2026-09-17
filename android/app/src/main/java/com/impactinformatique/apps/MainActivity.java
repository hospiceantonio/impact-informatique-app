package com.impactinformatique.apps;

import android.Manifest;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.pm.PackageManager;
import android.content.ContentValues;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Matrix;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.GeolocationPermissions;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;
import androidx.exifinterface.media.ExifInterface;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;

/**
 * Coquille Android des applications BIZZOO :
 * la WebView charge les fichiers embarqués (assets/www) et
 * délègue au téléphone les liens externes (WhatsApp, appels…),
 * la prise de photos et l'enregistrement des sauvegardes.
 *
 * Les fichiers sont servis directement depuis les assets par
 * shouldInterceptRequest : une adresse appassets.androidx.dev
 * ne part JAMAIS sur le réseau (ce domaine ne répond pas).
 */
public class MainActivity extends Activity {

    private static final String ORIGINE = "https://appassets.androidx.dev";
    private static final String PAGE_ACCUEIL = ORIGINE + "/assets/www/index.html";
    /* L'application vendeur, quand on veut y sauter depuis celle-ci.
       Sur Android 11 et au-delà, une application ne VOIT pas les autres
       sans les avoir déclarées dans « queries » : sans cette
       déclaration, le système répond que rien n'est installé, même
       quand l'app est là. C'est dans AndroidManifest.xml. */
    private static final String PAQUET_ADMIN = "com.impactinformatique.admin";

    private static final int CODE_CHOIX_FICHIER = 41;
    private static final int CODE_POSITION = 42;
    private static final int CODE_NOTIFICATIONS = 43;

    private WebView vueWeb;
    private ValueCallback<Uri[]> rappelChoixFichier;
    private Uri photoEnCours;
    private String origineposition;
    private GeolocationPermissions.Callback rappelPosition;

    @Override
    protected void onCreate(Bundle etat) {
        super.onCreate(etat);

        FrameLayout racine = new FrameLayout(this);
        racine.setBackgroundColor(ContextCompat.getColor(this, R.color.fond_demarrage));
        vueWeb = new WebView(this);
        vueWeb.setBackgroundColor(Color.TRANSPARENT);
        racine.addView(vueWeb, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        setContentView(racine);

        /* Plein écran : ni barre d'état ni barre de navigation, l'application
           occupe tout l'écran. Un glissement depuis un bord les ramène le
           temps de s'en servir. */
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        passerEnPleinEcran();

        /* Ce qui reste à contourner : l'encoche de l'appareil photo, et le
           clavier quand il s'ouvre sur un formulaire. */
        ViewCompat.setOnApplyWindowInsetsListener(racine, (v, insets) -> {
            Insets bords = insets.getInsets(WindowInsetsCompat.Type.systemBars()
                    | WindowInsetsCompat.Type.displayCutout()
                    | WindowInsetsCompat.Type.ime());
            vueWeb.setPadding(bords.left, bords.top, bords.right, bords.bottom);
            return WindowInsetsCompat.CONSUMED;
        });

        WebSettings reglages = vueWeb.getSettings();
        reglages.setJavaScriptEnabled(true);
        reglages.setDomStorageEnabled(true);
        reglages.setAllowFileAccess(false);
        reglages.setAllowContentAccess(false);
        reglages.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        reglages.setGeolocationEnabled(true);

        vueWeb.addJavascriptInterface(new PontAndroid(), "AndroidPont");

        vueWeb.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView vue, WebResourceRequest requete) {
                Uri url = requete.getUrl();
                if (url == null || !"https".equals(url.getScheme())
                        || !"appassets.androidx.dev".equals(url.getAuthority())) {
                    return null; // vraie requête réseau (base Supabase, photos…)
                }
                String chemin = url.getPath() == null ? "" : url.getPath();
                /* Accepte les deux formes d'adresse : /assets/www/… et /www/… */
                if (chemin.startsWith("/assets/")) chemin = chemin.substring("/assets/".length());
                else if (chemin.startsWith("/")) chemin = chemin.substring(1);
                WebResourceResponse reponse = reponseDepuisAssets(chemin);
                if (reponse != null) return reponse;
                /* Introuvable : réponse 404 claire, jamais le réseau. */
                byte[] corps = ("<!doctype html><meta charset=\"utf-8\"><title>Introuvable</title>" +
                        "<p>Fichier absent de l'application : " + chemin + "</p>")
                        .getBytes(StandardCharsets.UTF_8);
                return new WebResourceResponse("text/html", "utf-8", 404, "Not Found",
                        new HashMap<String, String>(), new ByteArrayInputStream(corps));
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView vue, WebResourceRequest requete) {
                Uri url = requete.getUrl();
                if (url.toString().startsWith(ORIGINE)) return false;

                /* La page de paiement s'ouvre dans un cadre à l'intérieur de
                   l'application. Deux raisons de ne pas l'expédier dehors :
                   un cadre n'est pas une navigation du client, et sortir au
                   milieu d'une transaction ferait perdre l'argent de vue. */
                if (!requete.isForMainFrame()) return false;
                if (estPaiement(url)) return false;

                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, url));
                } catch (ActivityNotFoundException e) {
                    Toast.makeText(MainActivity.this,
                            "Aucune application pour ouvrir ce lien.", Toast.LENGTH_SHORT).show();
                }
                return true;
            }

            @Override
            public void onReceivedError(WebView vue, WebResourceRequest requete, WebResourceError erreur) {
                if (!requete.isForMainFrame()) return;
                /* Page de diagnostic : version visible + bouton réessayer. */
                String page = "<!doctype html><html lang=\"fr\"><meta charset=\"utf-8\">" +
                        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" +
                        "<body style=\"margin:0;font-family:sans-serif;background:#0B4FA0;color:#fff;" +
                        "min-height:100vh;display:flex;align-items:center;justify-content:center;text-align:center\">" +
                        "<div style=\"padding:24px\"><h2 style=\"margin:0 0 10px\">Ouverture impossible</h2>" +
                        "<p style=\"opacity:.85;font-size:14px;word-break:break-all\">" +
                        erreur.getDescription() + "<br>" + requete.getUrl() + "</p>" +
                        "<p style=\"font-size:13px;opacity:.7\">Application version " + versionApplication() + "</p>" +
                        "<p><a href=\"" + PAGE_ACCUEIL + "\" style=\"display:inline-block;margin-top:8px;" +
                        "padding:12px 22px;background:#E62329;color:#fff;border-radius:10px;" +
                        "text-decoration:none;font-weight:bold\">Réessayer</a></p></div>";
                vue.loadDataWithBaseURL(ORIGINE + "/assets/www/erreur.html", page, "text/html", "utf-8", null);
            }
        });

        vueWeb.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView vue, ValueCallback<Uri[]> rappel,
                                             FileChooserParams parametres) {
                if (rappelChoixFichier != null) rappelChoixFichier.onReceiveValue(null);
                rappelChoixFichier = rappel;
                ouvrirChoixPhoto(parametres);
                return true;
            }

            /* Relevé de la position de la boutique (réglages de l'admin). */
            @Override
            public void onGeolocationPermissionsShowPrompt(String origine,
                                                           GeolocationPermissions.Callback rappel) {
                if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                        == PackageManager.PERMISSION_GRANTED) {
                    rappel.invoke(origine, true, false);
                    return;
                }
                origineposition_memoriser(origine, rappel);
                requestPermissions(new String[]{
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION}, CODE_POSITION);
            }
        });

        vueWeb.loadUrl(PAGE_ACCUEIL);

        demanderNotifications();
        VerificateurCatalogue.programmer(this);
    }

    /**
     * Les adresses de KkiaPay, qui portent le paiement Mobile Money.
     * Elles restent DANS l'application : c'est le seul moyen que le
     * client revienne sur sa commande une fois payée.
     */
    private static boolean estPaiement(Uri url) {
        String hote = url.getAuthority();
        if (hote == null) return false;
        hote = hote.toLowerCase();
        return hote.equals("kkiapay.me") || hote.endsWith(".kkiapay.me");
    }

    /* ---------- Plein écran ---------- */

    private void passerEnPleinEcran() {
        if (vueWeb == null) return;
        WindowInsetsControllerCompat controleur =
                WindowCompat.getInsetsController(getWindow(), vueWeb);
        controleur.setSystemBarsBehavior(
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
        controleur.hide(WindowInsetsCompat.Type.systemBars());
    }

    /**
     * Le système remet ses barres après un appel, une notification déroulée
     * ou le choix d'une photo : on repasse en plein écran au retour.
     */
    @Override
    public void onWindowFocusChanged(boolean aLeFocus) {
        super.onWindowFocusChanged(aLeFocus);
        if (aLeFocus) passerEnPleinEcran();
    }

    /* ---------- Notifications ---------- */

    /**
     * Autorisation d'afficher les nouveautés du catalogue dans la barre
     * de notifications. Obligatoire à partir d'Android 13 ; avant, elle
     * est acquise à l'installation.
     */
    private void demanderNotifications() {
        if (!getResources().getBoolean(R.bool.notifications_actives)) return;
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return;
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED) return;
        requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},
                CODE_NOTIFICATIONS);
    }

    /* ---------- Position ---------- */

    private void origineposition_memoriser(String origine, GeolocationPermissions.Callback rappel) {
        origineposition = origine;
        rappelPosition = rappel;
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] permissions, int[] resultats) {
        super.onRequestPermissionsResult(code, permissions, resultats);
        if (code != CODE_POSITION || rappelPosition == null) return;
        boolean accordee = resultats.length > 0 && resultats[0] == PackageManager.PERMISSION_GRANTED;
        rappelPosition.invoke(origineposition, accordee, false);
        rappelPosition = null;
        origineposition = null;
    }

    /* ---------- Fichiers embarqués ---------- */

    private WebResourceResponse reponseDepuisAssets(String chemin) {
        if (chemin.isEmpty() || chemin.endsWith("/")) chemin = chemin + "index.html";
        try {
            InputStream flux = getAssets().open(chemin);
            return new WebResourceResponse(typeMime(chemin), "utf-8", flux);
        } catch (IOException e) {
            return null;
        }
    }

    private static String typeMime(String chemin) {
        String c = chemin.toLowerCase();
        if (c.endsWith(".html")) return "text/html";
        if (c.endsWith(".js")) return "application/javascript";
        if (c.endsWith(".css")) return "text/css";
        if (c.endsWith(".json")) return "application/json";
        if (c.endsWith(".webmanifest")) return "application/manifest+json";
        if (c.endsWith(".svg")) return "image/svg+xml";
        if (c.endsWith(".png")) return "image/png";
        if (c.endsWith(".jpg") || c.endsWith(".jpeg")) return "image/jpeg";
        if (c.endsWith(".ico")) return "image/x-icon";
        return "application/octet-stream";
    }

    private String versionApplication() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (Exception e) {
            return "?";
        }
    }

    /* ---------- Choix / prise de photo ---------- */

    private void ouvrirChoixPhoto(WebChromeClient.FileChooserParams parametres) {
        /* La page indique ce qu'elle attend : image/* ou video/*. */
        String attendu = "image/*";
        if (parametres != null && parametres.getAcceptTypes() != null) {
            for (String t : parametres.getAcceptTypes()) {
                if (t != null && t.startsWith("video")) { attendu = "video/*"; break; }
            }
        }
        final boolean video = attendu.startsWith("video");

        Intent galerie = new Intent(Intent.ACTION_GET_CONTENT);
        galerie.addCategory(Intent.CATEGORY_OPENABLE);
        galerie.setType(attendu);
        boolean plusieurs = parametres != null
                && parametres.getMode() == WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE;
        if (plusieurs) galerie.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);

        Intent choix = Intent.createChooser(galerie,
                video ? "Vidéo du produit" : "Photo du produit");

        if (video) {
            /* Filmer directement, sans passer par la galerie. */
            photoEnCours = null;
            Intent camera = new Intent(MediaStore.ACTION_VIDEO_CAPTURE);
            choix.putExtra(Intent.EXTRA_INITIAL_INTENTS, new Intent[]{camera});
            try {
                startActivityForResult(choix, CODE_CHOIX_FICHIER);
            } catch (ActivityNotFoundException e) {
                repondreAuChoix(null);
            }
            return;
        }

        try {
            File dossier = new File(getCacheDir(), "photos");
            //noinspection ResultOfMethodCallIgnored
            dossier.mkdirs();
            File fichier = new File(dossier, "capture-" + System.currentTimeMillis() + ".jpg");
            //noinspection ResultOfMethodCallIgnored
            fichier.createNewFile();
            photoEnCours = FileProvider.getUriForFile(this,
                    getPackageName() + ".fichiers", fichier);
            Intent appareil = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
            appareil.putExtra(MediaStore.EXTRA_OUTPUT, photoEnCours);
            appareil.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            choix.putExtra(Intent.EXTRA_INITIAL_INTENTS, new Intent[]{appareil});
        } catch (Exception e) {
            photoEnCours = null; // pas d'appareil photo disponible : galerie seule
        }

        try {
            startActivityForResult(choix, CODE_CHOIX_FICHIER);
        } catch (ActivityNotFoundException e) {
            repondreAuChoix(null);
        }
    }

    @Override
    protected void onActivityResult(int code, int resultat, Intent donnees) {
        super.onActivityResult(code, resultat, donnees);
        if (code != CODE_CHOIX_FICHIER || rappelChoixFichier == null) return;

        Uri[] resultats = null;
        if (resultat == RESULT_OK) {
            if (donnees != null && donnees.getClipData() != null) {
                ArrayList<Uri> liste = new ArrayList<>();
                for (int i = 0; i < donnees.getClipData().getItemCount(); i++) {
                    liste.add(donnees.getClipData().getItemAt(i).getUri());
                }
                resultats = liste.toArray(new Uri[0]);
            } else if (donnees != null && donnees.getData() != null) {
                resultats = new Uri[]{donnees.getData()};
            } else if (photoEnCours != null) {
                resultats = new Uri[]{photoEnCours}; // photo prise avec l'appareil
            }
        }
        repondreAuChoix(resultats);
    }

    /**
     * Rend la main à la page. Les photos sont d'abord reconverties en JPEG
     * par Android : les téléphones récents enregistrent en HEIC/HEIF, un
     * format que la WebView ne sait pas décoder. Les vidéos passent telles
     * quelles.
     */
    private void repondreAuChoix(final Uri[] sources) {
        final ValueCallback<Uri[]> rappel = rappelChoixFichier;
        rappelChoixFichier = null;
        if (rappel == null) return;
        if (sources == null || sources.length == 0) {
            rappel.onReceiveValue(null);
            return;
        }
        new Thread(() -> {
            final Uri[] sorties = new Uri[sources.length];
            for (int i = 0; i < sources.length; i++) {
                Uri convertie = convertirImageEnJpeg(sources[i]);
                sorties[i] = convertie != null ? convertie : sources[i];
            }
            runOnUiThread(() -> rappel.onReceiveValue(sorties));
        }).start();
    }

    /** Renvoie un JPEG lisible par la WebView, ou null si rien à convertir. */
    private Uri convertirImageEnJpeg(Uri source) {
        String type = getContentResolver().getType(source);
        if (type != null && type.startsWith("video/")) return null; // vidéo : telle quelle

        try {
            /* Taille de lecture réduite : une photo de 12 Mpx tient en mémoire. */
            BitmapFactory.Options mesure = new BitmapFactory.Options();
            mesure.inJustDecodeBounds = true;
            try (InputStream flux = getContentResolver().openInputStream(source)) {
                BitmapFactory.decodeStream(flux, null, mesure);
            }
            int cote = Math.max(mesure.outWidth, mesure.outHeight);
            if (cote <= 0) return null; // format inconnu d'Android aussi

            BitmapFactory.Options lecture = new BitmapFactory.Options();
            lecture.inSampleSize = Math.max(1, Integer.highestOneBit(cote / 2200));
            Bitmap image;
            try (InputStream flux = getContentResolver().openInputStream(source)) {
                image = BitmapFactory.decodeStream(flux, null, lecture);
            }
            if (image == null) return null;

            image = redresser(image, source);

            File dossier = new File(getCacheDir(), "photos");
            //noinspection ResultOfMethodCallIgnored
            dossier.mkdirs();
            File fichier = new File(dossier, "photo-" + System.currentTimeMillis() + "-"
                    + Math.abs(source.hashCode()) + ".jpg");
            try (FileOutputStream sortie = new FileOutputStream(fichier)) {
                image.compress(Bitmap.CompressFormat.JPEG, 90, sortie);
            }
            image.recycle();
            return FileProvider.getUriForFile(this, getPackageName() + ".fichiers", fichier);
        } catch (Throwable e) {
            return null; // on laissera passer le fichier d'origine
        }
    }

    /** Applique l'orientation EXIF (photo prise en portrait, appareil tourné…). */
    private Bitmap redresser(Bitmap image, Uri source) {
        try (InputStream flux = getContentResolver().openInputStream(source)) {
            if (flux == null) return image;
            int orientation = new ExifInterface(flux).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
            Matrix matrice = new Matrix();
            switch (orientation) {
                case ExifInterface.ORIENTATION_ROTATE_90: matrice.postRotate(90); break;
                case ExifInterface.ORIENTATION_ROTATE_180: matrice.postRotate(180); break;
                case ExifInterface.ORIENTATION_ROTATE_270: matrice.postRotate(270); break;
                case ExifInterface.ORIENTATION_FLIP_HORIZONTAL: matrice.postScale(-1, 1); break;
                case ExifInterface.ORIENTATION_FLIP_VERTICAL: matrice.postScale(1, -1); break;
                default: return image;
            }
            Bitmap redressee = Bitmap.createBitmap(image, 0, 0,
                    image.getWidth(), image.getHeight(), matrice, true);
            if (redressee != image) image.recycle();
            return redressee;
        } catch (Throwable e) {
            return image;
        }
    }

    /* ---------- Retour ---------- */

    @Override
    public void onBackPressed() {
        if (vueWeb.canGoBack()) vueWeb.goBack();
        else super.onBackPressed();
    }

    /* ---------- Pont JavaScript : enregistrer un fichier ---------- */

    private class PontAndroid {
        @JavascriptInterface
        public void enregistrerFichier(String nom, String base64, String type) {
            enregistrer(nom, base64, type, true);
        }

        /** Même chose sans message : la page annonce elle-même le résultat. */
        @JavascriptInterface
        public void enregistrerFichierDiscret(String nom, String base64, String type) {
            enregistrer(nom, base64, type, false);
        }

        private void enregistrer(String nom, String base64, String type, boolean annoncer) {
            try {
                byte[] octets = Base64.decode(base64, Base64.DEFAULT);
                if (Build.VERSION.SDK_INT >= 29) {
                    ContentValues valeurs = new ContentValues();
                    valeurs.put(MediaStore.Downloads.DISPLAY_NAME, nom);
                    valeurs.put(MediaStore.Downloads.MIME_TYPE,
                            type == null || type.isEmpty() ? "application/octet-stream" : type);
                    Uri uri = getContentResolver().insert(
                            MediaStore.Downloads.EXTERNAL_CONTENT_URI, valeurs);
                    if (uri == null) throw new Exception("insertion refusée");
                    try (OutputStream sortie = getContentResolver().openOutputStream(uri)) {
                        sortie.write(octets);
                    }
                    if (annoncer) annoncer("Fichier enregistré dans Téléchargements : " + nom);
                } else {
                    File dossier = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
                    File fichier = new File(dossier, nom);
                    try (FileOutputStream sortie = new FileOutputStream(fichier)) {
                        sortie.write(octets);
                    }
                    if (annoncer) annoncer("Fichier enregistré : " + fichier.getAbsolutePath());
                }
            } catch (Exception e) {
                annoncer("Enregistrement impossible : " + e.getMessage());
            }
        }

        /**
         * L'application BIZZOO Admin est-elle installée sur ce
         * téléphone ? La page s'en sert pour proposer de l'OUVRIR plutôt
         * que de promettre un bouton qui ne mènerait nulle part.
         */
        @JavascriptInterface
        public boolean espaceVendeurPresent() {
            try {
                return getPackageManager()
                        .getLaunchIntentForPackage(PAQUET_ADMIN) != null;
            } catch (Exception e) {
                return false;
            }
        }

        /**
         * Passer à l'application vendeur.
         *
         * Elle ne donne aucun droit : elle demande de s'identifier, et
         * c'est la base qui décide ensuite de ce que ce compte peut
         * faire. Ce pont ne fait qu'éviter de sortir de l'application
         * pour aller chercher une icône sur l'écran d'accueil.
         */
        @JavascriptInterface
        public void ouvrirEspaceVendeur() {
            runOnUiThread(() -> {
                try {
                    Intent vers = getPackageManager()
                            .getLaunchIntentForPackage(PAQUET_ADMIN);
                    if (vers != null) {
                        vers.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(vers);
                        return;
                    }
                    annoncer("BIZZOO Admin n'est pas installée sur ce téléphone.");
                } catch (Exception e) {
                    annoncer("Impossible d'ouvrir l'espace vendeur : " + e.getMessage());
                }
            });
        }

        /**
         * Le catalogue affiché à l'écran est à jour : la vérification de
         * fond ne préviendra donc pas d'une nouveauté déjà vue.
         */
        @JavascriptInterface
        public void majDerniereVue(String signature) {
            if (signature == null || signature.isEmpty()) return;
            VerificateurCatalogue.memoriserVue(MainActivity.this, signature);
        }

        private void annoncer(String message) {
            runOnUiThread(() ->
                    Toast.makeText(MainActivity.this, message, Toast.LENGTH_LONG).show());
        }
    }
}
