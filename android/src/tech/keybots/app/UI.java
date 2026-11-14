package tech.keybots.app;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.widget.TextView;

/** Colours and small view helpers shared by the app and the keyboard. */
final class UI {
    static final int BG = Color.parseColor("#0E0E10");
    static final int PANEL = Color.parseColor("#1C1C1F");
    static final int KEY = Color.parseColor("#2E2E32");
    static final int KEY_FN = Color.parseColor("#1F1F22");
    static final int TEXT = Color.parseColor("#F5F5F7");
    static final int MUTED = Color.parseColor("#8E8E93");
    static final int GREEN = Color.parseColor("#00EC97");
    static final int GREEN_INK = Color.parseColor("#04140D");
    static final int RED = Color.parseColor("#FF5A52");

    private UI() {}

    static int dp(Context c, float v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, c.getResources().getDisplayMetrics()));
    }

    static GradientDrawable round(Context c, int color, float radiusDp) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(dp(c, radiusDp));
        return d;
    }

    static GradientDrawable outline(Context c, int fill, int stroke, float radiusDp) {
        GradientDrawable d = round(c, fill, radiusDp);
        d.setStroke(dp(c, 1), stroke);
        return d;
    }

    static TextView text(Context c, String s, float sp, int color, boolean bold) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        t.setGravity(Gravity.CENTER);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        return t;
    }
}
