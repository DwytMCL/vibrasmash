package com.vibrasmash.recorder;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Shows the recorder page (assets/www/index.html) in a WebView.
 *
 * The page is served from https://appassets.androidplatform.net/, answered from the
 * APK's assets by shouldInterceptRequest, so it is a secure context and motion
 * sensors are allowed. Every other host gets a 404: the app works offline and
 * loads nothing from the network.
 */
public class MainActivity extends Activity {
    private static final String HOST = "appassets.androidplatform.net";
    private WebView web;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);           // threshold slider is remembered in localStorage
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        web.addJavascriptInterface(new Bridge(), "VibraSmashAndroid");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest req) {
                Uri u = req.getUrl();
                if (!HOST.equals(u.getHost())) return notFound();
                String path = u.getPath();
                if (path == null || path.equals("/")) path = "/index.html";
                if (path.contains("..")) return notFound();
                try {
                    InputStream in = getAssets().open("www" + path);
                    return new WebResourceResponse(mime(path), "utf-8", in);
                } catch (IOException e) {
                    return notFound();
                }
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                return !HOST.equals(req.getUrl().getHost());   // stay inside the app
            }
        });
        setContentView(web);
        web.loadUrl("https://" + HOST + "/index.html");
    }

    @Override
    protected void onDestroy() {
        if (web != null) web.destroy();
        super.onDestroy();
    }

    private static WebResourceResponse notFound() {
        return new WebResourceResponse("text/plain", "utf-8", 404, "Not Found", null,
                new ByteArrayInputStream(new byte[0]));
    }

    private static String mime(String path) {
        if (path.endsWith(".html")) return "text/html";
        if (path.endsWith(".js")) return "text/javascript";
        if (path.endsWith(".json")) return "application/json";
        if (path.endsWith(".png")) return "image/png";
        return "application/octet-stream";
    }

    /** Called from the page's JavaScript. */
    private class Bridge {
        @JavascriptInterface
        public String deviceModel() {
            return Build.MANUFACTURER + " " + Build.MODEL + " (Android " + Build.VERSION.RELEASE + ")";
        }

        /** Removes the previous recording's share copies (called at Start). */
        @JavascriptInterface
        public void clearShare() {
            File[] old = ShareProvider.shareDir(MainActivity.this).listFiles();
            if (old != null) for (File f : old) f.delete();
        }

        /**
         * Opens the Android share menu with the given files (names separated by '|'),
         * which must have been saved with saveText during this recording.
         * Returns "OK" or "ERROR: ...".
         */
        @JavascriptInterface
        public String shareFiles(String names, String message) {
            final java.util.ArrayList<Uri> uris = new java.util.ArrayList<>();
            for (String n : names.split("\\|")) {
                if (!n.matches("[A-Za-z0-9_.-]+")) return "ERROR: bad file name";
                if (!new File(ShareProvider.shareDir(MainActivity.this), n).isFile()) {
                    return "ERROR: " + n + " is not available to share; record again";
                }
                uris.add(ShareProvider.uriFor(n));
            }
            if (uris.isEmpty()) return "ERROR: nothing to share";
            final android.content.Intent send = new android.content.Intent(
                    uris.size() == 1 ? android.content.Intent.ACTION_SEND
                                     : android.content.Intent.ACTION_SEND_MULTIPLE);
            send.setType("*/*");   // widest match, so file-accepting apps such as Messenger are listed
            if (uris.size() == 1) send.putExtra(android.content.Intent.EXTRA_STREAM, uris.get(0));
            else send.putParcelableArrayListExtra(android.content.Intent.EXTRA_STREAM, uris);
            android.content.ClipData clip = android.content.ClipData.newRawUri(null, uris.get(0));
            for (int i = 1; i < uris.size(); i++) clip.addItem(new android.content.ClipData.Item(uris.get(i)));
            send.setClipData(clip);
            send.putExtra(android.content.Intent.EXTRA_SUBJECT, "VibraSmash phone recording");
            if (message != null && !message.isEmpty()) send.putExtra(android.content.Intent.EXTRA_TEXT, message);
            send.addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION);
            runOnUiThread(new Runnable() {
                @Override public void run() {
                    startActivity(android.content.Intent.createChooser(send, "Share recording"));
                }
            });
            return "OK";
        }

        /** Saves a text file to Download/VibraSmash. Returns the location, or "ERROR: ...". */
        @JavascriptInterface
        public String saveText(String name, String text) {
            if (name == null || !name.matches("[A-Za-z0-9_.-]+")) return "ERROR: bad file name";
            byte[] data = text.getBytes(StandardCharsets.UTF_8);
            // Private copy for the share menu (served by ShareProvider).
            try {
                File dir = ShareProvider.shareDir(MainActivity.this);
                if (!dir.isDirectory() && !dir.mkdirs()) return "ERROR: cannot create share folder";
                try (FileOutputStream out = new FileOutputStream(new File(dir, name))) { out.write(data); }
            } catch (IOException e) {
                return "ERROR: " + e.getMessage();
            }
            String type = name.endsWith(".csv") ? "text/csv" : "text/plain";
            try {
                if (Build.VERSION.SDK_INT >= 29) {
                    ContentResolver cr = getContentResolver();
                    ContentValues v = new ContentValues();
                    v.put(MediaStore.Downloads.DISPLAY_NAME, name);
                    v.put(MediaStore.Downloads.MIME_TYPE, type);
                    v.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/VibraSmash");
                    Uri uri = cr.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
                    if (uri == null) return "ERROR: could not create " + name;
                    try (OutputStream out = cr.openOutputStream(uri)) {
                        if (out == null) return "ERROR: could not open " + name;
                        out.write(data);
                    }
                    return "Download/VibraSmash/" + name;
                } else {
                    File dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
                    if (dir == null) return "ERROR: storage not available";
                    File f = new File(dir, name);
                    try (FileOutputStream out = new FileOutputStream(f)) { out.write(data); }
                    return f.getAbsolutePath();
                }
            } catch (Exception e) {
                return "ERROR: " + e.getMessage();
            }
        }
    }
}
