// Copyright 2022 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license.

package org.chromium.chrome.browser;

import org.chromium.chrome.browser.profiles.Profile;
import org.chromium.content_public.browser.WebContents;

/** Compatibility facade for optional Kiwi menu integrations. */
public final class AppMenuBridge {
    private AppMenuBridge() {}

    public static String getRunningExtensions(Profile profile, WebContents webContents) {
        return "";
    }

    public static void grantExtensionActiveTab(
            Profile profile, WebContents webContents, String extensionId) {}

    public static void callExtension(
            Profile profile, WebContents webContents, String extensionId) {}

    public static void openDevTools(WebContents webContents) {}

    public static void disableProxy(Profile profile) {}

    public static boolean isProxyEnabled(Profile profile) {
        return false;
    }
}
