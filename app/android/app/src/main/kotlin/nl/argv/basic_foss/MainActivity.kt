package nl.argv.basic_foss

import android.content.pm.PackageManager
import android.util.Log
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var previousScreenBrightness: Float? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nl.argv.basic_foss/wear",
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isWearDevice" -> result.success(
                    packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH),
                )
                "getStoredAuthData" -> {
                    val preferences = getSharedPreferences(
                        WearableStateService.PREFERENCES,
                        MODE_PRIVATE,
                    )
                    result.success(
                        mapOf(
                            WearableStateService.KEY_DEVICE_ID to preferences.getString(
                                WearableStateService.KEY_DEVICE_ID,
                                null,
                            ),
                            WearableStateService.KEY_CARD_NUMBER to preferences.getString(
                                WearableStateService.KEY_CARD_NUMBER,
                                null,
                            ),
                        ),
                    )
                }
                "requestAuthState" -> {
                    requestAuthState()
                    result.success(null)
                }
                "publishAuthState" -> {
                    publishAuthState(
                        call.argument<Boolean>("loggedIn") ?: false,
                        call.argument<String>("deviceId"),
                        call.argument<String>("cardNumber"),
                    )
                    result.success(null)
                }
                "setMaxBrightness" -> {
                    if (previousScreenBrightness == null) {
                        previousScreenBrightness = window.attributes.screenBrightness
                    }
                    window.attributes = window.attributes.apply {
                        screenBrightness = 1.0f
                    }
                    result.success(null)
                }
                "restoreBrightness" -> {
                    val brightness = previousScreenBrightness ?: -1.0f
                    window.attributes = window.attributes.apply {
                        screenBrightness = brightness
                    }
                    previousScreenBrightness = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestAuthState() {
        Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { nodes ->
            nodes.forEach { node ->
                Wearable.getMessageClient(this).sendMessage(
                    node.id,
                    WearableStateService.REQUEST_PATH,
                    ByteArray(0),
                ).addOnFailureListener { error ->
                    Log.w(TAG, "Unable to request phone auth state", error)
                }
            }
        }.addOnFailureListener { error ->
            Log.w(TAG, "Unable to find connected Wear OS devices", error)
        }
    }

    private fun publishAuthState(loggedIn: Boolean, deviceId: String?, cardNumber: String?) {
        getSharedPreferences(WearableStateService.PREFERENCES, MODE_PRIVATE).edit()
            .putBoolean(WearableStateService.KEY_LOGGED_IN, loggedIn)
            .putString(WearableStateService.KEY_DEVICE_ID, deviceId)
            .putString(WearableStateService.KEY_CARD_NUMBER, cardNumber)
            .apply()

        val request = PutDataMapRequest.create(WearableStateService.AUTH_PATH)
        request.dataMap.putBoolean(WearableStateService.KEY_LOGGED_IN, loggedIn)
        deviceId?.let {
            request.dataMap.putString(WearableStateService.KEY_DEVICE_ID, it)
        }
        cardNumber?.let {
            request.dataMap.putString(WearableStateService.KEY_CARD_NUMBER, it)
        }
        request.setUrgent()
        Wearable.getDataClient(this)
            .putDataItem(request.asPutDataRequest())
            .addOnFailureListener { error ->
                Log.w(TAG, "Unable to publish auth state", error)
            }
    }

    companion object {
        private const val TAG = "BasicFOSSWear"
    }
}
