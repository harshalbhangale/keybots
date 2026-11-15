package tech.keybots.app;

import android.content.Context;
import android.inputmethodservice.InputMethodService;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * The Keybots keyboard for Android (preview). It types like a normal keyboard.
 * When the line you are typing reads like a command ("pay alex 0.4", "swap 1 near"),
 * the strip above the keys turns into a card; hold its button and the keyboard
 * sends it to your Keybots server: the agent asks the Spend Limits contract on NEAR,
 * which pays, refuses, or holds it for your Face ID in the Keybots app. Tap the
 * mascot key to see your bots and balance. Not connected yet: it checks the limits
 * on the phone only and says so.
 */
public class KeybotsIME extends InputMethodService {
    private static final String[] ROWS = {"qwertyuiop", "asdfghjkl", "zxcvbnm"};
    private static final String[] TABS = {"PAY", "TRADE", "FOLLOW", "CHECK"};
    private static final Pattern PAY = Pattern.compile("(?:^|\\s)(?:pay|send)\\s+([a-z0-9_.-]+)\\s+([0-9.]+)\\s*$", Pattern.CASE_INSENSITIVE);
    private static final Pattern SWAP = Pattern.compile("(?:^|\\s)(?:swap|buy|sell)\\s+([0-9.]+)(?:\\s+\\w+)*\\s*$", Pattern.CASE_INSENSITIVE);
    private static final Pattern SCAM = Pattern.compile("drain|unlock|urgent|seed phrase|private key", Pattern.CASE_INSENSITIVE);
    private static final long HOLD_MS = 900;

    private final Handler main = new Handler(Looper.getMainLooper());
    private boolean shift;
    private LinearLayout keys;
    private FrameLayout strip;
    private final TextView[] tabViews = new TextView[TABS.length];
    private String command; // what the card would do, or null

    @Override
    public View onCreateInputView() {
        Context c = this;
        LinearLayout root = new LinearLayout(c);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(UI.BG);
        int p = UI.dp(c, 6);
        root.setPadding(p, UI.dp(c, 8), p, UI.dp(c, 10));

        // Top row: the mascot key, then the four tabs.
        LinearLayout top = new LinearLayout(c);
        top.setOrientation(LinearLayout.HORIZONTAL);
        ImageView logo = new ImageView(c);
        logo.setImageResource(R.mipmap.ic_launcher);
        logo.setBackground(UI.round(c, UI.PANEL, 10));
        int lp = UI.dp(c, 4);
        logo.setPadding(lp, lp, lp, lp);
        logo.setOnClickListener(v -> status());
        top.addView(logo, new LinearLayout.LayoutParams(UI.dp(c, 44), UI.dp(c, 36)));
        LinearLayout tabs = new LinearLayout(c);
        tabs.setBackground(UI.round(c, UI.PANEL, 10));
        int tp = UI.dp(c, 3);
        tabs.setPadding(tp, tp, tp, tp);
        for (int i = 0; i < TABS.length; i++) {
            TextView t = UI.text(c, TABS[i], 10, UI.MUTED, true);
            t.setLetterSpacing(0.08f);
            tabViews[i] = t;
            final int idx = i;
            t.setOnClickListener(v -> setTab(idx));
            tabs.addView(t, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1));
        }
        LinearLayout.LayoutParams tl = new LinearLayout.LayoutParams(0, UI.dp(c, 36), 1);
        tl.leftMargin = UI.dp(c, 6);
        top.addView(tabs, tl);
        root.addView(top);

        // The strip: suggestions, or the command card.
        strip = new FrameLayout(c);
        LinearLayout.LayoutParams sl = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, UI.dp(c, 40));
        sl.topMargin = UI.dp(c, 8);
        sl.bottomMargin = UI.dp(c, 8);
        root.addView(strip, sl);

        keys = new LinearLayout(c);
        keys.setOrientation(LinearLayout.VERTICAL);
        root.addView(keys);
        buildKeys();
        refresh();
        return root;
    }

    @Override
    public void onStartInputView(EditorInfo info, boolean restarting) {
        super.onStartInputView(info, restarting);
        refresh();
    }

    /** Text that arrives another way (paste, autofill) is read too. */
    @Override
    public void onUpdateSelection(int oldStart, int oldEnd, int newStart, int newEnd, int candStart, int candEnd) {
        super.onUpdateSelection(oldStart, oldEnd, newStart, newEnd, candStart, candEnd);
        if (strip != null && strip.getChildCount() > 0 && !(strip.getChildAt(0) instanceof TextView)) refresh();
        else if (strip != null && strip.getChildCount() == 0) refresh();
        else if (strip != null && command == null) refresh();
    }

    private void buildKeys() {
        Context c = this;
        keys.removeAllViews();
        LinearLayout nums = row();
        ((LinearLayout.LayoutParams) nums.getLayoutParams()).height = UI.dp(c, 38);
        for (char ch : "1234567890.".toCharArray()) {
            final String s = String.valueOf(ch);
            addKey(nums, s, 1f, UI.KEY_FN, UI.TEXT, v -> type(s));
        }
        keys.addView(nums);
        for (int r = 0; r < ROWS.length; r++) {
            LinearLayout row = row();
            if (r == 1) row.setPadding(UI.dp(c, 16), 0, UI.dp(c, 16), 0);
            if (r == 2) addKey(row, "⇧", 1.4f, UI.KEY_FN, UI.TEXT, v -> { shift = !shift; buildKeys(); });
            for (char ch : ROWS[r].toCharArray()) {
                final String s = shift ? String.valueOf(ch).toUpperCase(Locale.US) : String.valueOf(ch);
                addKey(row, s, 1f, UI.KEY, UI.TEXT, v -> type(s));
            }
            if (r == 2) addKey(row, "⌫", 1.4f, UI.KEY_FN, UI.TEXT, v -> backspace());
            keys.addView(row);
        }
        LinearLayout last = row();
        addKey(last, "N", 1.5f, UI.PANEL, UI.GREEN, v -> type("near"));
        addKey(last, "keybots", 5.6f, UI.KEY, UI.MUTED, v -> type(" "));
        addKey(last, "return", 2.2f, UI.GREEN, UI.GREEN_INK, v -> enter());
        keys.addView(last);
    }

    private LinearLayout row() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, UI.dp(this, 46));
        lp.bottomMargin = UI.dp(this, 8);
        row.setLayoutParams(lp);
        return row;
    }

    private void addKey(LinearLayout row, String label, float weight, int bg, int fg, View.OnClickListener on) {
        TextView k = UI.text(this, label, label.length() > 1 && !label.equals("⇧") && !label.equals("⌫") ? 13 : 20, fg, label.length() > 1);
        if (label.equals("keybots")) k.setLetterSpacing(0.3f);
        k.setBackground(UI.round(this, bg, 8));
        k.setOnClickListener(on);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, weight);
        int m = UI.dp(this, 3);
        lp.leftMargin = m;
        lp.rightMargin = m;
        row.addView(k, lp);
    }

    private void type(String s) {
        InputConnection ic = getCurrentInputConnection();
        if (ic == null) return;
        ic.commitText(s, 1);
        if (shift && s.length() == 1) {
            shift = false;
            buildKeys();
        }
        refresh();
    }

    private void backspace() {
        InputConnection ic = getCurrentInputConnection();
        if (ic == null) return;
        CharSequence sel = ic.getSelectedText(0);
        if (sel != null && sel.length() > 0) ic.commitText("", 1);
        else ic.deleteSurroundingText(1, 0);
        refresh();
    }

    private void enter() {
        InputConnection ic = getCurrentInputConnection();
        if (ic == null) return;
        EditorInfo ei = getCurrentInputEditorInfo();
        int action = ei == null ? EditorInfo.IME_ACTION_NONE : ei.imeOptions & EditorInfo.IME_MASK_ACTION;
        if (action != EditorInfo.IME_ACTION_NONE && action != EditorInfo.IME_ACTION_UNSPECIFIED) ic.performEditorAction(action);
        else ic.commitText("\n", 1);
        refresh();
    }

    private void setTab(int idx) {
        String[] starters = {"pay ", "swap ", "follow @", "$near"};
        type(starters[idx]);
    }

    /** Reads the current line and shows either word suggestions or the command card. */
    private void refresh() {
        if (strip == null) return;
        InputConnection ic = getCurrentInputConnection();
        CharSequence before = ic == null ? "" : ic.getTextBeforeCursor(80, 0);
        String line = before == null ? "" : before.toString();
        int nl = line.lastIndexOf('\n');
        if (nl >= 0) line = line.substring(nl + 1);

        int active = -1;
        String title = null;
        Matcher m;
        if (SCAM.matcher(line).find()) {
            active = 3;
            title = "Looks like a scam · check it";
            command = "scam";
        } else if ((m = PAY.matcher(line)).find()) {
            active = 0;
            String to = m.group(1).contains(".") ? m.group(1) : m.group(1) + ".near";
            title = "Pay " + to + " " + m.group(2) + " NEAR";
            command = "pay:" + m.group(2) + ":" + to;
        } else if ((m = SWAP.matcher(line)).find()) {
            active = 1;
            title = "Swap " + m.group(1) + " on Rhea";
            command = "swap:" + m.group(1);
        } else {
            command = null;
        }
        for (int i = 0; i < tabViews.length; i++) {
            boolean on = i == active;
            tabViews[i].setTextColor(on ? UI.GREEN_INK : UI.MUTED);
            tabViews[i].setBackground(on ? UI.round(this, UI.GREEN, 7) : null);
        }
        strip.removeAllViews();
        strip.addView(command == null ? words() : card(title), new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
    }

    private View words() {
        LinearLayout w = new LinearLayout(this);
        for (String s : new String[] {"I", "the", "on"}) {
            TextView t = UI.text(this, s, 16, UI.TEXT, false);
            w.addView(t, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1));
        }
        return w;
    }

    /** The command card: its title and a button you hold to check it. */
    private View card(String title) {
        Context c = this;
        LinearLayout card = new LinearLayout(c);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setBackground(UI.outline(c, 0x1A00EC97, 0x6600EC97, 12));
        card.setPadding(UI.dp(c, 12), 0, UI.dp(c, 4), 0);
        TextView t = UI.text(c, title, 14, UI.TEXT, true);
        t.setGravity(Gravity.CENTER_VERTICAL);
        t.setSingleLine(true);
        card.addView(t, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1));
        TextView hold = UI.text(c, "HOLD", 11, UI.GREEN_INK, true);
        hold.setBackground(UI.round(c, UI.GREEN, 9));
        hold.setPadding(UI.dp(c, 14), 0, UI.dp(c, 14), 0);
        final String line = currentLine();
        final Runnable done = () -> send(title, line);
        hold.setOnTouchListener((v, e) -> {
            if (e.getAction() == MotionEvent.ACTION_DOWN) {
                v.setAlpha(0.7f);
                main.postDelayed(done, HOLD_MS);
            } else if (e.getAction() == MotionEvent.ACTION_UP || e.getAction() == MotionEvent.ACTION_CANCEL) {
                v.setAlpha(1f);
                main.removeCallbacks(done);
            }
            return true;
        });
        LinearLayout.LayoutParams hl = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, UI.dp(c, 32));
        card.addView(hold, hl);
        return card;
    }

    private String currentLine() {
        InputConnection ic = getCurrentInputConnection();
        CharSequence before = ic == null ? "" : ic.getTextBeforeCursor(200, 0);
        String line = before == null ? "" : before.toString();
        int nl = line.lastIndexOf('\n');
        return (nl >= 0 ? line.substring(nl + 1) : line).trim();
    }

    /** One line on the strip, for a few seconds. */
    private void say(String msg, int color, long ms) {
        strip.removeAllViews();
        TextView t = UI.text(this, msg, 13, color, true);
        t.setSingleLine(false);
        t.setMaxLines(2);
        t.setPadding(UI.dp(this, 10), 0, UI.dp(this, 10), 0);
        t.setBackground(UI.outline(this, 0x14FFFFFF, color, 12));
        strip.addView(t, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        main.removeCallbacksAndMessages(null);
        if (ms > 0) main.postDelayed(this::refresh, ms);
    }

    /** The mascot key: your bots and what Spend Limits holds, from the server. */
    private void status() {
        if (!Keybots.connected(this)) { say("Open the Keybots app and paste your key to connect.", UI.MUTED, 3500); return; }
        say("Checking your bots…", UI.MUTED, 0);
        new Thread(() -> {
            String msg; int color;
            try { msg = Keybots.network(this).toUpperCase(Locale.US) + " · " + Keybots.summary(Keybots.state(this)); color = UI.GREEN; }
            catch (Exception e) { msg = e.getMessage(); color = UI.RED; }
            final String m = msg; final int col = color;
            main.post(() -> say(m, col, 4500));
        }).start();
    }

    /** Hold: the command goes to Keybots, and Spend Limits on NEAR decides. */
    private void send(String title, String line) {
        if (command == null) return;
        if (!Keybots.connected(this)) { result(title); return; }
        final String source = command.equals("scam") ? "pasted" : "typed";
        say(source.equals("pasted") ? "Checking this message…" : (command.startsWith("swap") ? "Swapping…" : "Paying…"), UI.MUTED, 0);
        new Thread(() -> {
            String msg; int color;
            try {
                org.json.JSONObject r = Keybots.command(this, line, source);
                String outcome = r.optString("outcome");
                String what = r.optString("summary", r.optString("message", outcome));
                if (what.isEmpty()) what = r.optString("message", outcome);
                org.json.JSONObject tx = r.optJSONObject("tx");
                if (tx != null && !tx.optString("hash").isEmpty()) what += " · tx " + tx.optString("hash").substring(0, 8) + "…";
                msg = what;
                color = outcome.equals("paid") || outcome.equals("swapped") ? UI.GREEN
                        : outcome.equals("approval") ? 0xFFF5B841 : outcome.equals("blocked") ? UI.RED : UI.MUTED;
            } catch (Exception e) { msg = e.getMessage(); color = UI.RED; }
            final String m = msg; final int col = color;
            main.post(() -> {
                if (col == UI.GREEN || col == 0xFFF5B841) clearLine(line);
                say(m, col, 6000);
            });
        }).start();
    }

    /** A command that ran is taken out of the message, as on iOS. */
    private void clearLine(String line) {
        InputConnection ic = getCurrentInputConnection();
        if (ic == null || line.isEmpty()) return;
        CharSequence before = ic.getTextBeforeCursor(line.length() + 2, 0);
        if (before != null && before.toString().trim().endsWith(line)) ic.deleteSurroundingText(before.toString().length() - before.toString().lastIndexOf(line), 0);
    }

    /** Not connected: checks the limits on the phone and says what would happen. */
    private void result(String title) {
        String msg;
        int color;
        if (command == null) return;
        if (command.equals("scam")) {
            msg = "Blocked: looks like a scam. Nothing sent.";
            color = UI.RED;
        } else if (command.startsWith("pay:")) {
            String[] parts = command.split(":");
            double n = parse(parts[1]);
            if (n > 0.5) {
                msg = n + " NEAR is over your 0.5 limit. Blocked.";
                color = UI.RED;
            } else {
                msg = "Inside your limits. Connect Keybots in the app to send it.";
                color = UI.GREEN;
            }
        } else {
            double n = parse(command.substring(5));
            if (n > 1) {
                msg = "Over your 1 NEAR trade cap. Blocked.";
                color = UI.RED;
            } else {
                msg = "Inside your trade cap. Connect Keybots in the app to send it.";
                color = UI.GREEN;
            }
        }
        strip.removeAllViews();
        TextView t = UI.text(this, msg, 13, color, true);
        t.setBackground(UI.outline(this, 0x14FFFFFF, color, 12));
        strip.addView(t, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        main.postDelayed(this::refresh, 3200);
    }

    private static double parse(String s) {
        try {
            return Double.parseDouble(s);
        } catch (NumberFormatException e) {
            return 0;
        }
    }
}
