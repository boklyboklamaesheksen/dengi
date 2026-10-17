package app.rabochiy.vpn.play

import android.app.Activity
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.google.android.gms.common.api.ApiException
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallException
import com.google.android.play.core.install.InstallState
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.ActivityResult
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import com.google.android.play.core.review.ReviewException
import com.google.android.play.core.review.ReviewManager
import com.google.android.play.core.review.ReviewManagerFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Google Play In-App Review and In-App Updates for the Flutter side.
 *
 * Only talks to Play; when to ask is decided in Dart
 * (lib/services/in_app_review_service.dart, in_app_update_service.dart).
 * Create it while the activity is being constructed: the update-flow
 * launcher must be registered before the activity reaches STARTED.
 */
class PlayStoreBridge(private val activity: ComponentActivity) {

    companion object {
        const val METHOD_CHANNEL = "app.rabochiy.vpn/play_store"
        const val UPDATE_EVENT_CHANNEL = "app.rabochiy.vpn/play_store/update_state"
        private const val TAG = "PlayStoreBridge"
    }

    // Lazy: the activity has no application context yet during construction.
    private val reviewManager: ReviewManager by lazy {
        ReviewManagerFactory.create(activity.applicationContext)
    }
    private val updateManager: AppUpdateManager by lazy {
        AppUpdateManagerFactory.create(activity.applicationContext)
    }

    private var reviewInFlight = false
    private var pendingUpdateFlow: MethodChannel.Result? = null
    private var updateSink: EventChannel.EventSink? = null
    private var installListenerRegistered = false
    private var disposed = false

    private val installListener = InstallStateUpdatedListener { state ->
        val event = state.toMap()
        activity.runOnUiThread { updateSink?.success(event) }
    }

    private val updateFlowLauncher: ActivityResultLauncher<IntentSenderRequest> =
        activity.registerForActivityResult(
            ActivityResultContracts.StartIntentSenderForResult()
        ) { result ->
            finishUpdateFlow(
                when (result.resultCode) {
                    Activity.RESULT_OK -> "accepted"
                    Activity.RESULT_CANCELED -> "canceled"
                    ActivityResult.RESULT_IN_APP_UPDATE_FAILED -> "failed"
                    else -> "failed"
                }
            )
        }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            onMethodCall(call, result)
        }
        EventChannel(messenger, UPDATE_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    updateSink = events
                    registerInstallListener()
                }

                override fun onCancel(arguments: Any?) {
                    updateSink = null
                    unregisterInstallListener()
                }
            }
        )
    }

    fun dispose() {
        disposed = true
        updateSink = null
        unregisterInstallListener()
        finishUpdateFlow("canceled")
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestReview" -> requestReview(result)
            "getUpdateInfo" -> getUpdateInfo(result)
            "startUpdate" -> startUpdate(call.argument<String>("type"), result)
            "completeUpdate" -> completeUpdate(result)
            else -> result.notImplemented()
        }
    }

    // ── In-app review ──────────────────────────────────────────────────

    private fun requestReview(result: MethodChannel.Result) {
        if (reviewInFlight) {
            result.success("busy")
            return
        }
        reviewInFlight = true
        try {
            reviewManager.requestReviewFlow().addOnCompleteListener { request ->
                if (!request.isSuccessful || !isActivityUsable()) {
                    Log.w(TAG, "Review flow unavailable: ${errorCodeOf(request.exception)}")
                    finishReview(result, "unavailable")
                    return@addOnCompleteListener
                }
                try {
                    reviewManager.launchReviewFlow(activity, request.result)
                        .addOnCompleteListener {
                            // Play never says whether the card was shown or a
                            // review was left, so there is nothing else to report.
                            finishReview(result, "completed")
                        }
                } catch (e: Exception) {
                    Log.w(TAG, "Review flow could not be launched", e)
                    finishReview(result, "unavailable")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Review flow could not be requested", e)
            finishReview(result, "unavailable")
        }
    }

    private fun finishReview(result: MethodChannel.Result, outcome: String) {
        reviewInFlight = false
        deliver { result.success(outcome) }
    }

    // ── In-app updates ─────────────────────────────────────────────────

    private fun getUpdateInfo(result: MethodChannel.Result) {
        try {
            updateManager.appUpdateInfo.addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    deliver { result.success(task.result.toMap()) }
                } else {
                    // Expected for builds not installed from Google Play
                    // (debug, sideloaded APK, account that does not own the app).
                    deliver {
                        result.error(
                            "UPDATE_INFO_UNAVAILABLE",
                            errorCodeOf(task.exception).toString(),
                            null,
                        )
                    }
                }
            }
        } catch (e: Exception) {
            result.error("UPDATE_INFO_UNAVAILABLE", e.message, null)
        }
    }

    private fun startUpdate(type: String?, result: MethodChannel.Result) {
        val updateType = when (type) {
            "flexible" -> AppUpdateType.FLEXIBLE
            "immediate" -> AppUpdateType.IMMEDIATE
            else -> {
                result.error("BAD_ARGS", "Unknown update type: $type", null)
                return
            }
        }
        if (pendingUpdateFlow != null) {
            result.success("busy")
            return
        }
        pendingUpdateFlow = result
        try {
            // An AppUpdateInfo can start a flow only once: always use a fresh one.
            updateManager.appUpdateInfo.addOnCompleteListener { task ->
                if (!task.isSuccessful) {
                    finishUpdateFlow("unavailable")
                    return@addOnCompleteListener
                }
                val info = task.result
                val options = AppUpdateOptions.defaultOptions(updateType)
                val availability = info.updateAvailability()
                // An immediate update the user already accepted is resumed
                // exactly as in Google's sample, without the type check.
                val resumingImmediate = updateType == AppUpdateType.IMMEDIATE &&
                    availability == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
                val allowed = resumingImmediate ||
                    (availability == UpdateAvailability.UPDATE_AVAILABLE &&
                        info.isUpdateTypeAllowed(options))
                if (!allowed || !isActivityUsable()) {
                    finishUpdateFlow("not_allowed")
                    return@addOnCompleteListener
                }
                val started = try {
                    updateManager.startUpdateFlowForResult(info, updateFlowLauncher, options)
                } catch (e: Exception) {
                    Log.w(TAG, "Update flow could not be started", e)
                    false
                }
                if (!started) finishUpdateFlow("failed")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Update info could not be requested", e)
            finishUpdateFlow("unavailable")
        }
    }

    private fun completeUpdate(result: MethodChannel.Result) {
        try {
            updateManager.completeUpdate().addOnCompleteListener { task ->
                // On success Play restarts the app, so this rarely arrives.
                deliver {
                    if (task.isSuccessful) {
                        result.success(true)
                    } else {
                        result.error(
                            "COMPLETE_UPDATE_FAILED",
                            errorCodeOf(task.exception).toString(),
                            null,
                        )
                    }
                }
            }
        } catch (e: Exception) {
            result.error("COMPLETE_UPDATE_FAILED", e.message, null)
        }
    }

    private fun finishUpdateFlow(outcome: String) {
        val pending = pendingUpdateFlow ?: return
        pendingUpdateFlow = null
        deliver { pending.success(outcome) }
    }

    private fun registerInstallListener() {
        if (installListenerRegistered || disposed) return
        updateManager.registerListener(installListener)
        installListenerRegistered = true
    }

    private fun unregisterInstallListener() {
        if (!installListenerRegistered) return
        updateManager.unregisterListener(installListener)
        installListenerRegistered = false
    }

    // ── Helpers ────────────────────────────────────────────────────────

    private fun isActivityUsable(): Boolean =
        !disposed && !activity.isFinishing && !activity.isDestroyed

    /** The Flutter engine may already be gone when a Play task completes. */
    private inline fun deliver(block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            Log.w(TAG, "Result could not be delivered to Flutter", e)
        }
    }

    private fun errorCodeOf(error: Exception?): Int = when (error) {
        is InstallException -> error.errorCode
        is ReviewException -> error.errorCode
        is ApiException -> error.statusCode
        else -> 0
    }

    private fun AppUpdateInfo.toMap(): Map<String, Any?> = mapOf(
        "updateAvailability" to updateAvailability(),
        "installStatus" to installStatus(),
        "availableVersionCode" to availableVersionCode(),
        "updatePriority" to updatePriority(),
        "clientVersionStalenessDays" to clientVersionStalenessDays(),
        "flexibleAllowed" to isUpdateTypeAllowed(
            AppUpdateOptions.defaultOptions(AppUpdateType.FLEXIBLE)
        ),
        "immediateAllowed" to isUpdateTypeAllowed(
            AppUpdateOptions.defaultOptions(AppUpdateType.IMMEDIATE)
        ),
    )

    private fun InstallState.toMap(): Map<String, Any> = mapOf(
        "installStatus" to installStatus(),
        "installErrorCode" to installErrorCode(),
        "bytesDownloaded" to bytesDownloaded(),
        "totalBytesToDownload" to totalBytesToDownload(),
    )
}
