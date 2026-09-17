// Copyright 2022 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license.

package org.chromium.chrome.browser;

import org.chromium.chrome.browser.tab.Tab;

/** Compatibility hook retained for Kiwi's optional developer-tools window. */
public final class FixDevToolsWindow {
    private FixDevToolsWindow() {}

    public static void Execute(Tab tab) {}
}
