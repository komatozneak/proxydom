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
 * Foreground VPN notification.
 *
 * Detailed (default): Amnezia-style card — speeds, region, disconnect.
 * Minimal: required FGS stub when user turns the shade card off in Settings.
 */
object VpnNotificationHelper {
    private const val CHANNEL_DETAILED = "teremok_vpn_v2"
    private const val CHANNEL_MINIMAL = "teremok_vpn_minimal"
    private const val LEGACY_CHANNEL_ID = "teremok_vpn"
    private const val NOTIFICATION_ID = 42_001

    private const val PREFS = "teremok_vpn_notification"
    private const val KEY_DETAILED = "detailed_enabled"

    /** User preference: show the long shade card. Default ON. */
    fun isDetailedEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_DETAILED, true)

    fun setDetailedEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_DETAILED, enabled)
            .commit()
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java)
        runCatching { nm.deleteNotificationChannel(LEGACY_CHANNEL_ID) }

        if (nm.getNotificationChannel(CHANNEL_DETAILED) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_DETAILED,
                    "Теремок VPN",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "Подробный статус VPN в шторке"
                    setShowBadge(false)
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }
        if (nm.getNotificationChannel(CHANNEL_MINIMAL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_MINIMAL,
                    "Теремок VPN (фон)",
                    NotificationManager.IMPORTANCE_MIN,
                ).apply {
                    description = "Служебное уведомление при скрытой карточке"
                    setShowBadge(false)
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }
    }

    fun startConnecting(context: Context): Notification {
        ensureChannel(context)
        return if (isDetailedEnabled(context)) {
            buildDetailed(
                context = context,
                sessionLine = context.getString(R.string.vpn_notification_connecting),
                statusLine = context.getString(R.string.vpn_notification_connecting),
                downText = "",
                upText = "",
                showDisconnect = false,
            )
        } else {
            buildMinimal(
                context,
                context.getString(R.string.vpn_notification_connecting),
            )
        }
    }

    fun buildConnected(
        context: Context,
        sessionLine: String,
        downText: String,
        upText: String,
    ): Notification {
        ensureChannel(context)
        return if (isDetailedEnabled(context)) {
            buildDetailed(
                context = context,
                sessionLine = sessionLine,
                statusLine = context.getString(R.string.vpn_notification_connected),
                downText = downText,
                upText = upText,
                showDisconnect = true,
            )
        } else {
            buildMinimal(
                context,
                context.getString(R.string.vpn_notification_connected),
            )
        }
    }

    private fun buildDetailed(
        context: Context,
        sessionLine: String,
        statusLine: String,
        downText: String,
        upText: String,
        showDisconnect: Boolean,
    ): Notification {
        val launch = launchPending(context)
        val title = buildString {
            append("Теремок VPN")
            if (downText.isNotEmpty() || upText.isNotEmpty()) {
                append(" • ")
                if (downText.isNotEmpty()) append("↓ $downText")
                if (upText.isNotEmpty()) {
                    if (downText.isNotEmpty()) append(" ")
                    append("↑ $upText")
                }
            }
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_DETAILED)
            .setSmallIcon(R.drawable.ic_qs_vpn)
            .setContentTitle(title)
            .setContentText(sessionLine)
            .setContentInfo(statusLine)
            .setSubText(statusLine)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .setBigContentTitle(title)
                    .bigText("$sessionLine\n$statusLine"),
            )
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(launch)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        if (showDisconnect) {
            builder.addAction(
                0,
                context.getString(R.string.vpn_notification_disconnect),
                disconnectPending(context),
            )
        }
        return builder.build()
    }

    /** Tiny FGS stub — Android still requires a notification while VPN runs. */
    private fun buildMinimal(context: Context, status: String): Notification {
        return NotificationCompat.Builder(context, CHANNEL_MINIMAL)
            .setSmallIcon(R.drawable.ic_qs_vpn)
            .setContentTitle("Теремок VPN")
            .setContentText(status)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(launchPending(context))
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
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

    fun notificationId(): Int = NOTIFICATION_ID

    private fun pendingFlags(): Int {
        val base = PendingIntent.FLAG_UPDATE_CURRENT
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            base or PendingIntent.FLAG_IMMUTABLE
        } else {
            base
        }
    }
}
