package com.arcdash.arcdash

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class MacroDroidReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_APPLY_STREET_LEGAL = "com.arcdash.arcdash.APPLY_STREET_LEGAL"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_APPLY_STREET_LEGAL) {
            MainActivity.onMacroDroidBroadcast(context, ACTION_APPLY_STREET_LEGAL)
        }
    }
}
