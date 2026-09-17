// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.chromium.chrome.browser.ui.appmenu;

import android.os.Bundle;
import android.view.MenuItem;

import androidx.annotation.Nullable;

/** A delegate to handle menu item selection. */
public interface AppMenuDelegate {
    /** Handles selection of an item in the app menu. */
    boolean onOptionsItemSelected(int itemId, @Nullable Bundle menuItemData);

    /** Returns the properties delegate used to construct the app menu. */
    AppMenuPropertiesDelegate createAppMenuPropertiesDelegate();

    /**
     * Records the condensed title before dispatching the item. Kiwi encodes extension action
     * metadata in this field, so it must be forwarded rather than reconstructed from an item ID.
     */
    default void setLastItemTitle(String itemTitle) {}

    /** Records the visible title before dispatching the selected item. */
    default void setLastVisibleItemTitle(String itemTitle) {}
}
