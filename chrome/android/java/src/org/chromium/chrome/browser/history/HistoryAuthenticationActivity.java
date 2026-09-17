// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.chromium.chrome.browser.history;

import android.annotation.TargetApi;
import android.app.Activity;
import android.app.KeyguardManager;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.hardware.biometrics.BiometricPrompt;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.widget.Toast;

import org.chromium.chrome.R;

/** Transparent host activity for the system authentication prompt used to protect History. */
public final class HistoryAuthenticationActivity extends Activity {
    private static final int REQUEST_CONFIRM_DEVICE_CREDENTIAL = 1;

    private int mRequestId;
    private boolean mAuthenticationStarted;
    private boolean mLaunchingCredential;
    private CancellationSignal mCancellationSignal;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        mRequestId = HistoryAccessAuthenticator.getRequestId(getIntent());
        if (mRequestId == 0) {
            finish();
            return;
        }
        startAuthentication();
    }

    private void startAuthentication() {
        if (mAuthenticationStarted) return;
        mAuthenticationStarted = true;

        KeyguardManager keyguardManager =
                (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
        if (keyguardManager == null || !keyguardManager.isKeyguardSecure()) {
            Toast.makeText(this, R.string.history_auth_screen_lock_required, Toast.LENGTH_LONG)
                    .show();
            cancelAndFinish();
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            authenticateWithBiometricOrCredential();
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            authenticateWithBiometric();
        } else {
            launchDeviceCredential();
        }
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private void authenticateWithBiometricOrCredential() {
        mCancellationSignal = new CancellationSignal();
        BiometricPrompt prompt = new BiometricPrompt.Builder(this)
                .setTitle(getString(R.string.history_auth_title))
                .setSubtitle(getString(R.string.history_auth_subtitle))
                .setDeviceCredentialAllowed(true)
                .build();
        prompt.authenticate(mCancellationSignal, getMainExecutor(), createAuthenticationCallback());
    }

    @TargetApi(Build.VERSION_CODES.P)
    private void authenticateWithBiometric() {
        mCancellationSignal = new CancellationSignal();
        DialogInterface.OnClickListener usePinListener = (dialog, which) -> {
            mLaunchingCredential = true;
            launchDeviceCredential();
        };
        BiometricPrompt prompt = new BiometricPrompt.Builder(this)
                .setTitle(getString(R.string.history_auth_title))
                .setSubtitle(getString(R.string.history_auth_subtitle))
                .setNegativeButton(getString(R.string.history_auth_use_screen_lock),
                        getMainExecutor(), usePinListener)
                .build();
        prompt.authenticate(mCancellationSignal, getMainExecutor(), createAuthenticationCallback());
    }

    @TargetApi(Build.VERSION_CODES.P)
    private BiometricPrompt.AuthenticationCallback createAuthenticationCallback() {
        return new BiometricPrompt.AuthenticationCallback() {
            @Override
            public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult result) {
                completeAndFinish();
            }

            @Override
            public void onAuthenticationError(int errorCode, CharSequence errString) {
                if (mLaunchingCredential) return;
                if (Build.VERSION.SDK_INT == Build.VERSION_CODES.P
                        && (errorCode == BiometricPrompt.BIOMETRIC_ERROR_HW_NOT_PRESENT
                                || errorCode == BiometricPrompt.BIOMETRIC_ERROR_HW_UNAVAILABLE
                                || errorCode == BiometricPrompt.BIOMETRIC_ERROR_NO_BIOMETRICS)) {
                    mLaunchingCredential = true;
                    launchDeviceCredential();
                    return;
                }
                cancelAndFinish();
            }
        };
    }

    private void launchDeviceCredential() {
        KeyguardManager keyguardManager =
                (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
        Intent intent = keyguardManager == null ? null
                : keyguardManager.createConfirmDeviceCredentialIntent(
                        getString(R.string.history_auth_title),
                        getString(R.string.history_auth_subtitle));
        if (intent == null) {
            cancelAndFinish();
            return;
        }
        startActivityForResult(intent, REQUEST_CONFIRM_DEVICE_CREDENTIAL);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_CONFIRM_DEVICE_CREDENTIAL) return;
        if (resultCode == RESULT_OK) {
            completeAndFinish();
        } else {
            cancelAndFinish();
        }
    }

    private void completeAndFinish() {
        HistoryAccessAuthenticator.complete(mRequestId);
        mRequestId = 0;
        finish();
    }

    private void cancelAndFinish() {
        HistoryAccessAuthenticator.cancel(mRequestId);
        mRequestId = 0;
        finish();
    }

    @Override
    protected void onDestroy() {
        if (mCancellationSignal != null) mCancellationSignal.cancel();
        if (isFinishing() && mRequestId != 0) HistoryAccessAuthenticator.cancel(mRequestId);
        super.onDestroy();
    }
}
