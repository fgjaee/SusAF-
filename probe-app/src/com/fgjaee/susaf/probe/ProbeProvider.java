package com.fgjaee.susaf.probe;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Bundle;
import android.os.Process;
import android.system.ErrnoException;
import android.system.Os;
import android.system.OsConstants;

/**
 * No root permissions, no filesystem mutations, and no network access.
 * A caller with shell/root UID may ask for up to 32 lstat checks at a time.
 * The provider runs inside an ordinary Android application process.
 */
public final class ProbeProvider extends ContentProvider {
    private static final String VERSION = "SUSAFPROBEV1";
    private static final int MAX_PATHS = 32;

    @Override public boolean onCreate() { return true; }

    @Override
    public Bundle call(String method, String arg, Bundle extras) {
        int caller = Binder.getCallingUid();
        if (caller != Process.ROOT_UID && caller != Process.SHELL_UID
                && caller != Process.myUid()) {
            throw new SecurityException("SusAF probe requires shell/root caller");
        }
        if (!"scan".equals(method) || arg == null) {
            return reply("INVALID");
        }

        String[] paths = arg.split("\\n", -1);
        if (paths.length < 1 || paths.length > MAX_PATHS) {
            return reply("INVALID");
        }
        StringBuilder out = new StringBuilder();
        for (String path : paths) {
            if (out.length() > 0) out.append(",");
            out.append(checkPath(path));
        }
        // Stable, machine-parseable protocol. Return neither file contents
        // nor the caller-supplied paths, which may reveal private state.
        return reply(paths.length + "__" + out);
    }

    private static boolean allowedPath(String path) {
        if (path == null || path.length() == 0 || path.length() > 1024 ||
                path.contains("\\r") || path.contains("\\t") ||
                path.contains("\\n") || path.indexOf(0) >= 0 ||
                path.contains("/../") || path.endsWith("/..") ||
                path.contains("/./") || path.endsWith("/.")) {
            return false;
        }
        return path.startsWith("/data/local/tmp/") ||
                path.startsWith("/apex/");
    }

    private static String checkPath(String path) {
        if (!allowedPath(path)) return "INVALID";
        try {
            Os.lstat(path);
            return "VISIBLE";
        } catch (ErrnoException e) {
            if (e.errno == OsConstants.ENOENT || e.errno == OsConstants.ENOTDIR) {
                return "MISSING";
            }
            if (e.errno == OsConstants.EACCES || e.errno == OsConstants.EPERM) {
                return "DENIED";
            }
            return "ERROR";
        } catch (RuntimeException e) {
            return "ERROR";
        }
    }

    private static Bundle reply(String value) {
        Bundle result = new Bundle();
        result.putString("result", VERSION + "__" + Process.myUid() + "__" + value);
        return result;
    }

    @Override public Cursor query(Uri uri, String[] projection, String selection,
                                  String[] selectionArgs, String sortOrder) {
        throw new UnsupportedOperationException();
    }
    @Override public String getType(Uri uri) {
        return null;
    }
    @Override public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException();
    }
    @Override public int delete(Uri uri, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException();
    }
    @Override public int update(Uri uri, ContentValues values, String selection,
                                String[] selectionArgs) {
        throw new UnsupportedOperationException();
    }
}
