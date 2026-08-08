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
import android.view.View;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
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
import androidx.webkit.WebViewAssetLoader;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.util.ArrayList;

/**
 * Coquille Android des applications IMPACT INFORMATIQUE :
 * la WebView charge les fichiers embarqués (assets/www) et
 * délègue au téléphone les liens externes (WhatsApp, appels…),
 * la prise de photos et l'enregistrement des sauvegardes.
 */
public class MainActivity extends Activity {

    private static final String ORIGINE = "https://appassets.androidx.dev";
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

        final WebViewAssetLoader chargeur = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
                .build();

        vueWeb.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView vue, WebResourceRequest requete) {
                return chargeur.shouldInterceptRequest(requete.getUrl());
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

        vueWeb.loadUrl(ORIGINE + "/assets/www/index.html");
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
