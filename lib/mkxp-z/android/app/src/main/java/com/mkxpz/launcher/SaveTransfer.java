package com.mkxpz.launcher;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.provider.OpenableColumns;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Imports and exports RPG Maker save files ({@code .rxdata}, {@code .rvdata}
 * and {@code .rvdata2}) between the game and user-chosen storage via the
 * Storage Access Framework.
 *
 * <p>Save files can end up in more than one place: the standard RPG Maker
 * {@code save_data} writes relative to the game's working directory (the game
 * folder), while games that use mkxp's {@code System.data_directory} write to
 * the app's private data directory. To be safe both locations are searched on
 * export and written to on import. Subdirectories are searched too (some games
 * keep saves in a subfolder), but the game's own {@code Data/} folder is
 * skipped so game assets are never mistaken for saves.</p>
 */
public final class SaveTransfer
{
    private static final String TAG = "mkxp-z[SaveTransfer]";

    private static final String[] SAVE_EXTENSIONS = { ".rxdata", ".rvdata", ".rvdata2" };

    private static final String SAVE_MIME = "application/octet-stream";

    private static final int BUFFER_SIZE = 64 * 1024;

    private SaveTransfer() { }

    /**
     * @return true when {@code name} looks like a save file name.
     */
    public static boolean isSaveFileName(String name)
    {
        if (name == null)
            return false;

        String lower = name.toLowerCase();
        for (String ext : SAVE_EXTENSIONS) {
            if (lower.endsWith(ext))
                return true;
        }
        return false;
    }

    /**
     * Collects save files from every candidate root, deduplicated by file name.
     */
    public static List<File> findSaveFiles(File[] roots)
    {
        Map<String, File> unique = new LinkedHashMap<>();

        if (roots != null) {
            for (File root : roots) {
                if (root != null && root.isDirectory()) {
                    Log.i(TAG, "Scanning for save files in " + root.getAbsolutePath());
                    collectSaveFiles(root, unique);
                }
            }
        }

        return new ArrayList<>(unique.values());
    }

    private static void collectSaveFiles(File dir, Map<String, File> out)
    {
        File[] children = dir.listFiles();
        if (children == null)
            return;

        for (File child : children) {
            if (child.isDirectory()) {
                // The game's own database lives in Data/ and is not save data.
                if (child.getName().equalsIgnoreCase("Data"))
                    continue;
                collectSaveFiles(child, out);
            } else if (child.isFile() && isSaveFileName(child.getName())) {
                if (!out.containsKey(child.getName()))
                    out.put(child.getName(), child);
            }
        }
    }

    /**
     * Copies every found save file into the document tree selected by the user.
     *
     * @return the number of save files that were exported.
     */
    public static int exportSaves(Context context, Uri treeUri, File[] roots)
    {
        ContentResolver resolver = context.getContentResolver();
        List<File> saves = findSaveFiles(roots);

        int exported = 0;
        for (File save : saves) {
            try {
                if (copyToTree(resolver, treeUri, save)) {
                    exported++;
                    Log.i(TAG, "Exported " + save.getAbsolutePath());
                }
            } catch (IOException e) {
                Log.w(TAG, "Failed to export " + save.getAbsolutePath(), e);
            }
        }

        return exported;
    }

    /**
     * Copies each selected document into every candidate root, overwriting any
     * existing file with the same name. Non-save files are skipped.
     *
     * @return the number of save files that were imported.
     */
    public static int importSaves(Context context, List<Uri> uris, File[] roots)
    {
        ContentResolver resolver = context.getContentResolver();

        int imported = 0;
        for (Uri uri : uris) {
            try {
                String name = queryDisplayName(resolver, uri);
                if (name == null || name.isEmpty())
                    name = new File(uri.getLastPathSegment()).getName();

                if (!isSaveFileName(name)) {
                    Log.w(TAG, "Skipping non-save file: " + name);
                    continue;
                }

                boolean copied = false;
                if (roots != null) {
                    for (File root : roots) {
                        if (root == null || !root.isDirectory())
                            continue;

                        File dest = new File(root, name);
                        copyFromUri(resolver, uri, dest);
                        Log.i(TAG, "Imported " + name + " -> " + dest.getAbsolutePath());
                        copied = true;
                    }
                }

                if (copied)
                    imported++;
            } catch (IOException e) {
                Log.w(TAG, "Failed to import save file from " + uri, e);
            }
        }

        return imported;
    }

    private static boolean copyToTree(ContentResolver resolver, Uri treeUri, File source)
        throws IOException
    {
        Uri document = findOrCreateDocument(resolver, treeUri, source.getName(), SAVE_MIME);
        if (document == null)
            return false;

        try (InputStream in = new FileInputStream(source);
             OutputStream out = resolver.openOutputStream(document, "w")) {
            if (out == null)
                return false;
            copy(in, out);
        }

        return true;
    }

    private static void copyFromUri(ContentResolver resolver, Uri uri, File dest)
        throws IOException
    {
        try (InputStream in = resolver.openInputStream(uri);
             OutputStream out = new FileOutputStream(dest)) {
            if (in == null)
                throw new IOException("Could not open " + uri);
            copy(in, out);
        }
    }

    /**
     * Returns the document for {@code name} inside {@code treeUri}, reusing an
     * existing one so re-exporting overwrites instead of failing.
     */
    private static Uri findOrCreateDocument(ContentResolver resolver, Uri treeUri,
                                            String name, String mime)
        throws IOException
    {
        String treeDocId = DocumentsContract.getTreeDocumentId(treeUri);

        // Prefer an existing document so we overwrite it rather than fail.
        Uri childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, treeDocId);
        try (Cursor c = resolver.query(childrenUri, new String[] {
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            }, null, null, null)) {
            if (c != null) {
                while (c.moveToNext()) {
                    if (name.equals(c.getString(1)))
                        return DocumentsContract.buildDocumentUriUsingTree(treeUri, c.getString(0));
                }
            }
        } catch (Exception e) {
            // Some providers don't support listing children; fall through to
            // creating a new document.
        }

        Uri parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, treeDocId);
        return DocumentsContract.createDocument(resolver, parentUri, mime, name);
    }

    private static String queryDisplayName(ContentResolver resolver, Uri uri)
    {
        try (Cursor c = resolver.query(uri, new String[] { OpenableColumns.DISPLAY_NAME },
                                       null, null, null)) {
            if (c != null && c.moveToFirst()) {
                int idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (idx >= 0)
                    return c.getString(idx);
            }
        }
        return null;
    }

    private static void copy(InputStream in, OutputStream out) throws IOException
    {
        byte[] buffer = new byte[BUFFER_SIZE];
        int n;
        while ((n = in.read(buffer)) > 0)
            out.write(buffer, 0, n);
    }
}
