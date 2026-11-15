package tech.keybots.app;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.math.BigDecimal;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/**
 * The Keybots server, as the Android keyboard and app see it: the same API the
 * iOS keyboard uses. The key is pasted once in the app and kept on this phone;
 * nothing is built into the APK. Spend Limits on NEAR decides every payment.
 */
final class Keybots {
    static final String TESTNET = "https://13-126-207-245.sslip.io";

    private Keybots() {}

    private static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences("keybots", Context.MODE_PRIVATE);
    }

    static String server(Context c) {
        String base = prefs(c).getString("server", TESTNET);
        if (!"mainnet".equals(network(c))) return base;
        // Mainnet runs beside testnet: "https://host" -> "https://mainnet-host".
        int i = base.indexOf("://");
        return i < 0 ? base : base.substring(0, i + 3) + "mainnet-" + base.substring(i + 3);
    }

    static String key(Context c) { return prefs(c).getString("key", ""); }
    static String network(Context c) { return prefs(c).getString("network", "testnet"); }
    static boolean connected(Context c) { return !key(c).isEmpty(); }

    static void save(Context c, String server, String key, String network) {
        prefs(c).edit().putString("server", server.trim().replaceAll("/+$", ""))
                .putString("key", key.trim()).putString("network", network).apply();
    }

    /** One command, as typed ("typed") or copied from someone else ("pasted"). */
    static JSONObject command(Context c, String text, String source) throws Exception {
        JSONObject body = new JSONObject().put("text", text).put("source", source);
        return call(c, "POST", "/v1/command", body);
    }

    static JSONObject state(Context c) throws Exception {
        return call(c, "GET", "/v1/state", null);
    }

    /** "3 bots · 0.64 NEAR · 2 waiting", from /v1/state. */
    static String summary(JSONObject s) {
        int bots = s.optJSONArray("agents") == null ? 0 : s.optJSONArray("agents").length();
        JSONArray pending = s.optJSONArray("pending");
        int waiting = pending == null ? 0 : pending.length();
        String near = near(s.optString("available", "0"));
        String line = (s.optBoolean("paused") ? "All bots stopped" : bots + " bots running") + " · " + near + " NEAR";
        return waiting > 0 ? line + " · " + waiting + " waiting for you" : line;
    }

    /** yoctoNEAR -> "0.6443". */
    static String near(String yocto) {
        try {
            return new BigDecimal(yocto).movePointLeft(24).setScale(4, BigDecimal.ROUND_DOWN).stripTrailingZeros().toPlainString();
        } catch (Exception e) {
            return "0";
        }
    }

    private static JSONObject call(Context c, String method, String path, JSONObject body) throws Exception {
        HttpURLConnection h = (HttpURLConnection) new URL(server(c) + path).openConnection();
        h.setConnectTimeout(10000);
        h.setReadTimeout(60000);
        h.setRequestMethod(method);
        h.setRequestProperty("authorization", "Bearer " + key(c));
        h.setRequestProperty("x-airkey-client", "android");
        if (body != null) {
            h.setDoOutput(true);
            h.setRequestProperty("content-type", "application/json");
            try (OutputStream o = h.getOutputStream()) { o.write(body.toString().getBytes(StandardCharsets.UTF_8)); }
        }
        int code = h.getResponseCode();
        InputStream in = code < 400 ? h.getInputStream() : h.getErrorStream();
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        if (in != null) {
            byte[] b = new byte[8192];
            for (int n; (n = in.read(b)) > 0; ) buf.write(b, 0, n);
            in.close();
        }
        String text = buf.toString("UTF-8");
        JSONObject j = text.startsWith("{") ? new JSONObject(text) : new JSONObject();
        if (code == 401) throw new Exception("Keybots didn't accept the key. Check it in the app.");
        if (code >= 400) throw new Exception(j.optString("error", "Keybots answered " + code));
        return j;
    }
}
