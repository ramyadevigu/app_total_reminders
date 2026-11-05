package com.ramyadevi.total_reminders

import android.content.Context
import android.content.Intent
import android.os.Looper
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AlarmRingingServiceTest {
    @Test
    fun startingAnotherAlarmDoesNotStopTheRingingService() {
        val context = RuntimeEnvironment.getApplication()
        val firstAlarmId = 101
        val secondAlarmId = 102
        saveAlarm(context, firstAlarmId, "first-reminder")
        saveAlarm(context, secondAlarmId, "second-reminder")

        val controller = Robolectric.buildService(AlarmRingingService::class.java)
            .create()
        val service = controller.get()

        service.onStartCommand(startIntent(context, firstAlarmId), 0, 1)
        service.onStartCommand(startIntent(context, secondAlarmId), 0, 2)
        Shadows.shadowOf(Looper.getMainLooper()).idle()

        assertFalse(Shadows.shadowOf(service).isStoppedBySelf)
        assertEquals(secondAlarmId, AlarmScheduler.activeAlarmId(context))
        assertEquals("second-reminder", AlarmScheduler.activeReminderId(context))

        controller.destroy()
    }

    private fun saveAlarm(context: Context, alarmId: Int, reminderId: String) {
        val reminderJson = JSONObject()
            .put("id", reminderId)
            .put("title", reminderId)
            .put("dateTime", "2026-10-15T07:00:00")
            .put("recurrenceRule", JSONObject().put("type", "none"))
            .put("snoozeDurationMinutes", 15)
            .put("vibrate", false)
        val config = JSONObject()
            .put("id", alarmId)
            .put("reminderId", reminderId)
            .put("reminderJson", reminderJson.toString())
            .put("triggerAtMillis", System.currentTimeMillis() + 60_000)
            .put("isSnooze", false)
        context.getSharedPreferences("smarana_alarm_runtime", Context.MODE_PRIVATE)
            .edit()
            .putString("alarm_$alarmId", config.toString())
            .commit()
    }

    private fun startIntent(context: Context, alarmId: Int) =
        Intent(context, AlarmRingingService::class.java)
            .setAction(AlarmRingingService.ACTION_START)
            .putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarmId)
}
