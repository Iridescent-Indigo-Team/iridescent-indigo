package com.mkxpz.launcher;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * Extracts a ZIP archive (which is also the container format used by .obb
 * files) into a target directory. Only the entry name is inspected, so it
 * works identically for {@code .zip} and {@code .obb} inputs.
 */
public class ArchiveExtractor
{
    public interface ProgressListener
    {
        /** Called for each file entry as it is written. */
        void onProgress(String entryName);

        /** Called with a human readable description of a non-fatal problem. */
        void onError(String message);
    }

    private static final int BUFFER_SIZE = 64 * 1024;

    /**
     * Extracts {@code in} into {@code destDir}.
     *
     * @return true when the archive was fully processed without fatal errors.
     */
    public static boolean extract(InputStream in, File destDir, ProgressListener listener)
    {
        if (!destDir.exists() && !destDir.mkdirs()) {
            if (listener != null)
                listener.onError("Could not create game directory: " + destDir);
            return false;
        }

        byte[] buffer = new byte[BUFFER_SIZE];

        try (ZipInputStream zis = new ZipInputStream(in)) {
            ZipEntry entry;
            while ((entry = zis.getNextEntry()) != null) {
                // Some Windows-created archives use backslashes as separators.
                String name = entry.getName().replace('\\', '/');

                // Zip-slip protection: reject absolute paths and parent
                // traversal so we never write outside the destination. This is
                // a pure string check (fast, no per-entry filesystem calls).
                if (name.startsWith("/") || name.startsWith("../") || name.contains("/../")) {
                    if (listener != null)
                        listener.onError("Skipping entry that escapes the game folder: " + name);
                    zis.closeEntry();
                    continue;
                }

                File outFile = new File(destDir, name);

                if (entry.isDirectory()) {
                    if (!outFile.exists() && !outFile.mkdirs() && !outFile.isDirectory()) {
                        if (listener != null)
                            listener.onError("Could not create directory: " + name);
                    }
                } else {
                    File parent = outFile.getParentFile();
                    if (parent != null && !parent.exists() && !parent.mkdirs()) {
                        if (listener != null)
                            listener.onError("Could not create directory: " + parent.getPath());
                        zis.closeEntry();
                        continue;
                    }

                    if (listener != null)
                        listener.onProgress(name);

                    try (FileOutputStream fos = new FileOutputStream(outFile)) {
                        int len;
                        while ((len = zis.read(buffer)) > 0) {
                            fos.write(buffer, 0, len);
                        }
                    }
                }

                zis.closeEntry();
            }
            return true;
        } catch (IOException e) {
            if (listener != null)
                listener.onError(e.getMessage());
            return false;
        }
    }
}
