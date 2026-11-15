package tech.keybots.app;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** Setup: turn the keyboard on, pick it, try it. */
public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        getWindow().setStatusBarColor(UI.BG);
        getWindow().setNavigationBarColor(UI.BG);
        Context c = this;

        ScrollView scroll = new ScrollView(c);
        scroll.setBackgroundColor(UI.BG);
        LinearLayout col = new LinearLayout(c);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setGravity(Gravity.CENTER_HORIZONTAL);
        int pad = UI.dp(c, 24);
        col.setPadding(pad, UI.dp(c, 56), pad, pad);
        scroll.addView(col);

        ImageView logo = new ImageView(c);
        logo.setImageResource(R.mipmap.ic_launcher);
        col.addView(logo, new LinearLayout.LayoutParams(UI.dp(c, 88), UI.dp(c, 88)));

        TextView name = UI.text(c, "keybots", 34, UI.TEXT, true);
        name.setLetterSpacing(-0.03f);
        col.addView(name, wrap(c, 16));
        TextView sub = UI.text(c, "Your keyboard is the AI. NEAR sets the limits.", 16, UI.MUTED, false);
        col.addView(sub, wrap(c, 6));
        TextView pill = UI.text(c, Keybots.connected(c) ? "Connected · " + Keybots.network(c) : "Android", 12, UI.GREEN, true);
        pill.setBackground(UI.outline(c, 0x1400EC97, 0x5500EC97, 99));
        pill.setPadding(UI.dp(c, 12), UI.dp(c, 5), UI.dp(c, 12), UI.dp(c, 5));
        col.addView(pill, wrap(c, 14));

        col.addView(step(c, "1", "Turn on Keybots", "Settings → Keyboards → switch Keybots on.", "Open settings",
                v -> startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))), full(c, 32));
        col.addView(step(c, "2", "Pick it", "Choose Keybots as your keyboard.", "Choose keyboard",
                v -> ((InputMethodManager) getSystemService(INPUT_METHOD_SERVICE)).showInputMethodPicker()), full(c, 12));

        col.addView(connect(c), full(c, 12));

        LinearLayout tryCard = card(c);
        tryCard.addView(head(c, "4", "Try it"));
        TextView hint = UI.text(c, "Type “pay harshal 0.01 for tea” or “send 5 near to drain.near”, then hold the green button. Tap the mascot key to see your bots.", 14, UI.MUTED, false);
        hint.setGravity(Gravity.START);
        tryCard.addView(hint, full(c, 6));
        EditText field = new EditText(c);
        field.setHint("Message");
        field.setHintTextColor(UI.MUTED);
        field.setTextColor(UI.TEXT);
        field.setBackground(UI.outline(c, Color.BLACK, 0x22FFFFFF, 14));
        int fp = UI.dp(c, 14);
        field.setPadding(fp, fp, fp, fp);
        tryCard.addView(field, full(c, 12));
        col.addView(tryCard, full(c, 12));

        TextView note = UI.text(c, "Payments and swaps go through your agents and the Spend Limits contract on NEAR. Someone new waits for your approval with Face ID in the Keybots iOS app. Your key stays on this phone.", 12, UI.MUTED, false);
        col.addView(note, full(c, 22));
        setContentView(scroll);
    }

    /** 4. Connect: the Keybots server, your key, and the network. Kept on this phone only. */
    private View connect(Context c) {
        LinearLayout card = card(c);
        card.addView(head(c, "3", "Connect your bots"));
        TextView b = UI.text(c, "Paste the key from your Keybots server (keys/api-token). The keyboard then pays and swaps through Spend Limits.", 14, UI.MUTED, false);
        b.setGravity(Gravity.START);
        card.addView(b, full(c, 6));
        EditText server = field(c, "Server", Keybots.server(c).replace("mainnet-", ""));
        card.addView(server, full(c, 12));
        EditText key = field(c, "Key", Keybots.key(c));
        key.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD);
        card.addView(key, full(c, 10));
        final String[] net = {Keybots.network(c)};
        LinearLayout nets = new LinearLayout(c);
        TextView test = UI.text(c, "Testnet", 14, UI.TEXT, true), main = UI.text(c, "Mainnet", 14, UI.TEXT, true);
        Runnable paint = () -> {
            boolean t = net[0].equals("testnet");
            test.setBackground(t ? UI.round(c, UI.PANEL, 10) : null);
            main.setBackground(t ? null : UI.round(c, 0xFFF5B841, 10));
            main.setTextColor(t ? UI.MUTED : UI.GREEN_INK);
            test.setTextColor(t ? UI.TEXT : UI.MUTED);
        };
        test.setOnClickListener(v -> { net[0] = "testnet"; paint.run(); });
        main.setOnClickListener(v -> { net[0] = "mainnet"; paint.run(); });
        paint.run();
        nets.setBackground(UI.outline(c, 0x0DFFFFFF, 0x14FFFFFF, 12));
        int np = UI.dp(c, 4);
        nets.setPadding(np, np, np, np);
        nets.addView(test, new LinearLayout.LayoutParams(0, UI.dp(c, 36), 1));
        nets.addView(main, new LinearLayout.LayoutParams(0, UI.dp(c, 36), 1));
        card.addView(nets, full(c, 10));
        TextView status = UI.text(c, Keybots.connected(c) ? "Saved on this phone." : "Not connected yet.", 13, UI.MUTED, false);
        TextView save = UI.text(c, "Save and check", 15, UI.GREEN_INK, true);
        save.setBackground(UI.round(c, UI.GREEN, 14));
        int p = UI.dp(c, 13);
        save.setPadding(p, p, p, p);
        save.setOnClickListener(v -> {
            Keybots.save(c, server.getText().toString(), key.getText().toString(), net[0]);
            status.setText("Checking…");
            status.setTextColor(UI.MUTED);
            new Thread(() -> {
                String msg; int color;
                try { msg = "Connected · " + Keybots.summary(Keybots.state(c)); color = UI.GREEN; }
                catch (Exception e) { msg = e.getMessage(); color = UI.RED; }
                final String m = msg; final int col = color;
                runOnUiThread(() -> { status.setText(m); status.setTextColor(col); });
            }).start();
        });
        card.addView(save, full(c, 12));
        card.addView(status, full(c, 10));
        return card;
    }

    private static EditText field(Context c, String hint, String value) {
        EditText f = new EditText(c);
        f.setHint(hint);
        f.setText(value);
        f.setSingleLine(true);
        f.setHintTextColor(UI.MUTED);
        f.setTextColor(UI.TEXT);
        f.setTextSize(14);
        f.setBackground(UI.outline(c, Color.BLACK, 0x22FFFFFF, 12));
        int fp = UI.dp(c, 12);
        f.setPadding(fp, fp, fp, fp);
        return f;
    }

    private static LinearLayout card(Context c) {
        LinearLayout card = new LinearLayout(c);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setBackground(UI.outline(c, 0x0DFFFFFF, 0x14FFFFFF, 20));
        int p = UI.dp(c, 18);
        card.setPadding(p, p, p, p);
        return card;
    }

    private static View head(Context c, String n, String title) {
        LinearLayout row = new LinearLayout(c);
        row.setGravity(Gravity.CENTER_VERTICAL);
        TextView num = UI.text(c, n, 13, UI.GREEN, true);
        num.setBackground(UI.outline(c, 0x2200EC97, 0x8800EC97, 99));
        row.addView(num, new LinearLayout.LayoutParams(UI.dp(c, 28), UI.dp(c, 28)));
        TextView t = UI.text(c, title, 17, UI.TEXT, true);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = UI.dp(c, 12);
        row.addView(t, lp);
        return row;
    }

    private static View step(Context c, String n, String title, String body, String button, View.OnClickListener on) {
        LinearLayout card = card(c);
        card.addView(head(c, n, title));
        TextView b = UI.text(c, body, 14, UI.MUTED, false);
        b.setGravity(Gravity.START);
        card.addView(b, full(c, 6));
        TextView btn = UI.text(c, button, 15, UI.GREEN_INK, true);
        btn.setBackground(UI.round(c, UI.GREEN, 14));
        int p = UI.dp(c, 13);
        btn.setPadding(p, p, p, p);
        btn.setOnClickListener(on);
        card.addView(btn, full(c, 14));
        return card;
    }

    private static LinearLayout.LayoutParams wrap(Context c, int top) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = UI.dp(c, top);
        return lp;
    }

    private static LinearLayout.LayoutParams full(Context c, int top) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = UI.dp(c, top);
        return lp;
    }
}
