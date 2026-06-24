package com.majidalbana.app

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

open class MainActivity : FlutterActivity() {
    private val notificationSettingsChannel = "majidalbana/notification_settings"
    private val appIconChannel = "majidalbana/app_icon"
    private val launcherPrefsName = "majidalbana_launcher_icon_prefs"
    private val pendingIconKey = "pending_is_dark"
    private val appliedIconKey = "applied_is_dark"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationSettingsChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationSettings" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                        }

                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val fallbackIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(fallbackIntent)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            appIconChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAppIcon" -> {
                    val isDark = call.argument<Boolean>("isDark") ?: false
                    try {
                        // لا نبدّل alias فوراً والتطبيق مفتوح، لأن تعطيل الـ alias الحالي
                        // يجعل Android يغلق الـ Activity. نحفظ الطلب ونطبقه عند خروج التطبيق للخلفية.
                        savePendingLauncherIcon(isDark)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onStop() {
        super.onStop()
        applyPendingLauncherIconIfNeeded()
    }

    private fun savePendingLauncherIcon(isDark: Boolean) {
        getSharedPreferences(launcherPrefsName, MODE_PRIVATE)
            .edit()
            .putBoolean(pendingIconKey, isDark)
            .apply()
    }

    private fun applyPendingLauncherIconIfNeeded() {
        val prefs = getSharedPreferences(launcherPrefsName, MODE_PRIVATE)
        if (!prefs.contains(pendingIconKey)) return

        val isDark = prefs.getBoolean(pendingIconKey, false)
        val hasAppliedState = prefs.contains(appliedIconKey)
        val alreadyApplied = hasAppliedState && prefs.getBoolean(appliedIconKey, false) == isDark

        if (alreadyApplied) {
            prefs.edit().remove(pendingIconKey).apply()
            return
        }

        try {
            setLauncherIcon(isDark)
            prefs.edit()
                .putBoolean(appliedIconKey, isDark)
                .remove(pendingIconKey)
                .apply()
        } catch (_: Exception) {
            // نخلي الطلب محفوظ حتى يحاول مرة ثانية عند خروج التطبيق للخلفية.
        }
    }

    private fun setLauncherIcon(isDark: Boolean) {
        val packageManager = packageManager
        val defaultLauncher = ComponentName(this, "$packageName.DefaultIconActivity")
        val lightAlias = ComponentName(this, "$packageName.MainActivityLightAlias")
        val darkAlias = ComponentName(this, "$packageName.MainActivityDarkAlias")

        val enableAlias = if (isDark) darkAlias else lightAlias
        val disableAlias = if (isDark) lightAlias else darkAlias

        setComponentState(
            packageManager,
            enableAlias,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        )

        setComponentState(
            packageManager,
            disableAlias,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        )

        setComponentState(
            packageManager,
            defaultLauncher,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        )
    }

    private fun setComponentState(
        packageManager: PackageManager,
        componentName: ComponentName,
        newState: Int
    ) {
        if (packageManager.getComponentEnabledSetting(componentName) != newState) {
            packageManager.setComponentEnabledSetting(
                componentName,
                newState,
                PackageManager.DONT_KILL_APP
            )
        }
    }
}

class DefaultIconActivity : MainActivity()
