package com.ramyadevi.total_reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1)
        if (id < 0) {
            return
        }

        if (intent.action == AlarmScheduler.ACTION_TIMEOUT) {
            AlarmScheduler.handleRingTimeout(context, id)
            return
        }

        val serviceIntent = Intent(context, AlarmRingingService::class.java)
            .putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
        when (intent.action) {
            AlarmScheduler.ACTION_TRIGGER -> {
                if (AlarmScheduler.reminderJson(context, id) == null) {
                    return
                }
                serviceIntent.action = AlarmRingingService.ACTION_START
            }
            else -> return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
