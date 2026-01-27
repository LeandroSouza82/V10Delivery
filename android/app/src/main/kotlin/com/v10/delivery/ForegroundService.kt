package com.v10.delivery

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ForegroundService : Service() {
    companion object {
        const val ACTION_START = "ACTION_START_FOREGROUND"
        const val ACTION_STOP = "ACTION_STOP_FOREGROUND"
        const val CHANNEL_ID = "v10_foreground_channel"
        const val NOTIF_ID = 1001
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_START) {
            startForegroundServiceWithNotification()
        } else if (action == ACTION_STOP) {
            stopForeground(true)
            stopSelf()
        }
        return START_STICKY
    }

    private fun startForegroundServiceWithNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "V10 Service", NotificationManager.IMPORTANCE_LOW)
            channel.setShowBadge(false)
            nm.createNotificationChannel(channel)
        }

        // Title and message per request
        val title = "V10 Delivery — Online"
        val text = "Buscando novas rotas e pedidos em tempo real."

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(getApplicationInfo().icon)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)

        // Try to set a brand color (blue) and accent if supported
        try {
            val brandBlue = Color.parseColor("#1976D2")
            builder.color = brandBlue
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setColorized(true)
            }
        } catch (e: Exception) {
            // ignore color parse errors
        }

        val notification: Notification = builder.build()
        startForeground(NOTIF_ID, notification)
    }
}
