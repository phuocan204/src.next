// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.chromium.chrome.browser.history;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;
import android.view.View;
import android.view.WindowManager;

import org.chromium.base.ContextUtils;

/** Applies optional device authentication to sensitive browser activities. */
public final class PrivacyLockActivityCallbacks implements Application.ActivityLifecycleCallbacks {
    public static final String PREF_LOCK_BOOKMARKS = "privacy_lock_bookmarks";
    public static final String PREF_LOCK_DOWNLOADS = "privacy_lock_downloads";

    private static final String BOOKMARK_ACTIVITY =
            "org.chromium.chrome.browser.app.bookmarks.BookmarkActivity";
    private static final String DOWNLOAD_ACTIVITY =
            "org.chromium.chrome.browser.app.download.home.DownloadActivity";

    @Override
    public void onActivityCreated(Activity activity, Bundle savedInstanceState) {
        String preference = getProtectionPreference(activity.getClass().getName());
        if (preference == null
                || !ContextUtils.getAppSharedPreferences().getBoolean(preference, false)) {
            return;
        }

        activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        View content = activity.findViewById(android.R.id.content);
        if (content != null) content.setAlpha(0f);
        HistoryAccessAuthenticator.authenticate(activity, () -> {
            if (content != null) content.setAlpha(1f);
        }, activity::finish);
    }

    private static String getProtectionPreference(String activityName) {
        if (BOOKMARK_ACTIVITY.equals(activityName)) return PREF_LOCK_BOOKMARKS;
        if (DOWNLOAD_ACTIVITY.equals(activityName)) return PREF_LOCK_DOWNLOADS;
        return null;
    }

    @Override
    public void onActivityStarted(Activity activity) {}

    @Override
    public void onActivityResumed(Activity activity) {}

    @Override
    public void onActivityPaused(Activity activity) {}

    @Override
    public void onActivityStopped(Activity activity) {}

    @Override
    public void onActivitySaveInstanceState(Activity activity, Bundle outState) {}

    @Override
    public void onActivityDestroyed(Activity activity) {}
}
