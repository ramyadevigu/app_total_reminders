package com.ramyadevi.total_reminders

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException

class AlarmRingingService : Service() {
    companion object {
        const val ACTION_START = "com.ramyadevi.total_reminders.RING_ALARM"
        const val ACTION_STOP = "com.ramyadevi.total_reminders.STOP_ALARM"
        const val ACTION_SNOOZE = "com.ramyadevi.total_reminders.SNOOZE_ALARM"
        const val ACTION_TIMEOUT = "com.ramyadevi.total_reminders.TIMEOUT_ALARM"
        const val ACTION_CANCEL = "com.ramyadevi.total_reminders.CANCEL_ALARM"

        private const val NOTIFICATION_CHANNEL = "active_alarm"
        private const val NOTIFICATION_ID = 9001
        private const val WAKE_LOCK_TAG = "TotalReminders:AlarmRinging"
        private const val RING_LIMIT_MILLIS = 5 * 60 * 1000L
        private const val SNOOZE_PATTERN_MILLIS = 15 * 60 * 1000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var ringingId: Int? = null
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val timeout = Runnable {
        ringingId?.let { finishAlarm(it, ACTION_TIMEOUT) }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1)
            ?.takeIf { it >= 0 }
            ?: AlarmScheduler.activeAlarmId(this)
        if (id == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        when (intent?.action) {
            ACTION_START, null -> {
                startRinging(id)
                return if (ringingId == id) START_STICKY else START_NOT_STICKY
            }
            ACTION_STOP -> finishAlarm(id, ACTION_STOP)
            ACTION_SNOOZE -> finishAlarm(id, ACTION_SNOOZE)
            ACTION_TIMEOUT -> finishAlarm(id, ACTION_TIMEOUT)
            ACTION_CANCEL -> finishAlarm(id, ACTION_CANCEL)
            else -> stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(timeout)
        stopAudioAndVibration()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun startRinging(id: Int) {
        val encodedReminder = AlarmScheduler.reminderJson(this, id) ?: run {
            stopSelf()
            return
        }
        val reminder = try {
            JSONObject(encodedReminder)
        } catch (error: JSONException) {
            Log.e("TotalRemindersAlarm", "Invalid reminder data for alarm $id.", error)
            stopSelf()
            return
        }
        ringingId?.takeIf { it != id }?.let { previousId ->
            finishAlarm(previousId, ACTION_STOP, stopService = false)
        }
        ringingId = id
        AlarmScheduler.markActive(this, id)
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification(id, reminder))
        val remainingTime = AlarmScheduler.remainingRingTime(this, id)
        if (remainingTime <= 0L) {
            finishAlarm(id, ACTION_TIMEOUT)
            return
        }
        acquireWakeLock()
        playAlarmSound(reminder.optString("soundUri").takeIf { it.isNotEmpty() })
        startVibration(reminder.optBoolean("vibrate", true))
        AlarmScheduler.scheduleRingTimeout(this, id)
        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, remainingTime)
        AlarmScheduler.notifyRinging(this, id)
    }

    private fun finishAlarm(id: Int, action: String, stopService: Boolean = true) {
        if (ringingId != null && ringingId != id) {
            return
        }
        val persistedActiveId = AlarmScheduler.activeAlarmId(this)
        if (persistedActiveId != null && persistedActiveId != id) {
            return
        }

        handler.removeCallbacks(timeout)
        AlarmScheduler.cancelRingTimeout(this, id)
        when (action) {
            ACTION_STOP -> AlarmScheduler.finishWithStop(this, id)
            ACTION_SNOOZE, ACTION_TIMEOUT -> AlarmScheduler.finishWithSnooze(this, id)
            ACTION_CANCEL -> Unit
        }
        stopAudioAndVibration()
        releaseWakeLock()
        AlarmScheduler.notifyStopped(this, id)
        AlarmScheduler.clearActive(this, id)
        ringingId = null
        if (stopService) {
            getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        }
    }

    private fun buildNotification(id: Int, reminder: JSONObject): Notification {
        val title = reminder.optString("title", "Alarm")
        val description = reminder.optString("description").trim()
        val configuredSnoozeMinutes = reminder.optInt("snoozeDurationMinutes", 15)
        val snoozeMinutes = if (configuredSnoozeMinutes in 1..1440) {
            configuredSnoozeMinutes
        } else {
            15
        }
        val snoozeLabel = if (snoozeMinutes >= 60 && snoozeMinutes % 60 == 0) {
            "${snoozeMinutes / 60} hr"
        } else {
            "$snoozeMinutes min"
        }
        val launchIntent = Intent(this, MainActivity::class.java)
            .setAction(AlarmScheduler.ACTION_OPEN_ALARM)
            .putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        val fullScreenIntent = PendingIntent.getActivity(
            this,
            id,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopAction = serviceActionPendingIntent(id, ACTION_STOP, 1)
        val snoozeAction = serviceActionPendingIntent(id, ACTION_SNOOZE, 2)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(description.ifEmpty { "Alarm is ringing" })
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setFullScreenIntent(fullScreenIntent, true)
            .setContentIntent(fullScreenIntent)
            .addAction(
                Notification.Action.Builder(null, "Snooze · $snoozeLabel", snoozeAction).build(),
            )
            .addAction(Notification.Action.Builder(null, "Stop", stopAction).build())
            .apply {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    @Suppress("DEPRECATION")
                    setPriority(Notification.PRIORITY_MAX)
                }
            }
            .build()
    }

    private fun serviceActionPendingIntent(id: Int, action: String, actionCode: Int) =
        PendingIntent.getService(
            this,
            id * 10 + actionCode,
            Intent(this, AlarmRingingService::class.java)
                .setAction(action)
                .setData(Uri.parse("smarana://alarm/$id/$action"))
                .putExtra(AlarmScheduler.EXTRA_ALARM_ID, id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL,
            "Ringing alarms",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Active alarms"
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun playAlarmSound(soundUri: String?) {
        val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        val requestedUri = soundUri?.let(Uri::parse) ?: defaultUri
        mediaPlayer = createMediaPlayer(requestedUri)
        if (mediaPlayer == null && requestedUri != defaultUri) {
            Log.e(
                "TotalRemindersAlarm",
                "Selected alarm sound is unavailable; using the system alarm sound.",
            )
            mediaPlayer = createMediaPlayer(defaultUri)
        }
        if (mediaPlayer == null) {
            Log.e("TotalRemindersAlarm", "Unable to play the system alarm sound.")
        }
    }

    private fun createMediaPlayer(uri: Uri): MediaPlayer? {
        val player = MediaPlayer()
        return try {
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            player.setDataSource(this, uri)
            player.isLooping = true
            player.prepare()
            player.start()
            player
        } catch (error: IOException) {
            player.release()
            Log.e("TotalRemindersAlarm", "Unable to load alarm audio.", error)
            null
        } catch (error: SecurityException) {
            player.release()
            Log.e("TotalRemindersAlarm", "Alarm sound access was denied.", error)
            null
        } catch (error: IllegalArgumentException) {
            player.release()
            Log.e("TotalRemindersAlarm", "Invalid alarm sound URI.", error)
            null
        } catch (error: IllegalStateException) {
            player.release()
            Log.e("TotalRemindersAlarm", "Unable to start alarm audio.", error)
            null
        }
    }

    private fun startVibration(enabled: Boolean) {
        if (!enabled) {
            return
        }
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 800, 400)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun stopAudioAndVibration() {
        mediaPlayer?.release()
        mediaPlayer = null
        vibrator?.cancel()
        vibrator = null
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) {
            return
        }
        val powerManager = getSystemService(PowerManager::class.java)
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            WAKE_LOCK_TAG,
        ).apply {
            setReferenceCounted(false)
            acquire(RING_LIMIT_MILLIS + SNOOZE_PATTERN_MILLIS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }
}
