package com.teremok.connect.teremok_connect

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * VPN shade card. Two channels, one notification id, one user pref.
 *
 * Connected always has a standard [addAction] «Отключиться».
 * No compact RemoteViews — Pixel clips a 48dp custom row.
 */
object ShadeNotification {
    const val CHANNEL_VISIBLE = "teremok_shade_v1"
    const val CHANNEL_QUIET = "teremok_shade_quiet_v1"
    private const val NOTIFICATION_ID = 42_001
    private const val PREFS = "teremok_shade"
    private const val KEY_VISIBLE = "shade_notification_visible"

    private val LEGACY_CHANNELS = listOf(
        "teremok_vpn",
        "teremok_vpn_v2",
        "teremok_vpn_v3",
        "teremok_vpn_v4",
        "teremok_vpn_v5",
        "teremok_vpn_minimal",
        "teremok_vpn_minimal_v3",
        "teremok_vpn_minimal_v4",
        "teremok_vpn_minimal_v5",
        "teremok_vpn_connected_v6",
    )

    fun notificationId(): Int = NOTIFICATION_ID

    fun isVisible(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_VISIBLE, true)

    fun setVisible(context: Context, visible: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_VISIBLE, visible)
            .commit()
    }

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        for (id in LEGACY_CHANNELS) {
            runCatching { nm.deleteNotificationChannel(id) }
        }
        if (nm.getNotificationChannel(CHANNEL_VISIBLE) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_VISIBLE,
                    "Уведомление в шторке",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Карточка VPN с кнопкой отключения"
                    setShowBadge(false)
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }
        if (nm.getNotificationChannel(CHANNEL_QUIET) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_QUIET,
                    "Фон VPN",
                    NotificationManager.IMPORTANCE_MIN,
                ).apply {
                    description = "Служебное уведомление, пока VPN включён"
                    setShowBadge(false)
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }
    }

    fun connecting(context: Context): Notification {
        ensureChannels(context)
        return build(
            context = context,
            line = context.getString(R.string.vpn_notification_connecting),
            connected = false,
        )
    }

    fun connected(
        context: Context,
        sessionLine: String,
        downText: String,
        upText: String,
    ): Notification {
        ensureChannels(context)
        return build(
            context = context,
            line = buildLine(sessionLine, downText, upText),
            connected = true,
        )
    }

    private fun buildLine(sessionLine: String, downText: String, upText: String): String {
        val speeds = buildString {
            if (downText.isNotEmpty()) append("↓ $downText")
            if (upText.isNotEmpty()) {
                if (isNotEmpty()) append("  ")
                append("↑ $upText")
            }
        }
        return when {
            sessionLine.isNotBlank() && speeds.isNotEmpty() -> "$sessionLine · $speeds"
            sessionLine.isNotBlank() -> sessionLine
            speeds.isNotEmpty() -> speeds
            else -> ""
        }
    }

    private fun build(
        context: Context,
        line: String,
        connected: Boolean,
    ): Notification {
        val visible = isVisible(context)
        val channel = if (visible) CHANNEL_VISIBLE else CHANNEL_QUIET
        val status = line.ifBlank { context.getString(R.string.vpn_notification_connected) }
        val builder = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_proxydom)
            .setContentTitle("Прокси Дом")
            .setContentText(status)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(launchPending(context))
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setVisibility(
                if (visible) {
                    NotificationCompat.VISIBILITY_PUBLIC
                } else {
                    NotificationCompat.VISIBILITY_SECRET
                },
            )
            .setPriority(
                if (visible) {
                    NotificationCompat.PRIORITY_LOW
                } else {
                    NotificationCompat.PRIORITY_MIN
                },
            )

        if (connected && VpnShadePolicy.showConnectedAction("connected")) {
            builder.addAction(
                0,
                context.getString(R.string.vpn_notification_disconnect),
                disconnectPending(context),
            )
        }
        return builder.build()
    }

    private fun launchPending(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            context.packageManager.getLaunchIntentForPackage(context.packageName),
            pendingFlags(),
        )

    private fun disconnectPending(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            1,
            Intent(context, VpnActionReceiver::class.java).apply {
                action = VpnActionReceiver.ACTION_DISCONNECT
            },
            pendingFlags(),
        )

    private fun pendingFlags(): Int {
        val base = PendingIntent.FLAG_UPDATE_CURRENT
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            base or PendingIntent.FLAG_IMMUTABLE
        } else {
            base
        }
    }
}
