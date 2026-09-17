// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.chromium.chrome.browser.history;

import android.app.Activity;
import android.content.Intent;

import org.chromium.base.Log;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/** Requests device authentication before running an action that displays browsing history. */
public final class HistoryAccessAuthenticator {
    private static final String TAG = "HistoryAuth";
    private static final String EXTRA_REQUEST_ID =
            "org.chromium.chrome.browser.history.REQUEST_ID";

    private static final AtomicInteger sNextRequestId = new AtomicInteger(1);
    private static final Map<Integer, PendingAction> sPendingActions = new HashMap<>();

    private HistoryAccessAuthenticator() {}

    /** Shows the system biometric/PIN prompt and runs {@code action} only after authentication. */
    public static void authenticate(Activity activity, Runnable action) {
        authenticate(activity, action, () -> {});
    }

    /** Requests authentication and invokes {@code onFailure} if it is cancelled or unavailable. */
    public static void authenticate(Activity activity, Runnable action, Runnable onFailure) {
        int requestId = sNextRequestId.getAndIncrement();
        synchronized (sPendingActions) {
            sPendingActions.put(requestId, new PendingAction(action, onFailure));
        }

        Intent intent = new Intent(activity, HistoryAuthenticationActivity.class);
        intent.putExtra(EXTRA_REQUEST_ID, requestId);
        try {
            activity.startActivity(intent);
        } catch (RuntimeException exception) {
            PendingAction pendingAction = removePendingAction(requestId);
            if (pendingAction != null) pendingAction.onFailure.run();
            Log.e(TAG, "Unable to start history authentication", exception);
        }
    }

    static int getRequestId(Intent intent) {
        return intent.getIntExtra(EXTRA_REQUEST_ID, 0);
    }

    static void complete(int requestId) {
        PendingAction pendingAction = removePendingAction(requestId);
        if (pendingAction != null) pendingAction.onSuccess.run();
    }

    static void cancel(int requestId) {
        PendingAction pendingAction = removePendingAction(requestId);
        if (pendingAction != null) pendingAction.onFailure.run();
    }

    private static PendingAction removePendingAction(int requestId) {
        synchronized (sPendingActions) {
            return sPendingActions.remove(requestId);
        }
    }

    private static final class PendingAction {
        final Runnable onSuccess;
        final Runnable onFailure;

        PendingAction(Runnable onSuccess, Runnable onFailure) {
            this.onSuccess = onSuccess;
            this.onFailure = onFailure;
        }
    }
}
