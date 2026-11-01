package com.example.mobile_games

import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Runs against the minified release APK, without camera or permission prompts. */
@RunWith(AndroidJUnit4::class)
class PoseLandmarkerReleaseTest {
    @Test(timeout = 120000)
    fun initializesAndDetectsBothPlayerRegions() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder()
                .setModelAssetPath("pose_landmarker_lite.task").build())
            .setRunningMode(RunningMode.IMAGE)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .build()
        // Creating options and the native graph triggered the platform_ failure.
        val detector = PoseLandmarker.createFromOptions(context, options)
        try {
            repeat(2) {
                val bitmap = Bitmap.createBitmap(320, 360, Bitmap.Config.ARGB_8888)
                val image = BitmapImageBuilder(bitmap).build()
                try {
                    assertTrue(detector.detect(image).landmarks().isEmpty())
                } finally {
                    image.close()
                    if (!bitmap.isRecycled) bitmap.recycle()
                }
            }
        } finally {
            detector.close()
        }
    }
}
