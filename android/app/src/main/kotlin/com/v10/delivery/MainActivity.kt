package com.v10.delivery

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.content.Context
import android.content.SharedPreferences
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "app.channel.launcher"
    private val PREFS = "v10_overlay_prefs"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Criar canal de notificações 'pedidos' com som customizado (res/raw/buzina.mp3)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channelId = "pedidos"
                val existing = nm.getNotificationChannel(channelId)
                if (existing == null) {
                    val channel = NotificationChannel(channelId, "Pedidos", NotificationManager.IMPORTANCE_HIGH)
                    val soundUri = Uri.parse("android.resource://" + applicationContext.packageName + "/raw/buzina")
                    val audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    channel.setSound(soundUri, audioAttributes)
                    channel.enableLights(true)
                    nm.createNotificationChannel(channel)
                }
            }
        } catch (e: Exception) {
            // ignore errors creating channel
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "createPedidosChannel" -> {
                    val sound = call.argument<String>("sound") ?: "buzina"
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            val channelId = "pedidos"
                            val existing = nm.getNotificationChannel(channelId)
                            if (existing == null) {
                                val channel = NotificationChannel(channelId, "Pedidos", NotificationManager.IMPORTANCE_HIGH)
                                val soundUri = Uri.parse("android.resource://" + applicationContext.packageName + "/raw/" + sound)
                                val audioAttributes = AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                    .build()
                                channel.setSound(soundUri, audioAttributes)
                                channel.enableLights(true)
                                nm.createNotificationChannel(channel)
                            }
                        }
                    } catch (e: Exception) {
                        // ignore
                    }
                    result.success(true)
                }
                "bringToFront" -> {
                    bringAppToFront()
                    result.success(true)
                }
                "startForegroundService" -> {
                    startV10Service()
                    result.success(true)
                }
                "stopForegroundService" -> {
                    stopV10Service()
                    result.success(true)
                }
                "saveOverlayPosition" -> {
                    val x = (call.argument<Double>("x") ?: 0.0).toFloat()
                    val y = (call.argument<Double>("y") ?: 0.0).toFloat()
                    savePosition(x, y)
                    result.success(true)
                }
                "getOverlayPosition" -> {
                    val pos = getPosition()
                    result.success(pos)
                }
                "openOverlaySettings" -> {
                    openOverlaySettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun bringAppToFront() {
        try {
            val intent = Intent(this, MainActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            startActivity(intent)
        } catch (e: Exception) {
            // ignore
        }
    }

    private fun startV10Service() {
        try {
            val intent = Intent(this, ForegroundService::class.java)
            intent.action = ForegroundService.ACTION_START
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            // ignore
        }
    }

    private fun stopV10Service() {
        try {
            val intent = Intent(this, ForegroundService::class.java)
            intent.action = ForegroundService.ACTION_STOP
            startService(intent)
        } catch (e: Exception) {
            // ignore
        }
    }

    private fun savePosition(x: Float, y: Float) {
        val prefs: SharedPreferences = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit().putFloat("overlay_x", x).putFloat("overlay_y", y).apply()
    }

    private fun getPosition(): Map<String, Any> {
        val prefs: SharedPreferences = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val x = prefs.getFloat("overlay_x", -1f)
        val y = prefs.getFloat("overlay_y", -1f)
        return mapOf("x" to x.toDouble(), "y" to y.toDouble())
    }

    private fun openOverlaySettings() {
        try {
            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
            intent.data = android.net.Uri.parse("package:" + packageName)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            // ignore
        }
    }
}
