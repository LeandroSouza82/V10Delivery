package com.example.v10_delivery

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.content.Context
import android.content.SharedPreferences
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "app.channel.launcher"
	private val PREFS = "v10_overlay_prefs"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
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
