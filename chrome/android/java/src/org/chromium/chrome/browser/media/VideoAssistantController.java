// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.chromium.chrome.browser.media;

import android.annotation.TargetApi;
import android.app.Activity;
import android.content.Context;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.media.AudioManager;
import android.os.Build;
import android.os.Handler;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.chromium.base.ContextUtils;
import org.chromium.chrome.browser.tab.Tab;
import org.chromium.chrome.browser.tab.TabUtils;
import org.chromium.content.browser.MediaSessionImpl;

import java.util.WeakHashMap;

/** Fullscreen web-video controls and gestures inspired by mobile video players. */
public final class VideoAssistantController {
    private static final long DOUBLE_TAP_TIMEOUT_MS = 300;
    private static final long CONTROLS_TIMEOUT_MS = 3000;
    private static final float GESTURE_THRESHOLD_DP = 16f;
    private static final float[] PLAYBACK_SPEEDS = {0.5f, 1f, 1.25f, 1.5f, 2f, 3f};

    private static final int GESTURE_NONE = 0;
    private static final int GESTURE_BRIGHTNESS = 1;
    private static final int GESTURE_VOLUME = 2;
    private static final int GESTURE_SEEK = 3;

    private static final WeakHashMap<Activity, VideoAssistantController> sControllers =
            new WeakHashMap<>();

    private final Activity mActivity;
    private final Tab mTab;
    private final FrameLayout mOverlay;
    private final LinearLayout mControls;
    private final TextView mPlayButton;
    private final TextView mSpeedButton;
    private final TextView mFitButton;
    private final TextView mLockButton;
    private final TextView mGestureMessage;
    private final Handler mHandler = new Handler();
    private final AudioManager mAudioManager;
    private final float mDensity;
    private final float mOriginalBrightness;
    private final int mOriginalRequestedOrientation;

    private final Runnable mHideControlsRunnable = () -> setControlsVisible(false);
    private Runnable mPendingSingleTap;
    private long mLastTapTime;
    private float mLastTapX;
    private float mDownX;
    private float mDownY;
    private float mStartBrightness;
    private int mStartVolume;
    private int mGesture = GESTURE_NONE;
    private long mPendingSeekMs;
    private boolean mPlaying = true;
    private boolean mLocked;
    private int mSpeedIndex = 1;
    private int mFitMode;
    private boolean mCaptionsVisible;

    /** Adds the assistant over the fullscreen video belonging to {@code tab}. */
    public static void showForTab(Tab tab) {
        if (!ContextUtils.getAppSharedPreferences().getBoolean(
                "video_assistant_enabled", true)) {
            return;
        }
        Activity activity = TabUtils.getActivity(tab);
        if (activity == null || tab.getWebContents() == null) return;
        MediaSessionImpl mediaSession = MediaSessionImpl.fromWebContents(tab.getWebContents());
        if (mediaSession == null || !mediaSession.isControllable()) return;
        VideoAssistantController oldController = sControllers.remove(activity);
        if (oldController != null) oldController.destroy();
        VideoAssistantController controller = new VideoAssistantController(activity, tab);
        sControllers.put(activity, controller);
        controller.show();
    }

    /** Removes the assistant when the tab leaves fullscreen. */
    public static void hideForTab(Tab tab) {
        Activity activity = TabUtils.getActivity(tab);
        if (activity == null) return;
        VideoAssistantController controller = sControllers.remove(activity);
        if (controller != null) controller.destroy();
    }

    private VideoAssistantController(Activity activity, Tab tab) {
        mActivity = activity;
        mTab = tab;
        mDensity = activity.getResources().getDisplayMetrics().density;
        mAudioManager = (AudioManager) activity.getSystemService(Context.AUDIO_SERVICE);
        mOriginalBrightness = activity.getWindow().getAttributes().screenBrightness;
        mOriginalRequestedOrientation = activity.getRequestedOrientation();

        mOverlay = new FrameLayout(activity);
        mOverlay.setClickable(true);
        mOverlay.setFocusable(true);
        mOverlay.setKeepScreenOn(true);
        mOverlay.setOnTouchListener(this::onTouch);

        mControls = new LinearLayout(activity);
        mControls.setGravity(Gravity.CENTER);
        mControls.setOrientation(LinearLayout.HORIZONTAL);
        mControls.setPadding(dp(8), dp(8), dp(8), dp(8));
        mControls.setBackgroundColor(0x99000000);

        TextView rewind = createButton("-10", view -> seekBy(-10000));
        mPlayButton = createButton("II", view -> togglePlayback());
        TextView forward = createButton("+10", view -> seekBy(10000));
        mSpeedButton = createButton("1x", view -> cyclePlaybackSpeed());
        mFitButton = createButton("FIT", view -> cycleFitMode());
        TextView captions = createButton("CC", view -> toggleCaptions());
        TextView rotate = createButton("ROT", view -> rotateScreen());
        TextView pip = createButton("PiP", view -> enterPictureInPicture());
        mLockButton = createButton("LOCK", view -> toggleLock());
        TextView close = createButton("X", view -> exitFullscreen());

        mControls.addView(rewind);
        mControls.addView(mPlayButton);
        mControls.addView(forward);
        mControls.addView(mSpeedButton);
        mControls.addView(mFitButton);
        mControls.addView(captions);
        mControls.addView(rotate);
        mControls.addView(pip);
        mControls.addView(mLockButton);
        mControls.addView(close);

        HorizontalScrollView controlsScroller = new HorizontalScrollView(activity);
        controlsScroller.setFillViewport(true);
        controlsScroller.setHorizontalScrollBarEnabled(false);
        controlsScroller.addView(mControls, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        FrameLayout.LayoutParams controlsParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        controlsParams.bottomMargin = dp(24);
        mOverlay.addView(controlsScroller, controlsParams);

        mGestureMessage = new TextView(activity);
        mGestureMessage.setTextColor(Color.WHITE);
        mGestureMessage.setTextSize(18);
        mGestureMessage.setGravity(Gravity.CENTER);
        mGestureMessage.setPadding(dp(16), dp(10), dp(16), dp(10));
        mGestureMessage.setBackgroundColor(0x99000000);
        mGestureMessage.setVisibility(View.GONE);
        FrameLayout.LayoutParams messageParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER);
        mOverlay.addView(mGestureMessage, messageParams);
    }

    private void show() {
        ViewGroup content = mActivity.findViewById(android.R.id.content);
        if (content == null) return;
        content.addView(mOverlay, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        scheduleControlsHide();
    }

    private TextView createButton(String text, View.OnClickListener listener) {
        TextView button = new TextView(mActivity);
        button.setText(text);
        button.setTextColor(Color.WHITE);
        button.setTextSize(14);
        button.setTypeface(Typeface.DEFAULT_BOLD);
        button.setGravity(Gravity.CENTER);
        button.setMinWidth(dp(48));
        button.setMinHeight(dp(48));
        button.setPadding(dp(8), dp(8), dp(8), dp(8));
        button.setOnClickListener(listener);
        return button;
    }

    private boolean onTouch(View view, MotionEvent event) {
        if (mLocked) {
            if (event.getActionMasked() == MotionEvent.ACTION_UP) setControlsVisible(true);
            return true;
        }

        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                mDownX = event.getX();
                mDownY = event.getY();
                mGesture = GESTURE_NONE;
                mPendingSeekMs = 0;
                WindowManager.LayoutParams attributes = mActivity.getWindow().getAttributes();
                mStartBrightness = attributes.screenBrightness < 0 ? 0.5f
                                                                   : attributes.screenBrightness;
                mStartVolume = mAudioManager == null ? 0
                        : mAudioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
                return true;
            case MotionEvent.ACTION_MOVE:
                handleMove(event);
                return true;
            case MotionEvent.ACTION_UP:
                if (mGesture == GESTURE_SEEK && mPendingSeekMs != 0) {
                    seekBy(mPendingSeekMs);
                } else if (mGesture == GESTURE_NONE) {
                    handleTap(event.getX());
                }
                hideGestureMessageSoon();
                return true;
            case MotionEvent.ACTION_CANCEL:
                hideGestureMessageSoon();
                return true;
            default:
                return true;
        }
    }

    private void handleMove(MotionEvent event) {
        float deltaX = event.getX() - mDownX;
        float deltaY = event.getY() - mDownY;
        if (mGesture == GESTURE_NONE
                && Math.max(Math.abs(deltaX), Math.abs(deltaY)) < dp(GESTURE_THRESHOLD_DP)) {
            return;
        }
        if (mGesture == GESTURE_NONE) {
            if (Math.abs(deltaX) > Math.abs(deltaY)) {
                mGesture = GESTURE_SEEK;
            } else {
                mGesture = mDownX < mOverlay.getWidth() / 2f
                        ? GESTURE_BRIGHTNESS : GESTURE_VOLUME;
            }
            setControlsVisible(false);
        }

        if (mGesture == GESTURE_SEEK) {
            mPendingSeekMs = Math.round(deltaX / mOverlay.getWidth() * 120000);
            showGestureMessage((mPendingSeekMs >= 0 ? "+" : "")
                    + Math.round(mPendingSeekMs / 1000f) + "s");
        } else if (mGesture == GESTURE_BRIGHTNESS) {
            float brightness = clamp(mStartBrightness - deltaY / mOverlay.getHeight(), 0.01f, 1f);
            WindowManager.LayoutParams attributes = mActivity.getWindow().getAttributes();
            attributes.screenBrightness = brightness;
            mActivity.getWindow().setAttributes(attributes);
            showGestureMessage("Brightness " + Math.round(brightness * 100) + "%");
        } else if (mGesture == GESTURE_VOLUME && mAudioManager != null) {
            int maxVolume = mAudioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
            int volume = Math.round(clamp(
                    mStartVolume - deltaY / mOverlay.getHeight() * maxVolume, 0, maxVolume));
            mAudioManager.setStreamVolume(AudioManager.STREAM_MUSIC, volume, 0);
            showGestureMessage("Volume " + Math.round(volume * 100f / maxVolume) + "%");
        }
    }

    private void handleTap(float x) {
        long now = android.os.SystemClock.uptimeMillis();
        if (now - mLastTapTime <= DOUBLE_TAP_TIMEOUT_MS
                && Math.abs(x - mLastTapX) < dp(80)) {
            if (mPendingSingleTap != null) mHandler.removeCallbacks(mPendingSingleTap);
            mPendingSingleTap = null;
            mLastTapTime = 0;
            if (x < mOverlay.getWidth() / 3f) {
                seekBy(-10000);
            } else if (x > mOverlay.getWidth() * 2f / 3f) {
                seekBy(10000);
            } else {
                togglePlayback();
            }
            return;
        }

        mLastTapTime = now;
        mLastTapX = x;
        mPendingSingleTap = () -> {
            setControlsVisible(mControls.getVisibility() != View.VISIBLE);
            mPendingSingleTap = null;
        };
        mHandler.postDelayed(mPendingSingleTap, DOUBLE_TAP_TIMEOUT_MS);
    }

    private MediaSessionImpl getMediaSession() {
        if (mTab.getWebContents() == null) return null;
        return MediaSessionImpl.fromWebContents(mTab.getWebContents());
    }

    private void togglePlayback() {
        MediaSessionImpl session = getMediaSession();
        if (session == null) return;
        if (mPlaying) {
            session.suspend();
            mPlayButton.setText(">");
        } else {
            session.resume();
            mPlayButton.setText("II");
        }
        mPlaying = !mPlaying;
        showControlsTemporarily();
    }

    private void seekBy(long milliseconds) {
        MediaSessionImpl session = getMediaSession();
        if (session != null && milliseconds != 0) session.seek(milliseconds);
        showGestureMessage((milliseconds >= 0 ? "+" : "") + (milliseconds / 1000) + "s");
        hideGestureMessageSoon();
    }

    private void cyclePlaybackSpeed() {
        mSpeedIndex = (mSpeedIndex + 1) % PLAYBACK_SPEEDS.length;
        float speed = PLAYBACK_SPEEDS[mSpeedIndex];
        mSpeedButton.setText(formatSpeed(speed));
        evaluateVideoScript("for(const v of getFullscreenVideos())v.playbackRate=" + speed + ";");
        showControlsTemporarily();
    }

    private void cycleFitMode() {
        String[] modes = {"contain", "cover", "fill"};
        String[] labels = {"FIT", "CROP", "FILL"};
        mFitMode = (mFitMode + 1) % modes.length;
        mFitButton.setText(labels[mFitMode]);
        evaluateVideoScript("for(const v of getFullscreenVideos()){"
                + "v.style.objectFit='" + modes[mFitMode]
                + "';v.style.width='100vw';v.style.height='100vh';}");
        showControlsTemporarily();
    }

    private void toggleLock() {
        mLocked = !mLocked;
        for (int i = 0; i < mControls.getChildCount(); i++) {
            View child = mControls.getChildAt(i);
            child.setVisibility(child == mLockButton ? View.VISIBLE
                                                     : (mLocked ? View.GONE : View.VISIBLE));
        }
        mLockButton.setText(mLocked ? "UNLOCK" : "LOCK");
        mHandler.removeCallbacks(mHideControlsRunnable);
        setControlsVisible(true);
        if (!mLocked) scheduleControlsHide();
    }

    private void toggleCaptions() {
        mCaptionsVisible = !mCaptionsVisible;
        String mode = mCaptionsVisible ? "showing" : "disabled";
        evaluateVideoScript("for(const v of getFullscreenVideos())for(const t of v.textTracks)"
                + "t.mode='" + mode + "';");
        showGestureMessage(mCaptionsVisible ? "Captions on" : "Captions off");
        hideGestureMessageSoon();
    }

    private void rotateScreen() {
        boolean isLandscape = mActivity.getResources().getConfiguration().orientation
                == android.content.res.Configuration.ORIENTATION_LANDSCAPE;
        mActivity.setRequestedOrientation(isLandscape
                        ? ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                        : ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    }

    @TargetApi(Build.VERSION_CODES.O)
    private void enterPictureInPicture() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O
                || !mActivity.getPackageManager().hasSystemFeature(
                        PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
            showGestureMessage("Picture-in-picture is not available");
            hideGestureMessageSoon();
            return;
        }
        sControllers.remove(mActivity);
        destroy();
        mActivity.enterPictureInPictureMode();
    }

    private void exitFullscreen() {
        evaluateVideoScript("if(document.fullscreenElement)document.exitFullscreen();");
    }

    private void evaluateVideoScript(String script) {
        if (mTab.getWebContents() != null) {
            String helpers = "const getFullscreenVideos=()=>{const r=document.fullscreenElement;"
                    + "if(r&&r.tagName==='VIDEO')return[r];"
                    + "return r?r.querySelectorAll('video'):document.querySelectorAll('video');};";
            mTab.getWebContents().evaluateJavaScript(
                    "(()=>{" + helpers + script + "})()", null);
        }
    }

    private void showControlsTemporarily() {
        setControlsVisible(true);
        scheduleControlsHide();
    }

    private void scheduleControlsHide() {
        mHandler.removeCallbacks(mHideControlsRunnable);
        if (!mLocked) mHandler.postDelayed(mHideControlsRunnable, CONTROLS_TIMEOUT_MS);
    }

    private void setControlsVisible(boolean visible) {
        mControls.setVisibility(visible ? View.VISIBLE : View.GONE);
        if (visible) scheduleControlsHide();
    }

    private void showGestureMessage(String message) {
        mGestureMessage.setText(message);
        mGestureMessage.setVisibility(View.VISIBLE);
    }

    private void hideGestureMessageSoon() {
        mHandler.postDelayed(() -> mGestureMessage.setVisibility(View.GONE), 600);
    }

    private void destroy() {
        mHandler.removeCallbacksAndMessages(null);
        removeOverlay();
        WindowManager.LayoutParams attributes = mActivity.getWindow().getAttributes();
        attributes.screenBrightness = mOriginalBrightness;
        mActivity.getWindow().setAttributes(attributes);
        mActivity.setRequestedOrientation(mOriginalRequestedOrientation);
    }

    private void removeOverlay() {
        ViewGroup parent = (ViewGroup) mOverlay.getParent();
        if (parent != null) parent.removeView(mOverlay);
    }

    private int dp(float value) {
        return Math.round(value * mDensity);
    }

    private static float clamp(float value, float min, float max) {
        return Math.max(min, Math.min(max, value));
    }

    private static String formatSpeed(float speed) {
        return speed == Math.round(speed) ? Math.round(speed) + "x" : speed + "x";
    }
}
