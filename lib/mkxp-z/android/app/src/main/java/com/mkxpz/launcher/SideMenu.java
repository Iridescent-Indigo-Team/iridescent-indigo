package com.mkxpz.launcher;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.view.animation.DecelerateInterpolator;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.RelativeLayout;
import android.widget.Switch;
import android.widget.TextView;

import com.mkxpz.R;

/**
 * A left-to-right slide-out menu drawn on top of the SDL surface.
 *
 * <p>The menu is kept as a set of sibling views added to the activity's
 * content {@link RelativeLayout}, so it does not require restructuring the
 * SDL bootstrap. When closed it only occupies a thin grab handle at the left
 * screen edge; the panel itself is translated off-screen and the scrim is
 * removed, letting touches pass through to the game below.</p>
 */
public class SideMenu
{
    public interface OnLoadArchiveListener
    {
        void onLoadArchive();
    }

    public interface OnImportSavesListener
    {
        void onImportSaves();
    }

    public interface OnExportSavesListener
    {
        void onExportSaves();
    }

    public interface OnFpsOverlayToggleListener
    {
        void onFpsOverlayToggle(boolean enabled);
    }

    private final Context mContext;
    private final ViewGroup mRoot;

    private View mScrim;
    private LinearLayout mPanel;
    private View mHandle;
    private TextView mGamePathView;
    private Switch mFpsToggle;

    private final int mPanelWidth;
    private final int mHandleWidth;
    private final int mTouchSlop;

    private OnLoadArchiveListener mOnLoadArchiveListener = () -> {};

    private OnImportSavesListener mOnImportSavesListener = () -> {};
    private OnExportSavesListener mOnExportSavesListener = () -> {};
    private OnFpsOverlayToggleListener mOnFpsOverlayToggleListener = enabled -> {};

    private boolean mOpen = false;
    private boolean mDidDrag = false;
    private float mDragStartRawX = 0f;
    private float mDragStartOffset = 0f;
    private float mOffset = 0f; // 0 == open, -panelWidth == closed

    private static final int HANDLE_REVEAL_DURATION_MS = 1500;
    private final Runnable mHideHandleRunnable = this::hideHandle;

    public SideMenu(Context context, ViewGroup root)
    {
        mContext = context;
        mRoot = root;

        float density = context.getResources().getDisplayMetrics().density;
        mPanelWidth = (int) (300f * density);
        mHandleWidth = (int) (14f * density);
        mTouchSlop = ViewConfiguration.get(context).getScaledTouchSlop();

        build();
        setOffset(-mPanelWidth);
    }

    public void setOnLoadArchiveListener(OnLoadArchiveListener listener)
    {
        mOnLoadArchiveListener = listener;
    }

    public void setOnImportSavesListener(OnImportSavesListener listener)
    {
        mOnImportSavesListener = listener;
    }

    public void setOnExportSavesListener(OnExportSavesListener listener)
    {
        mOnExportSavesListener = listener;
    }

    public void setOnFpsOverlayToggleListener(OnFpsOverlayToggleListener listener)
    {
        mOnFpsOverlayToggleListener = listener;
    }

    public void setFpsOverlayEnabled(boolean enabled)
    {
        if (mFpsToggle != null)
            mFpsToggle.setChecked(enabled);
    }

    public void setGamePath(String path)
    {
        if (mGamePathView != null)
            mGamePathView.setText("Game folder:\n" + path);
    }

    public boolean isOpen()
    {
        return mOpen;
    }

    private void build()
    {
        // Full-screen scrim that catches taps outside the panel while open.
        mScrim = new View(mContext);
        mScrim.setBackgroundColor(0x99000000);
        mScrim.setClickable(true);
        mScrim.setVisibility(View.GONE);
        mScrim.setOnClickListener(v -> close());
        mRoot.addView(mScrim, new RelativeLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        // The panel itself.
        mPanel = new LinearLayout(mContext);
        mPanel.setOrientation(LinearLayout.VERTICAL);
        mPanel.setBackgroundColor(Color.rgb(22, 22, 22));
        mPanel.setPadding(dp(20), dp(24), dp(20), dp(24));

        RelativeLayout.LayoutParams panelLp = new RelativeLayout.LayoutParams(
            mPanelWidth, ViewGroup.LayoutParams.MATCH_PARENT);
        panelLp.addRule(RelativeLayout.ALIGN_PARENT_START);
        mRoot.addView(mPanel, panelLp);

        TextView title = new TextView(mContext);
        title.setText(R.string.app_name);
        title.setTextColor(Color.WHITE);
        title.setTextSize(22f);
        title.setTypeface(null, Typeface.BOLD);
        mPanel.addView(title);

        mGamePathView = new TextView(mContext);
        mGamePathView.setTextColor(0xB0FFFFFF);
        mGamePathView.setTextSize(12f);
        mGamePathView.setPadding(0, dp(12), 0, 0);
        mPanel.addView(mGamePathView);

        Button loadArchive = new Button(mContext);
        loadArchive.setText(R.string.load_archive);
        loadArchive.setAllCaps(true);
        LinearLayout.LayoutParams loadLp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        loadLp.setMargins(0, dp(24), 0, 0);
        loadArchive.setLayoutParams(loadLp);
        loadArchive.setOnClickListener(v -> {
            close();
            mOnLoadArchiveListener.onLoadArchive();
        });
        mPanel.addView(loadArchive);

        Button importSaves = new Button(mContext);
        importSaves.setText(R.string.import_saves);
        importSaves.setAllCaps(true);
        LinearLayout.LayoutParams importLp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        importLp.setMargins(0, dp(12), 0, 0);
        importSaves.setLayoutParams(importLp);
        importSaves.setOnClickListener(v -> {
            close();
            mOnImportSavesListener.onImportSaves();
        });
        mPanel.addView(importSaves);

        Button exportSaves = new Button(mContext);
        exportSaves.setText(R.string.export_saves);
        exportSaves.setAllCaps(true);
        LinearLayout.LayoutParams exportLp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        exportLp.setMargins(0, dp(12), 0, 0);
        exportSaves.setLayoutParams(exportLp);
        exportSaves.setOnClickListener(v -> {
            close();
            mOnExportSavesListener.onExportSaves();
        });
        mPanel.addView(exportSaves);

        mFpsToggle = new Switch(mContext);
        mFpsToggle.setText(R.string.show_fps);
        mFpsToggle.setTextColor(Color.WHITE);
        LinearLayout.LayoutParams fpsLp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        fpsLp.setMargins(0, dp(24), 0, 0);
        mFpsToggle.setLayoutParams(fpsLp);
        mFpsToggle.setOnCheckedChangeListener((buttonView, isChecked) ->
            mOnFpsOverlayToggleListener.onFpsOverlayToggle(isChecked));
        mPanel.addView(mFpsToggle);

        // Grab handle: a thin strip at the left edge. Kept mostly transparent
        // and only revealed transiently so it doesn't intrude on the game.
        mHandle = new View(mContext);
        mHandle.setBackground(makeHandleDrawable());
        mHandle.setClickable(true);
        RelativeLayout.LayoutParams handleLp = new RelativeLayout.LayoutParams(
            mHandleWidth, dp(96));
        handleLp.addRule(RelativeLayout.ALIGN_PARENT_START);
        handleLp.addRule(RelativeLayout.CENTER_VERTICAL);
        mRoot.addView(mHandle, handleLp);
        mHandle.setOnTouchListener(this::onHandleTouch);
        mHandle.setVisibility(View.INVISIBLE);
        mHandle.setAlpha(0f);
    }

    private GradientDrawable makeHandleDrawable()
    {
        GradientDrawable d = new GradientDrawable();
        d.setColor(0x33202020);
        d.setCornerRadius(dp(7));
        return d;
    }

    /**
     * Briefly reveals the grab handle (a hint at the left edge), then fades it
     * out again after {@link #HANDLE_REVEAL_DURATION_MS}.
     */
    public void revealHandle()
    {
        if (mHandle == null)
            return;

        mHandle.removeCallbacks(mHideHandleRunnable);
        mHandle.animate().cancel();
        mHandle.setVisibility(View.VISIBLE);
        mHandle.setAlpha(1f);
        mHandle.postDelayed(mHideHandleRunnable, HANDLE_REVEAL_DURATION_MS);
    }

    private void hideHandle()
    {
        if (mHandle == null)
            return;

        mHandle.animate()
            .alpha(0f)
            .setDuration(300)
            .withEndAction(() -> mHandle.setVisibility(View.INVISIBLE))
            .start();
    }

    private boolean onHandleTouch(View v, MotionEvent ev)
    {
        switch (ev.getActionMasked())
        {
            case MotionEvent.ACTION_DOWN:
                mDidDrag = false;
                mPanel.animate().cancel();
                mDragStartRawX = ev.getRawX();
                mDragStartOffset = mOffset;
                mPanel.setVisibility(View.VISIBLE);
                mScrim.setVisibility(View.VISIBLE);
                return true;

            case MotionEvent.ACTION_MOVE:
            {
                float dx = ev.getRawX() - mDragStartRawX;
                if (!mDidDrag && Math.abs(dx) > mTouchSlop)
                    mDidDrag = true;

                if (mDidDrag)
                    setOffset(clamp(mDragStartOffset + dx, -mPanelWidth, 0f));
                return true;
            }

            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                if (!mDidDrag) {
                    // A plain tap toggles the menu.
                    toggle();
                } else if (mOffset > -mPanelWidth / 2f) {
                    open();
                } else {
                    close();
                }
                return true;
        }
        return false;
    }

    private float clamp(float value, float min, float max)
    {
        return Math.max(min, Math.min(max, value));
    }

    private void setOffset(float offset)
    {
        mOffset = offset;
        mPanel.setTranslationX(offset);
        mScrim.setAlpha(openFraction());
    }

    private float openFraction()
    {
        // 0 when fully closed, 1 when fully open.
        return 1f - (-mOffset / (float) mPanelWidth);
    }

    public void open()
    {
        mOpen = true;
        hideHandle();
        mPanel.setVisibility(View.VISIBLE);
        mScrim.setVisibility(View.VISIBLE);
        animateTo(0f);
    }

    public void close()
    {
        mOpen = false;
        animateTo(-mPanelWidth);
        // Briefly re-afford the handle after the menu slides away.
        revealHandle();
    }

    public void toggle()
    {
        if (mOpen)
            close();
        else
            open();
    }

    private void animateTo(float target)
    {
        mPanel.animate()
              .translationX(target)
              .setDuration(220)
              .setInterpolator(new DecelerateInterpolator())
              .setUpdateListener(animation -> {
                  mOffset = mPanel.getTranslationX();
                  mScrim.setAlpha(openFraction());
              })
              .withEndAction(() -> {
                  if (!mOpen)
                      mScrim.setVisibility(View.GONE);
              })
              .start();
    }

    private int dp(int value)
    {
        return (int) (value * mContext.getResources().getDisplayMetrics().density);
    }
}
