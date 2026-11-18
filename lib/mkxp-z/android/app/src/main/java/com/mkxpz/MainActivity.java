package com.mkxpz;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.app.ProgressDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.view.View;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.ViewGroup.LayoutParams;
import android.widget.TextView;
import android.widget.LinearLayout;
import android.widget.Toast;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Vibrator;
import android.os.VibrationEffect;
import android.os.storage.StorageManager;
import android.os.storage.OnObbStateChangeListener;
import android.net.Uri;
import android.util.Log;
import android.util.TypedValue;
import java.util.Locale;
import java.util.ArrayList;
import java.util.List;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.libsdl.app.SDLActivity;
import com.mkxpz.gamepad.Gamepad;
import com.mkxpz.gamepad.GamepadConfig;
import com.mkxpz.launcher.SideMenu;
import com.mkxpz.launcher.ArchiveExtractor;
import com.mkxpz.launcher.SaveTransfer;

public class MainActivity extends SDLActivity
{
    // This activity inherits from SDLActivity activity.
    // Put your Java-side stuff here.

    private static final String TAG = "mkxp-z[Activity]";
    // Game files live in the app's own external files directory (e.g.
    // /storage/emulated/0/Android/data/com.mkxpz/files/mkxp-z), which needs no
    // storage permissions and is cleaned up on uninstall. Shared external
    // storage is deliberately not used for game assets.
    private static String GAME_PATH_DEFAULT;
    private static String GAME_PATH;
    private static String OBB_MAIN_FILENAME;
    private static boolean DEBUG = false;

    private static final String PREFS_NAME = "mkxpz_prefs";
    private static final String PREFS_GAME_PATH = "game_path";
    private static final String PREFS_FPS_OVERLAY = "fps_overlay_enabled";
    private static final int REQUEST_LOAD_ARCHIVE = 200;
    private static final int REQUEST_IMPORT_SAVES = 201;
    private static final int REQUEST_EXPORT_SAVES = 202;

    protected boolean mStarted = false;

    protected static Handler mMainHandler;
    protected static StorageManager mStorageManager;
    protected static Vibrator mVibrator;

    protected static TextView tvFps;

    // FPS overlay toggle, read from native code (eventthread.cpp) to decide
    // whether to stream FPS updates into the Java overlay. Set on the UI
    // thread when the user flips the menu switch; read on the native thread.
    // Marked volatile for cross-thread visibility.
    protected static volatile boolean fpsOverlayEnabled = false;

    // In-screen gamepad
    private final Gamepad mGamepad = new Gamepad();
    private boolean mGamepadInvisible = false;

    // Slide-out launcher menu
    private SideMenu mSideMenu;
    private boolean mEdgeTracking = false;
    private float mEdgeStartRawX = 0f;

    private void runSDLThread()
    {
        if (!mStarted) {
            Log.i(TAG, "Game path: " + GAME_PATH);
        }

        mStarted = true;

        // Run (resume) native SDL thread
        if (mHasMultiWindow) {
            resumeNativeThread();
        }
    }

    OnObbStateChangeListener obbListener = new OnObbStateChangeListener()
    {
        @Override
        public void onObbStateChange(String path, int state)
        {
            super.onObbStateChange(path, state);

            Log.v(TAG, "OBB state of " + path + " changed to " + state);

            switch (state)
            {
                case OnObbStateChangeListener.MOUNTED:
                    String obbPath = mStorageManager.getMountedObbPath(path);
                    Log.v(TAG, "OBB " + path + " is mounted to " + obbPath);
                    GAME_PATH = obbPath;
                    break;

                case OnObbStateChangeListener.UNMOUNTED:
                    Log.v(TAG, "OBB " + path + " is unmounted");
                    GAME_PATH = GAME_PATH_DEFAULT;
                    break;

                default:
                    Log.e(TAG, "Failed to mount OBB " + path + ": Got state " + state);
                    break;
            }

            runSDLThread();
        }
    };

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data)
    {
        if (requestCode == REQUEST_LOAD_ARCHIVE) {
            if (resultCode == RESULT_OK && data != null && data.getData() != null) {
                loadGameArchive(data.getData());
            }
        } else if (requestCode == REQUEST_IMPORT_SAVES) {
            if (resultCode == RESULT_OK && data != null) {
                importSaves(data);
            }
        } else if (requestCode == REQUEST_EXPORT_SAVES) {
            if (resultCode == RESULT_OK && data != null && data.getData() != null) {
                exportSaves(data.getData());
            }
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState)
    {
        super.onCreate(savedInstanceState);

        // If SDL failed to initialize (for example a native library could not
        // be loaded), the SDL bootstrap already shows its own error dialog and
        // leaves the SDL context/surface unset. Don't build the overlay UI on
        // top of that, or we'd crash dereferencing a null context.
        if (mBrokenLibraries) {
            return;
        }

        // Game files live in the app's own external files directory.
        File gameRootBase = getExternalFilesDir(null);
        if (gameRootBase == null)
            gameRootBase = getFilesDir();
        GAME_PATH_DEFAULT = new File(gameRootBase, "mkxp-z").getAbsolutePath();
        GAME_PATH = GAME_PATH_DEFAULT;

        mMainHandler = new Handler(getMainLooper());

        mStorageManager = (StorageManager) getSystemService(STORAGE_SERVICE);
        mVibrator = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);

        // Get main OBB filepath
        final String obbPrefix = "main"; // "main", "patch"
        final int obbVersion = 1;
        OBB_MAIN_FILENAME = getObbDir() + "/" + obbPrefix + "." + obbVersion + "." + getPackageName() + ".obb";

        // Get Debug flag
        try {
            ActivityInfo actInfo = getPackageManager().getActivityInfo(this.getComponentName(), PackageManager.GET_META_DATA);
            DEBUG = actInfo.metaData.getBoolean("mkxp_debug");
        } catch (PackageManager.NameNotFoundException e) {
            Log.w(TAG, "Failed to set debug flag: " + e);
            e.printStackTrace();
        }

        // Setup in-screen gamepad
        mGamepadInvisible = (isAndroidTV() || isChromebook());
        GamepadConfig gpadConfig = new GamepadConfig();
        mGamepad.init(gpadConfig, mGamepadInvisible);
        mGamepad.setOnKeyDownListener(SDLActivity::onNativeKeyDown);
        mGamepad.setOnKeyUpListener(SDLActivity::onNativeKeyUp);

        if (mLayout != null) {
            mGamepad.attachTo(this, mLayout);
        }

        // Setup FPS textview (a high-visibility overlay in the top-left corner).
        tvFps = new TextView(this);
        tvFps.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        tvFps.setTextColor(Color.WHITE);
        tvFps.setTypeface(Typeface.DEFAULT_BOLD);
        tvFps.setShadowLayer(2f, 0f, 1f, Color.BLACK);

        GradientDrawable fpsBg = new GradientDrawable();
        fpsBg.setColor(0xCC000000);
        fpsBg.setCornerRadius(dpPx(6));
        tvFps.setBackground(fpsBg);
        tvFps.setPadding(dpPx(10), dpPx(4), dpPx(10), dpPx(4));
        tvFps.setVisibility(View.GONE);

        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT);
        params.setMargins(16, 16, 0, 0);
        tvFps.setLayoutParams(params);

        mLayout.addView(tvFps);

        // Restore a previously loaded game path (survives process restarts).
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        String savedGamePath = prefs.getString(PREFS_GAME_PATH, null);
        if (savedGamePath != null && new File(savedGamePath).isDirectory()) {
            GAME_PATH = savedGamePath;
        }

        // Restore the FPS overlay toggle.
        fpsOverlayEnabled = prefs.getBoolean(PREFS_FPS_OVERLAY, false);

        // Setup the slide-out game launcher menu (on top of the SDL surface).
        mSideMenu = new SideMenu(this, mLayout);
        mSideMenu.setGamePath(GAME_PATH);
        mSideMenu.setFpsOverlayEnabled(fpsOverlayEnabled);
        mSideMenu.setOnFpsOverlayToggleListener(this::setFpsOverlayEnabled);
        mSideMenu.setOnLoadArchiveListener(this::pickGameArchive);
        mSideMenu.setOnImportSavesListener(this::pickImportSaves);
        mSideMenu.setOnExportSavesListener(this::pickExportSaves);

        // Briefly hint at the grab handle on first launch.
        mSideMenu.revealHandle();
    }

    @Override
    protected void onStart()
    {
        super.onStart();

        if (!mStarted) {
            // Check for main OBB file
            if (new File(OBB_MAIN_FILENAME).exists()) {
                Log.v(TAG, "Main OBB file found, starting with main OBB mount");

                // Try to mount main OBB file
                mStorageManager.mountObb(OBB_MAIN_FILENAME, null, obbListener);
            } else if (hasGame(new File(GAME_PATH))) {
                Log.v(TAG, "Game found in " + GAME_PATH + ", starting");

                // Run from the game directory
                runSDLThread();
            } else {
                Log.v(TAG, "No game found in " + GAME_PATH + ", showing launcher menu");

                // No game yet: let the user load one through the slide-out menu.
                mSideMenu.open();
            }
        } else {
            // onStart: Resume SDL thread
            runSDLThread();
        }
    }

    @Override
    protected void onDestroy()
    {
        super.onDestroy();

        // HACK: Exiting the JVM (process) since Ruby does not like when we
        // try to re-initialize the Ruby VM in mkxp-z (JNI native library)
        // that leads to segmentation fault, even after cleaning up the VM.
        System.exit(0);
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent evt)
    {
        if (
            evt.getKeyCode() != KeyEvent.KEYCODE_BACK &&
            evt.getKeyCode() != KeyEvent.KEYCODE_VOLUME_UP &&
            evt.getKeyCode() != KeyEvent.KEYCODE_VOLUME_DOWN &&
            evt.getKeyCode() != KeyEvent.KEYCODE_VOLUME_MUTE &&
            evt.getKeyCode() != KeyEvent.KEYCODE_HEADSETHOOK
        ) {
            // Hide gamepad view on key events when visible
            if (!mGamepadInvisible) {
                mGamepad.hideView();
                mGamepadInvisible = true;
            }
        }

        if (mGamepad.processGamepadEvent(evt))
            return true;

        return super.dispatchKeyEvent(evt);
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent evt)
    {
        // Slide-out menu: a swipe right from the left screen edge opens it.
        handleEdgeSwipe(evt);

        // Show gamepad view on touch when hidden (but not while the menu is open).
        if ((mSideMenu == null || !mSideMenu.isOpen()) && mGamepadInvisible) {
            mGamepad.showView();
            mGamepadInvisible = false;
        }

        return super.dispatchTouchEvent(evt);
    }

    @Override
    public boolean onGenericMotionEvent(MotionEvent evt)
    {
        if (mGamepad.processDPadEvent(evt))
            return true;

        return super.onGenericMotionEvent(evt);
    }

    /**
     * This method is for arguments for launching native mkxp-z.
     *
     * @return arguments for the mkxp-z
     */
    @Override
    protected String[] getArguments()
    {
        String[] args;

        if (DEBUG) {
            // Arguments in Debug mode
            args = new String[] { "debug" };
        } else {
            // Arguments in normal mode
            args = new String[] {};
        }

        return args;
    }

    /**
     * This static method is used in native mkxp-z. (see eventthread.cpp)
     * This method updates text with given FPS count to FPS TextView in Activity.
     */
    @SuppressLint("SetTextI18n")
    @SuppressWarnings("unused")
    private static void updateFPSText(int num)
    {
        if (!fpsOverlayEnabled)
            return;

        mMainHandler.post(() -> {
            tvFps.setText(num + " FPS");
            tvFps.setVisibility(View.VISIBLE);
        });
    }

    /**
     * Applies the FPS overlay toggle (from the slide-out menu) and persists it;
     * the native side (eventthread.cpp) reads {@link #fpsOverlayEnabled} to
     * know whether to stream updates. The overlay becomes visible once the
     * first FPS value arrives (see {@link #updateFPSText}).
     */
    private void setFpsOverlayEnabled(boolean enabled)
    {
        fpsOverlayEnabled = enabled;
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putBoolean(PREFS_FPS_OVERLAY, enabled)
            .apply();

        if (!enabled)
            tvFps.setVisibility(View.GONE);
    }

    /**
     * This static method is used in native mkxp-z. (see systemImpl.cpp)
     * This method returns a string of current device locale tag. (e.g. "en_US")
     *
     * @return string of locale tag
     */
    @SuppressWarnings("unused")
    private static String getSystemLanguage()
    {
        return Locale.getDefault().toString();
    }

    /**
     * This static method is used in native mkxp-z. (see android-binding.cpp)
     * This method returns a boolean indicating that the device has a vibrator or not.
     *
     * @return boolean
     */
    @SuppressWarnings("unused")
    private static boolean hasVibrator()
    {
        return mVibrator.hasVibrator();
    }

    /**
     * This static method is used in native mkxp-z. (see android-binding.cpp)
     * This method makes the device vibrate for the given number of milliseconds.
     *
     * @param duration milliseconds duration of vibration
     */
    @SuppressWarnings("unused")
    private static void vibrate(int duration)
    {
        if (duration >= 10000) {
            duration = 10000;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            mVibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.EFFECT_HEAVY_CLICK));
        } else {
            mVibrator.vibrate(duration);
        }
    }

    /**
     * This static method is used in native mkxp-z. (see android-binding.cpp)
     * This method turns off the current device vibration.
     */
    @SuppressWarnings("unused")
    private static void vibrateStop()
    {
        mVibrator.cancel();
    }

    /**
     * This static method is used in native mkxp-z. (see android-binding.cpp)
     * This method returns a boolean indicating the app is in multi window mode or not.
     * (Multi-window mode is supported from Android 7.0 Nougat (API 24) and higher.)
     *
     * @param activity current MainActivity instance
     * @return boolean
     */
    @SuppressWarnings("unused")
    private static boolean inMultiWindow(Activity activity)
    {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity.isInMultiWindowMode();
    }

    /**
     * Launches the system file picker so the user can select a game archive.
     */
    private void pickGameArchive()
    {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        // .obb files have no standard MIME type, so also allow octet-stream.
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
            "application/zip",
            "application/x-zip-compressed",
            "application/octet-stream"
        });
        startActivityForResult(intent, REQUEST_LOAD_ARCHIVE);
    }

    /**
     * Launches the system file picker (multi-select) so the user can choose
     * save files to import into the game folder.
     */
    private void pickImportSaves()
    {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        // .rxdata/.rvdata files have no standard MIME type.
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
            "application/octet-stream",
            "application/x-rpgmaker"
        });
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
        startActivityForResult(intent, REQUEST_IMPORT_SAVES);
    }

    /**
     * Launches the system folder picker so the user can choose where to export
     * the game's save files.
     */
    private void pickExportSaves()
    {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        startActivityForResult(intent, REQUEST_EXPORT_SAVES);
    }

    /**
     * The directories where the game may keep its save files. RPG Maker's
     * {@code save_data} writes into the game folder, but games that use
     * mkxp's {@code System.data_directory} store saves in the app's private
     * data directory instead, so both are covered.
     */
    private File[] saveRoots()
    {
        File gameFolder = new File(GAME_PATH);
        File dataDir = getFilesDir();

        if (gameFolder.equals(dataDir))
            return new File[] { gameFolder };

        return new File[] { gameFolder, dataDir };
    }

    /**
     * Copies the user-selected save documents into the game folder.
     */
    private void importSaves(Intent data)
    {
        final List<Uri> uris = new ArrayList<>();
        if (data.getClipData() != null) {
            for (int i = 0; i < data.getClipData().getItemCount(); i++) {
                Uri uri = data.getClipData().getItemAt(i).getUri();
                if (uri != null)
                    uris.add(uri);
            }
        } else if (data.getData() != null) {
            uris.add(data.getData());
        }

        if (uris.isEmpty())
            return;

        final ProgressDialog dialog = new ProgressDialog(this);
        dialog.setMessage("Importing save data\u2026");
        dialog.setCancelable(false);
        dialog.show();

        final File[] roots = saveRoots();

        new Thread(() -> {
            final int imported = SaveTransfer.importSaves(MainActivity.this, uris, roots);

            runOnUiThread(() -> {
                dialog.dismiss();

                if (imported == 0) {
                    Toast.makeText(MainActivity.this,
                        "No save files were imported", Toast.LENGTH_LONG).show();
                } else {
                    Toast.makeText(MainActivity.this,
                        "Imported " + imported + " save file" + (imported == 1 ? "" : "s"),
                        Toast.LENGTH_LONG).show();
                }
            });
        }).start();
    }

    /**
     * Copies the game's save files into the user-selected folder.
     */
    private void exportSaves(Uri treeUri)
    {
        // Keep access to the chosen folder so the exported files stay readable.
        try {
            getContentResolver().takePersistableUriPermission(treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        } catch (SecurityException e) {
            Log.w(TAG, "Could not persist access to " + treeUri, e);
        }

        final ProgressDialog dialog = new ProgressDialog(this);
        dialog.setMessage("Exporting save data\u2026");
        dialog.setCancelable(false);
        dialog.show();

        final File[] roots = saveRoots();

        new Thread(() -> {
            final int total = SaveTransfer.findSaveFiles(roots).size();
            final int exported = SaveTransfer.exportSaves(MainActivity.this, treeUri, roots);

            runOnUiThread(() -> {
                dialog.dismiss();

                if (total == 0) {
                    Toast.makeText(MainActivity.this,
                        "No save data found to export", Toast.LENGTH_LONG).show();
                } else if (exported < total) {
                    Toast.makeText(MainActivity.this,
                        "Exported " + exported + " of " + total + " save files",
                        Toast.LENGTH_LONG).show();
                } else {
                    Toast.makeText(MainActivity.this,
                        "Exported " + exported + " save file" + (exported == 1 ? "" : "s"),
                        Toast.LENGTH_LONG).show();
                }
            });
        }).start();
    }

    /**
     * Extracts the selected archive into the game folder, then starts (or
     * restarts) the native game.
     */
    private void loadGameArchive(Uri uri)
    {
        final ProgressDialog dialog = new ProgressDialog(this);
        dialog.setMessage("Extracting game archive\u2026");
        dialog.setCancelable(false);
        dialog.show();

        new Thread(() -> {
            boolean success = false;
            String error = null;

            try (InputStream in = getContentResolver().openInputStream(uri)) {
                if (in == null)
                    throw new IOException("Could not open the selected file");

                File destRoot = new File(GAME_PATH_DEFAULT);
                success = ArchiveExtractor.extract(in, destRoot, new ArchiveExtractor.ProgressListener()
                {
                    @Override
                    public void onProgress(String entryName) { }

                    @Override
                    public void onError(String message)
                    {
                        runOnUiThread(() ->
                            Toast.makeText(MainActivity.this, message, Toast.LENGTH_LONG).show());
                    }
                });
            } catch (IOException e) {
                error = e.getMessage();
            }

            final boolean ok = success;
            final String err = error;

            runOnUiThread(() -> {
                dialog.dismiss();

                if (!ok) {
                    Toast.makeText(MainActivity.this, "Failed to extract archive" +
                        (err != null ? ": " + err : ""), Toast.LENGTH_LONG).show();
                    return;
                }

                File gameFolder = findGameFolder(new File(GAME_PATH_DEFAULT));
                if (gameFolder == null) {
                    Toast.makeText(MainActivity.this,
                        "No game found in archive (missing Game.ini / game .ini)", Toast.LENGTH_LONG).show();
                    return;
                }

                GAME_PATH = gameFolder.getAbsolutePath();
                persistGamePath(GAME_PATH);
                mSideMenu.setGamePath(GAME_PATH);

                if (!mStarted) {
                    mSideMenu.close();
                    runSDLThread();
                } else {
                    // Ruby can't be re-initialized in-process, so relaunch.
                    Toast.makeText(MainActivity.this, "Game loaded, restarting\u2026",
                        Toast.LENGTH_SHORT).show();
                    restartApp();
                }
            });
        }).start();
    }

    /**
     * Searches for the directory that actually contains a game, starting from
     * {@code root} and descending into its subdirectories.
     *
     * @return the game folder, or {@code null} if none was found.
     */
    private static File findGameFolder(File root)
    {
        if (findGameIni(root) != null)
            return root;

        File[] children = root.listFiles();
        if (children != null) {
            for (File child : children) {
                if (child.isDirectory()) {
                    File found = findGameFolder(child);
                    if (found != null)
                        return found;
                }
            }
        }
        return null;
    }

    /**
     * @return true when {@code dir} looks like a game folder.
     */
    private static boolean hasGame(File dir)
    {
        return findGameIni(dir) != null;
    }

    /**
     * Locates the game's INI file inside {@code dir}.
     *
     * <p>By default mkxp-z reads {@code Game.ini}, but a game may rename its
     * executable (and therefore its {@code .ini} and {@code .rgssad} files) and
     * declare the new name via the {@code execName} option in its
     * {@code mkxp.json} (e.g. {@code "execName": "Uranium"} makes mkxp-z look
     * for {@code Uranium.ini}).</p>
     *
     * @return the game INI file, or {@code null} if {@code dir} has none.
     */
    private static File findGameIni(File dir)
    {
        if (dir == null || !dir.isDirectory())
            return null;

        File gameIni = new File(dir, "Game.ini");
        if (gameIni.isFile())
            return gameIni;

        String execName = readExecName(new File(dir, "mkxp.json"));
        if (execName != null && !execName.isEmpty()) {
            File ini = new File(dir, execName + ".ini");
            if (ini.isFile())
                return ini;
        }

        return null;
    }

    /**
     * Extracts the {@code execName} value from a game's {@code mkxp.json}.
     *
     * <p>mkxp-z's config file is JSON with {@code //} comments, so rather than
     * parsing it fully we just look for the {@code "execName": "..."} pair.</p>
     *
     * @return the configured executable name, or {@code null} if unset/unreadable.
     */
    private static String readExecName(File mkxpJson)
    {
        if (mkxpJson == null || !mkxpJson.isFile())
            return null;

        StringBuilder sb = new StringBuilder();
        try (FileInputStream in = new FileInputStream(mkxpJson)) {
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) {
                sb.append(new String(buf, 0, n, StandardCharsets.UTF_8));
            }
        } catch (IOException e) {
            return null;
        }

        Matcher m = Pattern.compile("\"execName\"\\s*:\\s*\"([^\"]+)\"").matcher(sb.toString());
        return m.find() ? m.group(1) : null;
    }

    private void persistGamePath(String path)
    {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putString(PREFS_GAME_PATH, path)
            .apply();
    }

    private int dpPx(int value)
    {
        return (int) (value * getResources().getDisplayMetrics().density);
    }

    /**
     * Exits the process after scheduling a fresh launch, so a newly loaded
     * game can be booted cleanly (the Ruby VM cannot be re-initialized in the
     * running process).
     */
    private void restartApp()
    {
        try {
            Intent intent = new Intent(this, MainActivity.class);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);

            int flags = PendingIntent.FLAG_ONE_SHOT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                flags |= PendingIntent.FLAG_IMMUTABLE;

            PendingIntent pendingIntent = PendingIntent.getActivity(this, 0, intent, flags);

            AlarmManager alarm = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
            alarm.set(AlarmManager.RTC, System.currentTimeMillis() + 250, pendingIntent);
        } catch (Exception e) {
            Log.e(TAG, "Failed to schedule app restart", e);
        }

        System.exit(0);
    }

    private void handleEdgeSwipe(MotionEvent evt)
    {
        if (mSideMenu == null)
            return;

        int action = evt.getActionMasked();
        float density = getResources().getDisplayMetrics().density;
        float edgeWidth = 40f * density;
        float slop = 24f * density;

        if (action == MotionEvent.ACTION_DOWN) {
            if (!mSideMenu.isOpen() && evt.getX() < edgeWidth) {
                mEdgeTracking = true;
                mEdgeStartRawX = evt.getRawX();
                mSideMenu.revealHandle();
            } else {
                mEdgeTracking = false;
            }
        } else if (mEdgeTracking) {
            if (action == MotionEvent.ACTION_MOVE) {
                if (evt.getRawX() - mEdgeStartRawX > slop) {
                    mEdgeTracking = false;
                    mSideMenu.open();
                }
            } else if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                mEdgeTracking = false;
            }
        }
    }
}
