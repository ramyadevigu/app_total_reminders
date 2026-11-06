package com.ramyadevi.total_reminders

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import org.json.JSONException
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit

internal object AlarmScheduler {
    const val ACTION_TRIGGER = "com.ramyadevi.total_reminders.ALARM_TRIGGER"
    const val ACTION_TIMEOUT = "com.ramyadevi.total_reminders.ALARM_TIMEOUT"
    const val ACTION_RINGING = "com.ramyadevi.total_reminders.ALARM_RINGING"
    const val ACTION_STOPPED = "com.ramyadevi.total_reminders.ALARM_STOPPED"
    const val ACTION_OPEN_ALARM = "com.ramyadevi.total_reminders.OPEN_ALARM"
    const val EXTRA_ALARM_ID = "alarmId"

    private const val PREFERENCES = "smarana_alarm_runtime"
    private const val ACTIVE_ALARM_ID = "active_alarm_id"
    private const val ACTIVE_REMINDER_ID = "active_reminder_id"
    private const val ACTIVE_ALARM_DEADLINE = "active_alarm_deadline"
    private const val ALARM_PREFIX = "alarm_"
    private const val TIMEOUT_MINUTES = 5L

    fun schedule(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        reminderJson: String,
        isSnooze: Boolean,
    ) {
        val preferences = preferences(context)
        val oldConfig = readConfig(context, id)
        val oldTrigger = oldConfig?.optLong("triggerAtMillis", 0L) ?: 0L
        val keepExistingSnooze =
            !isSnooze &&
                oldConfig?.optBoolean("isSnooze", false) == true &&
                oldTrigger > System.currentTimeMillis()
        val actualTrigger = if (keepExistingSnooze) oldTrigger else triggerAtMillis
        val actualSnooze = isSnooze || keepExistingSnooze
        val reminder = JSONObject(reminderJson)
        val config = JSONObject()
            .put("id", id)
            .put("reminderId", reminder.optString("id"))
            .put("reminderJson", reminderJson)
            .put("triggerAtMillis", actualTrigger)
            .put("isSnooze", actualSnooze)
        check(preferences.edit().putString(keyFor(id), config.toString()).commit()) {
            "Unable to persist alarm $id."
        }
        scheduleAt(context, id, actualTrigger)
    }

    fun cancel(context: Context, id: Int) {
        cancelPendingAlarm(context, id)
        cancelRingTimeout(context, id)
        preferences(context).edit().remove(keyFor(id)).apply()
        if (activeAlarmId(context) == id) {
            startServiceAction(context, AlarmRingingService.ACTION_CANCEL, id)
        }
    }

    fun pendingSnoozeTime(context: Context, id: Int): Long? {
        if (activeAlarmId(context) == id) {
            return null
        }
        val config = readConfig(context, id) ?: return null
        val triggerAtMillis = config.optLong("triggerAtMillis", 0L)
        return triggerAtMillis.takeIf {
            config.optBoolean("isSnooze", false) && it > 0L
        }
    }

    fun activeAlarmId(context: Context): Int? {
        val id = preferences(context).getInt(ACTIVE_ALARM_ID, -1)
        return id.takeIf { it >= 0 }
    }

    fun activeReminderId(context: Context): String? {
        return preferences(context).getString(ACTIVE_REMINDER_ID, null)
    }

    fun reminderJson(context: Context, id: Int): String? {
        return readConfig(context, id)?.optString("reminderJson")
    }

    fun requestStop(context: Context, id: Int) {
        startServiceAction(context, AlarmRingingService.ACTION_STOP, id)
    }

    fun requestSnooze(context: Context, id: Int) {
        startServiceAction(context, AlarmRingingService.ACTION_SNOOZE, id)
    }

    fun markActive(context: Context, id: Int) {
        val preferences = preferences(context)
        val reminderId = readConfig(context, id)?.optString("reminderId") ?: return
        val existingId = preferences.getInt(ACTIVE_ALARM_ID, -1)
        val existingDeadline = preferences.getLong(ACTIVE_ALARM_DEADLINE, 0L)
        if (existingId == id && existingDeadline > System.currentTimeMillis()) {
            return
        }
        check(preferences.edit()
            .putInt(ACTIVE_ALARM_ID, id)
            .putString(ACTIVE_REMINDER_ID, reminderId)
            .putLong(
                ACTIVE_ALARM_DEADLINE,
                System.currentTimeMillis() + TIMEOUT_MINUTES * 60_000L,
            )
            .commit()) { "Unable to persist active alarm state." }
    }

    fun remainingRingTime(context: Context, id: Int): Long {
        val preferences = preferences(context)
        if (preferences.getInt(ACTIVE_ALARM_ID, -1) != id) {
            return 0L
        }
        return preferences.getLong(ACTIVE_ALARM_DEADLINE, 0L) -
            System.currentTimeMillis()
    }

    fun clearActive(context: Context, id: Int) {
        val preferences = preferences(context)
        if (preferences.getInt(ACTIVE_ALARM_ID, -1) == id) {
            preferences.edit()
                .remove(ACTIVE_ALARM_ID)
                .remove(ACTIVE_REMINDER_ID)
                .remove(ACTIVE_ALARM_DEADLINE)
                .apply()
        }
    }

    fun notifyRinging(context: Context, id: Int) {
        val reminderId = readConfig(context, id)?.optString("reminderId") ?: return
        val intent = Intent(ACTION_RINGING)
            .setPackage(context.packageName)
            .putExtra("reminderId", reminderId)
        context.sendBroadcast(intent)
    }

    fun notifyStopped(context: Context, id: Int) {
        val reminderId = activeReminderId(context) ?: return
        context.sendBroadcast(
            Intent(ACTION_STOPPED)
                .setPackage(context.packageName)
                .putExtra("reminderId", reminderId),
        )
    }

    fun scheduleRingTimeout(context: Context, id: Int) {
        val triggerAt = preferences(context).getLong(
            ACTIVE_ALARM_DEADLINE,
            System.currentTimeMillis() + TIMEOUT_MINUTES * 60_000L,
        )
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pendingIntent = timeoutPendingIntent(context, id)
        setAlarm(alarmManager, triggerAt, pendingIntent)
    }

    fun cancelRingTimeout(context: Context, id: Int) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pendingIntent = timeoutPendingIntent(context, id)
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    fun finishWithSnooze(context: Context, id: Int) {
        val config = readConfig(context, id) ?: return
        val reminder = try {
            JSONObject(config.getString("reminderJson"))
        } catch (error: JSONException) {
            Log.e("TotalRemindersAlarm", "Invalid reminder data for alarm $id.", error)
            return
        }
        val configuredMinutes = reminder.optInt("snoozeDurationMinutes", 15)
        val snoozeMinutes = if (configuredMinutes in 1..1440) {
            configuredMinutes.toLong()
        } else {
            15L
        }
        val triggerAt = System.currentTimeMillis() + snoozeMinutes * 60_000L
        config.put("triggerAtMillis", triggerAt)
            .put("isSnooze", true)
        check(
            preferences(context).edit()
                .putString(keyFor(id), config.toString())
                .commit(),
        ) { "Unable to persist alarm snooze." }
        scheduleAt(context, id, triggerAt)
    }

    fun finishWithStop(context: Context, id: Int) {
        val config = readConfig(context, id) ?: return
        val reminder = try {
            JSONObject(config.getString("reminderJson"))
        } catch (error: JSONException) {
            Log.e("TotalRemindersAlarm", "Invalid reminder data for alarm $id.", error)
            cancelPendingAlarm(context, id)
            config.put("triggerAtMillis", 0L).put("isSnooze", false)
            check(
                preferences(context).edit()
                    .putString(keyFor(id), config.toString())
                    .commit(),
            ) { "Unable to persist alarm state." }
            return
        }
        val nextOccurrence = nextOccurrence(reminder, System.currentTimeMillis())
        config.put("triggerAtMillis", nextOccurrence ?: 0L)
            .put("isSnooze", false)
        check(
            preferences(context).edit()
                .putString(keyFor(id), config.toString())
                .commit(),
        ) { "Unable to persist the next alarm occurrence." }
        if (nextOccurrence == null) {
            cancelPendingAlarm(context, id)
        } else {
            scheduleAt(context, id, nextOccurrence)
        }
    }

    fun handleRingTimeout(context: Context, id: Int) {
        if (activeAlarmId(context) != id) {
            return
        }
        cancelRingTimeout(context, id)
        finishWithSnooze(context, id)
        notifyStopped(context, id)
        clearActive(context, id)
        context.stopService(
            Intent(context, AlarmRingingService::class.java),
        )
    }

    fun rescheduleAfterBoot(context: Context, resetActiveState: Boolean = false) {
        val preferences = preferences(context)
        if (resetActiveState) {
            preferences.edit()
                .remove(ACTIVE_ALARM_ID)
                .remove(ACTIVE_REMINDER_ID)
                .remove(ACTIVE_ALARM_DEADLINE)
                .apply()
        }
        val now = System.currentTimeMillis()
        for ((key, encoded) in preferences.all) {
            if (!key.startsWith(ALARM_PREFIX) || encoded !is String) {
                continue
            }
            val config = try {
                JSONObject(encoded)
            } catch (error: JSONException) {
                Log.e("TotalRemindersAlarm", "Invalid saved alarm configuration.", error)
                continue
            }
            val id = config.optInt("id", -1)
            if (id < 0 || activeAlarmId(context) == id) {
                continue
            }
            var triggerAt = config.optLong("triggerAtMillis", 0L)
            if (triggerAt <= 0L) {
                continue
            }
            if (triggerAt <= now && !config.optBoolean("isSnooze", false)) {
                val reminder = try {
                    JSONObject(config.getString("reminderJson"))
                } catch (error: JSONException) {
                    Log.e("TotalRemindersAlarm", "Invalid reminder data for alarm $id.", error)
                    continue
                }
                val nextOccurrence = nextOccurrence(reminder, now)
                if (nextOccurrence == null) {
                    config.put("triggerAtMillis", 0L)
                    preferences.edit().putString(key, config.toString()).apply()
                    continue
                }
                triggerAt = nextOccurrence
                config.put("triggerAtMillis", triggerAt)
                preferences.edit().putString(key, config.toString()).apply()
            }
            scheduleAt(context, id, maxOf(triggerAt, now))
        }
    }

    private fun scheduleAt(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
    ) {
        if (triggerAtMillis <= 0L) {
            cancelPendingAlarm(context, id)
            return
        }
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val triggerIntent = triggerPendingIntent(context, id)
        val canScheduleExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()
        if (canScheduleExact) {
            val showIntent = PendingIntent.getActivity(
                context,
                id,
                Intent(context, MainActivity::class.java)
                    .setAction(ACTION_OPEN_ALARM)
                    .putExtra(EXTRA_ALARM_ID, id)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(triggerAtMillis, showIntent),
                triggerIntent,
            )
        } else {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                triggerIntent,
            )
        }
    }

    private fun setAlarm(
        alarmManager: AlarmManager,
        triggerAtMillis: Long,
        pendingIntent: PendingIntent,
    ) {
        val canScheduleExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()
        if (canScheduleExact) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        } else {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        }
    }

    private fun cancelPendingAlarm(context: Context, id: Int) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pendingIntent = triggerPendingIntent(context, id)
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun triggerPendingIntent(context: Context, id: Int): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java)
            .setAction(ACTION_TRIGGER)
            .setData(Uri.parse("smarana://alarm/$id"))
            .putExtra(EXTRA_ALARM_ID, id)
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun timeoutPendingIntent(context: Context, id: Int): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java)
            .setAction(ACTION_TIMEOUT)
            .setData(Uri.parse("smarana://alarm/$id/timeout"))
            .putExtra(EXTRA_ALARM_ID, id)
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun startServiceAction(context: Context, action: String, id: Int) {
        val intent = Intent(context, AlarmRingingService::class.java)
            .setAction(action)
            .putExtra(EXTRA_ALARM_ID, id)
        context.startService(intent)
    }

    private fun readConfig(context: Context, id: Int): JSONObject? {
        val encoded = preferences(context).getString(keyFor(id), null) ?: return null
        return try {
            JSONObject(encoded)
        } catch (error: org.json.JSONException) {
            Log.e("TotalRemindersAlarm", "Invalid saved alarm $id.", error)
            null
        }
    }

    private fun nextOccurrence(reminder: JSONObject, afterMillis: Long): Long? {
        val startText = reminder.optString("dateTime")
        val zone = ZoneId.systemDefault()
        val start = try {
            LocalDateTime.parse(startText).atZone(zone)
        } catch (_: DateTimeParseException) {
            try {
                OffsetDateTime.parse(startText).atZoneSameInstant(zone)
            } catch (_: DateTimeParseException) {
                return null
            }
        }
        val after = Instant.ofEpochMilli(afterMillis).atZone(zone)
        val rule = reminder.optJSONObject("recurrenceRule") ?: return null
        val type = rule.optString("type", "none")
        if (type == "none") {
            return null
        }
        val endText = rule.optString("endDate").takeIf { it.isNotEmpty() }
        val endDate = endText?.take(10)?.let {
            try {
                LocalDate.parse(it)
            } catch (_: DateTimeParseException) {
                null
            }
        }
        if (endDate != null && start.toLocalDate().isAfter(endDate)) {
            return null
        }
        val interval = rule.optInt("interval", 1).coerceAtLeast(1)
        val candidate = when (type) {
            "daily" -> nextDaily(start, after, interval)
            "weekly" -> nextWeekly(start, after, rule, interval)
            "monthly" -> nextMonthly(start, after, rule, interval)
            "yearly" -> nextYearly(start, after, rule, interval)
            else -> null
        } ?: return null
        if (endDate != null && candidate.toLocalDate().isAfter(endDate)) {
            return null
        }
        return candidate.toInstant().toEpochMilli()
    }

    private fun nextDaily(
        start: java.time.ZonedDateTime,
        after: java.time.ZonedDateTime,
        interval: Int,
    ): java.time.ZonedDateTime {
        val daysAfterStart = ChronoUnit.DAYS.between(start.toLocalDate(), after.toLocalDate())
        var daysUntil = daysAfterStart +
            ((interval - daysAfterStart % interval) % interval)
        var candidate = start.toLocalDate().plusDays(daysUntil).atTime(start.toLocalTime())
            .atZone(start.zone)
        if (!candidate.isAfter(after)) {
            daysUntil += interval
            candidate = start.toLocalDate().plusDays(daysUntil)
                .atTime(start.toLocalTime()).atZone(start.zone)
        }
        return candidate
    }

    private fun nextWeekly(
        start: java.time.ZonedDateTime,
        after: java.time.ZonedDateTime,
        rule: JSONObject,
        interval: Int,
    ): java.time.ZonedDateTime {
        val weekdayArray = rule.optJSONArray("weekdays")
        val weekdays = mutableSetOf<Int>()
        if (weekdayArray != null) {
            for (index in 0 until weekdayArray.length()) {
                weekdays.add(weekdayArray.optInt(index))
            }
        }
        if (weekdays.isEmpty()) {
            weekdays.add(rule.optInt("dayOfWeek", start.dayOfWeek.value))
        }
        val startDate = start.toLocalDate()
        val startWeek = startDate.minusDays((start.dayOfWeek.value - 1).toLong())
        val afterDate = after.toLocalDate()
        val daysAfterStart = ChronoUnit.DAYS.between(startDate, afterDate)
        val maxDays = interval * 7 + 7
        for (daysUntil in 0..maxDays) {
            val date = afterDate.plusDays(daysUntil.toLong())
            val dayOffset = ChronoUnit.DAYS.between(startDate, date)
            val weekOffset = ChronoUnit.DAYS.between(startWeek, date) / 7
            if (dayOffset < daysAfterStart || dayOffset < 0 ||
                weekOffset % interval != 0L || date.dayOfWeek.value !in weekdays
            ) {
                continue
            }
            val candidate = date.atTime(start.toLocalTime()).atZone(start.zone)
            if (!candidate.isBefore(start) && candidate.isAfter(after)) {
                return candidate
            }
        }
        throw IllegalStateException("Unable to find the next weekly alarm occurrence.")
    }

    private fun nextMonthly(
        start: java.time.ZonedDateTime,
        after: java.time.ZonedDateTime,
        rule: JSONObject,
        interval: Int,
    ): java.time.ZonedDateTime {
        val requestedDay = rule.optInt("dayOfMonth", start.dayOfMonth)
            .takeIf { it in 1..31 } ?: start.dayOfMonth
        val startMonth = start.year * 12 + start.monthValue - 1
        val afterMonth = after.year * 12 + after.monthValue - 1
        var monthsAfterStart = afterMonth - startMonth
        monthsAfterStart += (interval - monthsAfterStart % interval) % interval
        while (true) {
            val targetMonth = start.toLocalDate().withDayOfMonth(1)
                .plusMonths(monthsAfterStart.toLong())
            val day = requestedDay.coerceAtMost(targetMonth.lengthOfMonth())
            val candidate = targetMonth.withDayOfMonth(day)
                .atTime(start.toLocalTime()).atZone(start.zone)
            if (!candidate.isBefore(start) && candidate.isAfter(after)) {
                return candidate
            }
            monthsAfterStart += interval
        }
    }

    private fun nextYearly(
        start: java.time.ZonedDateTime,
        after: java.time.ZonedDateTime,
        rule: JSONObject,
        interval: Int,
    ): java.time.ZonedDateTime {
        var yearsAfterStart = after.year - start.year
        yearsAfterStart += (interval - yearsAfterStart % interval) % interval
        val month = rule.optInt("monthOfYear", start.monthValue)
            .takeIf { it in 1..12 } ?: start.monthValue
        val day = rule.optInt("dayOfMonth", start.dayOfMonth)
            .takeIf { it in 1..31 } ?: start.dayOfMonth
        while (true) {
            val targetMonth = LocalDate.of(start.year + yearsAfterStart, month, 1)
            val candidate = targetMonth.withDayOfMonth(day.coerceAtMost(targetMonth.lengthOfMonth()))
                .atTime(start.toLocalTime()).atZone(start.zone)
            if (!candidate.isBefore(start) && candidate.isAfter(after)) {
                return candidate
            }
            yearsAfterStart += interval
        }
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun keyFor(id: Int) = "$ALARM_PREFIX$id"
}
