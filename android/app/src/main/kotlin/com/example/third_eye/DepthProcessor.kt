package com.example.third_eye

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.calib3d.StereoBM
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.Rect
import org.opencv.imgproc.Imgproc
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min

object DepthProcessor {
    private var openCvReady: Boolean = false

    private fun ensureOpenCv() {
        if (!openCvReady) {
            openCvReady = OpenCVLoader.initDebug()
        }
        if (!openCvReady) {
            throw IllegalStateException("OpenCV failed to initialize")
        }
    }

    data class DepthOutput(
        val depthPng: ByteArray,
        val centerDisparity: Double?
    )

    fun computeFromPng(
        pngBytes: ByteArray,
        assumeSbs: Boolean,
        numDisparities: Int,
        blockSize: Int
    ): DepthOutput {
        ensureOpenCv()

        val bmp = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
            ?: throw IllegalArgumentException("Failed to decode PNG bytes")

        val rgba = Mat()
        Utils.bitmapToMat(bmp, rgba)

        val leftRgba: Mat
        val rightRgba: Mat

        if (assumeSbs && rgba.cols() >= 2) {
            val half = rgba.cols() / 2
            leftRgba = rgba.submat(Rect(0, 0, half, rgba.rows())).clone()
            rightRgba = rgba.submat(Rect(half, 0, rgba.cols() - half, rgba.rows())).clone()
        } else {
            leftRgba = rgba.clone()
            rightRgba = rgba.clone()
        }

        val leftGray = Mat()
        val rightGray = Mat()
        Imgproc.cvtColor(leftRgba, leftGray, Imgproc.COLOR_RGBA2GRAY)
        Imgproc.cvtColor(rightRgba, rightGray, Imgproc.COLOR_RGBA2GRAY)

        val targetWidth = 640
        if (leftGray.cols() > targetWidth) {
            val scale = targetWidth.toDouble() / leftGray.cols().toDouble()
            val newH = (leftGray.rows() * scale).toInt()
            Imgproc.resize(
                leftGray,
                leftGray,
                org.opencv.core.Size(targetWidth.toDouble(), newH.toDouble())
            )
            Imgproc.resize(
                rightGray,
                rightGray,
                org.opencv.core.Size(targetWidth.toDouble(), newH.toDouble())
            )
        }

        Imgproc.equalizeHist(leftGray, leftGray)
        Imgproc.equalizeHist(rightGray, rightGray)

        val bs = if (blockSize % 2 == 1) blockSize else blockSize + 1
        val nd = max(16, ((numDisparities + 15) / 16) * 16)

        val stereo = StereoBM.create(nd, bs)

        stereo.setPreFilterCap(31)
        stereo.setUniquenessRatio(12)
        stereo.setTextureThreshold(10)
        stereo.setSpeckleWindowSize(100)
        stereo.setSpeckleRange(32)
        stereo.setDisp12MaxDiff(1)

        val disp16 = Mat()
        stereo.compute(leftGray, rightGray, disp16)

        val disp8 = Mat()
        Core.normalize(disp16, disp8, 0.0, 255.0, Core.NORM_MINMAX, CvType.CV_8U)

        Imgproc.medianBlur(disp8, disp8, 5)

        val colored = Mat()
        Imgproc.applyColorMap(disp8, colored, Imgproc.COLORMAP_TURBO)

        val outBmp = Bitmap.createBitmap(colored.cols(), colored.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(colored, outBmp)

        val stream = ByteArrayOutputStream()
        outBmp.compress(Bitmap.CompressFormat.PNG, 100, stream)

        return DepthOutput(
            depthPng = stream.toByteArray(),
            centerDisparity = centerDisparity
        )
    }
}
