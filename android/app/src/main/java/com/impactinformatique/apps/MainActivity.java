package com.impactinformatique.apps;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ContentValues;
import android.content.Intent;
import android.graphics.Color;
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
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;

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
 * Coquille Android des applications IMPACT INFORMATIQUE :
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
    private static final int CODE_CHOIX_FICHIER = 41;

    private WebView vueWeb;
    private ValueCallback<Uri[]> rappelChoixFichier;
    private Uri photoEnCours;

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

        /* Barres système : l'application peint derrière, la WebView est décalée. */
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        ViewCompat.setOnApplyWindowInsetsListener(racine, (v, insets) -> {
            Insets barres = insets.getInsets(WindowInsetsCompat.Type.systemBars()
                    | WindowInsetsCompat.Type.displayCutout());
            vueWeb.setPadding(barres.left, barres.top, barres.right, barres.bottom);
            return WindowInsetsCompat.CONSUMED;
        });

        WebSettings reglages = vueWeb.getSettings();
        reglages.setJavaScriptEnabled(true);
        reglages.setDomStorageEnabled(true);
        reglages.setAllowFileAccess(false);
        reglages.setAllowContentAccess(false);
        reglages.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);

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
        });

        vueWeb.loadUrl(PAGE_ACCUEIL);
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
        Intent galerie = new Intent(Intent.ACTION_GET_CONTENT);
        galerie.addCategory(Intent.CATEGORY_OPENABLE);
        galerie.setType("image/*");
        boolean plusieurs = parametres != null
                && parametres.getMode() == WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE;
        if (plusieurs) galerie.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);

        Intent choix = Intent.createChooser(galerie, "Photo du produit");

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
            if (rappelChoixFichier != null) rappelChoixFichier.onReceiveValue(null);
            rappelChoixFichier = null;
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
        rappelChoixFichier.onReceiveValue(resultats);
        rappelChoixFichier = null;
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
                    annoncer("Fichier enregistré dans Téléchargements : " + nom);
                } else {
                    File dossier = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
                    File fichier = new File(dossier, nom);
                    try (FileOutputStream sortie = new FileOutputStream(fichier)) {
                        sortie.write(octets);
                    }
                    annoncer("Fichier enregistré : " + fichier.getAbsolutePath());
                }
            } catch (Exception e) {
                annoncer("Enregistrement impossible : " + e.getMessage());
            }
        }

        private void annoncer(String message) {
            runOnUiThread(() ->
                    Toast.makeText(MainActivity.this, message, Toast.LENGTH_LONG).show());
        }
    }
}
