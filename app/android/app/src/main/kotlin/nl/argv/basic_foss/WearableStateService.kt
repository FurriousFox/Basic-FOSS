package nl.argv.basic_foss

import android.content.Context
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService

class WearableStateService : WearableListenerService() {
    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path == REQUEST_PATH) {
            publishStoredState()
        }
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        dataEvents.forEach { event ->
            if (event.type != DataEvent.TYPE_CHANGED) return@forEach
            when (event.dataItem.uri.path) {
                AUTH_PATH -> {
                    val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
                    getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
                        .putBoolean(KEY_LOGGED_IN, dataMap.getBoolean(KEY_LOGGED_IN, false))
                        .putString(KEY_DEVICE_ID, dataMap.getString(KEY_DEVICE_ID))
                        .putString(KEY_CARD_NUMBER, dataMap.getString(KEY_CARD_NUMBER))
                        .apply()
                }
                REQUEST_PATH -> publishStoredState()
            }
        }
    }

    private fun publishStoredState() {
        val preferences = getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val request = PutDataMapRequest.create(AUTH_PATH)
        request.dataMap.putBoolean(
            KEY_LOGGED_IN,
            preferences.getBoolean(KEY_LOGGED_IN, false),
        )
        request.dataMap.putString(KEY_DEVICE_ID, preferences.getString(KEY_DEVICE_ID, null))
        request.dataMap.putString(KEY_CARD_NUMBER, preferences.getString(KEY_CARD_NUMBER, null))
        request.setUrgent()
        Wearable.getDataClient(this).putDataItem(request)
    }

    companion object {
        const val AUTH_PATH = "/basic-foss/auth"
        const val REQUEST_PATH = "/basic-foss/request"
        const val PREFERENCES = "wear_state"
        const val KEY_LOGGED_IN = "loggedIn"
        const val KEY_DEVICE_ID = "deviceId"
        const val KEY_CARD_NUMBER = "cardNumber"
    }
}
