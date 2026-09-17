// Copyright 2022 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license.

package org.chromium.chrome.browser.settings;

import android.app.Activity;

/** Compatibility helper used by legacy Kiwi preference screens. */
public final class ToolbarSettings {
    private ToolbarSettings() {}

    public static void AskForRelaunch(Activity activity) {
        activity.recreate();
    }
}
