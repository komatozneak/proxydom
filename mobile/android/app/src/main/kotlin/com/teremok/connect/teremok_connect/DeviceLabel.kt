package com.teremok.connect.teremok_connect

import android.content.Context
import android.os.Build
import android.provider.Settings

/** Raw Android identity bits for Flutter [formatOsDeviceLabel]. */
object DeviceLabel {
    fun raw(context: Context): HashMap<String, String> {
        val settingsName = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                Settings.Global.getString(
                    context.contentResolver,
                    Settings.Global.DEVICE_NAME,
                ) ?: ""
            } else {
                ""
            }
        } catch (_: Exception) {
            ""
        }
        return hashMapOf(
            "settingsName" to settingsName,
            "brand" to (Build.BRAND ?: ""),
            "manufacturer" to (Build.MANUFACTURER ?: ""),
            "model" to (Build.MODEL ?: ""),
        )
    }
}
