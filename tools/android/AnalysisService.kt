package PLACEHOLDER

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Servicio en primer plano que mantiene viva la app mientras se analizan
 * canciones y muestra el progreso en una notificacion. Solo existe mientras
 * dura el analisis: Dart lo inicia al empezar y lo detiene al terminar.
 */
class AnalysisService : Service() {

    companion object {
        const val CHANNEL_ID = "aztra_analysis"
        const val NOTIF_ID = 4711
        const val DONE_NOTIF_ID = 4712

        @Volatile
        var instance: AnalysisService? = null
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var started = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Analizando…"
        val text = intent?.getStringExtra("text") ?: ""
        val progress = intent?.getIntExtra("progress", -1) ?: -1
        val max = intent?.getIntExtra("max", 0) ?: 0
        val notification = buildNotification(title, text, progress, max, true)

        if (!started) {
            started = true
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIF_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } else {
                    startForeground(NOTIF_ID, notification)
                }
            } catch (e: Exception) {
                stopSelf()
                return START_NOT_STICKY
            }
            acquireWakeLock()
        } else {
            notificationManager().notify(NOTIF_ID, notification)
        }
        return START_NOT_STICKY
    }

    /** Actualiza el texto y la barra de progreso de la notificacion. */
    fun update(title: String, text: String, progress: Int, max: Int) {
        if (!started) return
        notificationManager().notify(
            NOTIF_ID,
            buildNotification(title, text, progress, max, true)
        )
    }

    /** Quita la notificacion de progreso, avisa que termino y detiene el servicio. */
    fun finishWith(title: String, text: String) {
        val done = buildNotification(title, text, -1, 0, false)
        stopForeground(Service.STOP_FOREGROUND_REMOVE)
        notificationManager().notify(DONE_NOTIF_ID, done)
        stopSelf()
    }

    override fun onDestroy() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {
        }
        wakeLock = null
        instance = null
        super.onDestroy()
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Análisis de audio",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Progreso del análisis de tu biblioteca"
            notificationManager().createNotificationChannel(channel)
        }
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "aztra:analysis").apply {
            setReferenceCounted(false)
            acquire(6 * 60 * 60 * 1000L)
        }
    }

    private fun buildNotification(
        title: String,
        text: String,
        progress: Int,
        max: Int,
        ongoing: Boolean
    ): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val iconId = resources.getIdentifier("ic_stat_aztra", "drawable", packageName)
        builder.setSmallIcon(if (iconId != 0) iconId else android.R.drawable.stat_notify_sync)
            .setContentTitle(title)
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)

        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            val pending = PendingIntent.getActivity(
                this,
                0,
                launch,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            builder.setContentIntent(pending)
        }

        if (ongoing) {
            if (max > 0 && progress >= 0) {
                builder.setProgress(max, progress, false)
            } else {
                builder.setProgress(0, 0, true)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
        }
        return builder.build()
    }
}
