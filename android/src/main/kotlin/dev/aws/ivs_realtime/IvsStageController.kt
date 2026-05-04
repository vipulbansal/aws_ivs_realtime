package dev.aws.ivs_realtime

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.amazonaws.ivs.broadcast.AudioLocalStageStream
import com.amazonaws.ivs.broadcast.Bluetooth
import com.amazonaws.ivs.broadcast.BroadcastException
import com.amazonaws.ivs.broadcast.Device
import com.amazonaws.ivs.broadcast.DeviceDiscovery
import com.amazonaws.ivs.broadcast.ImageLocalStageStream
import com.amazonaws.ivs.broadcast.LocalStageStream
import com.amazonaws.ivs.broadcast.ParticipantInfo
import com.amazonaws.ivs.broadcast.Stage
import com.amazonaws.ivs.broadcast.StageRenderer
import com.amazonaws.ivs.broadcast.StageStream
import io.flutter.plugin.common.MethodChannel

class IvsStageController(
    private val activity: android.app.Activity,
    private val emitStageEvent: (Map<String, Any>) -> Unit = {},
) : Stage.Strategy, StageRenderer {

    val participantAdapter = ParticipantAdapter()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val app: Application = activity.application as Application

    private var deviceDiscovery: DeviceDiscovery? = null
    private var stage: Stage? = null
    private val streams = mutableListOf<LocalStageStream>()
    private var publishEnabled: Boolean = true

    private var connectionState: Stage.ConnectionState = Stage.ConnectionState.DISCONNECTED
    private var wasConnectedThisSession: Boolean = false
    private var suppressDisconnectEvent: Boolean = false

    private var pendingJoinToken: String? = null
    private var pendingJoinResult: MethodChannel.Result? = null

    init {
        deviceDiscovery = DeviceDiscovery(app)
    }

    fun setPublishEnabled(enabled: Boolean) {
        val changed = publishEnabled != enabled
        publishEnabled = enabled
        stage?.refreshStrategy()
        if (!changed) return
        if (enabled) {
            permissionGranted()
        } else {
            participantAdapter.updateLocalParticipant {
                it.streams.clear()
            }
            participantAdapter.removeLocalParticipant()
        }
    }

    fun joinOrLeave(token: String, result: MethodChannel.Result) {
        mainHandler.post {
            if (connectionState != Stage.ConnectionState.DISCONNECTED) {
                suppressDisconnectEvent = true
                leaveInternal()
                result.success(null)
                return@post
            }
            if (token.isEmpty()) {
                result.error("INVALID_ARGUMENT", "Empty token", null)
                return@post
            }
            pendingJoinToken = token
            pendingJoinResult = result
            val perms = permissionsForJoin()
            if (hasPermissions(perms)) {
                if (performJoin(token)) finishJoinSuccess()
            } else {
                ActivityCompat.requestPermissions(
                    activity,
                    perms.toTypedArray(),
                    REQUEST_JOIN_PERMISSIONS,
                )
            }
        }
    }

    /** @return true if consumed */
    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_JOIN_PERMISSIONS) return false
        val ok =
            grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        val token = pendingJoinToken
        val res = pendingJoinResult
        if (!ok) {
            res?.error(
                "PERMISSION_DENIED",
                "Microphone (and camera if publishing) permission is required.",
                null,
            )
            pendingJoinToken = null
            pendingJoinResult = null
            return true
        }
        if (token != null) {
            mainHandler.post {
                if (performJoin(token)) {
                    res?.success(null)
                }
                pendingJoinToken = null
                pendingJoinResult = null
            }
        }
        return true
    }

    private fun finishJoinSuccess() {
        pendingJoinResult?.success(null)
        pendingJoinToken = null
        pendingJoinResult = null
    }

    private fun permissionsForJoin(): List<String> {
        val list = mutableListOf<String>()
        list.add(Manifest.permission.RECORD_AUDIO)
        if (publishEnabled) {
            list.add(Manifest.permission.CAMERA)
        }
        return list
    }

    private fun hasPermissions(permissions: List<String>): Boolean =
        permissions.all {
            ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
        }

    fun refreshStageBindings() {
        mainHandler.post {
            try {
                stage?.refreshStrategy()
            } catch (_: Exception) {
            }
            participantAdapter.notifyDataSetChanged()
        }
    }

    fun setShowParticipantStateOverlay(show: Boolean) {
        mainHandler.post {
            participantAdapter.setShowParticipantStateOverlay(show)
        }
    }

    fun setLocalStreamMuted(micMuted: Boolean, cameraMuted: Boolean) {
        mainHandler.post {
            for (stream in streams) {
                when (stream) {
                    is AudioLocalStageStream -> stream.setMuted(micMuted)
                    is ImageLocalStageStream -> stream.setMuted(cameraMuted)
                }
            }
        }
    }

    fun leave() {
        mainHandler.post {
            suppressDisconnectEvent = true
            leaveInternal()
        }
    }

    private fun leaveInternal() {
        try {
            stage?.leave()
        } catch (_: Exception) {
        }
    }

    fun release() {
        mainHandler.post {
            suppressDisconnectEvent = true
            stage?.release()
            stage = null
            deviceDiscovery?.release()
            deviceDiscovery = null
            Bluetooth.stopBluetoothSco(app)
        }
    }

    private fun performJoin(token: String): Boolean {
        return try {
            Bluetooth.startBluetoothSco(app)
            try {
                stage?.release()
            } catch (_: Exception) {
            }
            stage = null
            // Rebuild local camera/mic streams only after the previous stage is released.
            // Otherwise new ImageLocalStageStream previews can stay black on rejoin while
            // publish still works for remotes.
            permissionGranted()
            val newStage = Stage(app, token, this)
            newStage.addRenderer(this)
            newStage.join()
            stage = newStage
            mainHandler.post {
                if (this@IvsStageController.stage !== newStage) return@post
                try {
                    newStage.refreshStrategy()
                } catch (_: Exception) {
                }
                participantAdapter.notifyDataSetChanged()
            }
            true
        } catch (e: BroadcastException) {
            Log.e(TAG, "join failed", e)
            Toast.makeText(app, "Failed to join: ${e.localizedMessage}", Toast.LENGTH_LONG).show()
            pendingJoinResult?.error("JOIN_FAILED", e.localizedMessage, null)
            pendingJoinToken = null
            pendingJoinResult = null
            false
        }
    }

    internal fun permissionGranted() {
        val discovery = deviceDiscovery ?: return
        streams.clear()
        if (publishEnabled) {
            val devices = discovery.listLocalDevices()
            devices
                .filter { it.descriptor.type == Device.Descriptor.DeviceType.CAMERA }
                .maxByOrNull { it.descriptor.position == Device.Descriptor.Position.FRONT }
                ?.let { streams.add(ImageLocalStageStream(it)) }
            devices
                .filter { it.descriptor.type == Device.Descriptor.DeviceType.MICROPHONE }
                .maxByOrNull { it.descriptor.isDefault }
                ?.let { streams.add(AudioLocalStageStream(it)) }
            participantAdapter.ensureLocalParticipant()
            participantAdapter.updateLocalParticipant {
                it.streams.clear()
                it.streams.addAll(streams)
            }
        } else {
            participantAdapter.updateLocalParticipant {
                it.streams.clear()
            }
            participantAdapter.removeLocalParticipant()
        }

        stage?.refreshStrategy()
    }

    override fun stageStreamsToPublishForParticipant(
        stage: Stage,
        participantInfo: ParticipantInfo,
    ): MutableList<LocalStageStream> =
        if (publishEnabled) streams else mutableListOf()

    override fun shouldPublishFromParticipant(stage: Stage, participantInfo: ParticipantInfo): Boolean =
        publishEnabled

    override fun shouldSubscribeToParticipant(
        stage: Stage,
        participantInfo: ParticipantInfo,
    ): Stage.SubscribeType = Stage.SubscribeType.AUDIO_VIDEO

    override fun onError(exception: BroadcastException) {
        Log.e(TAG, "onError", exception)
        mainHandler.post {
            Toast.makeText(app, exception.localizedMessage, Toast.LENGTH_LONG).show()
            // Host may delete the stage while viewers are still connected; some failures surface
            // here without a separate DISCONNECTED transition, so mirror disconnect signaling.
            if (wasConnectedThisSession && !suppressDisconnectEvent) {
                wasConnectedThisSession = false
                try {
                    Bluetooth.stopBluetoothSco(app)
                } catch (_: Exception) {
                }
                emitStageEvent(mapOf("event" to "disconnected"))
            }
        }
    }

    override fun onConnectionStateChanged(
        stage: Stage,
        connectionState: Stage.ConnectionState,
        exception: BroadcastException?,
    ) {
        this.connectionState = connectionState
        if (connectionState == Stage.ConnectionState.CONNECTED) {
            wasConnectedThisSession = true
            mainHandler.post {
                if (this@IvsStageController.stage != stage) return@post
                try {
                    stage.refreshStrategy()
                } catch (_: Exception) {
                }
                participantAdapter.notifyDataSetChanged()
            }
        } else if (connectionState == Stage.ConnectionState.DISCONNECTED) {
            Bluetooth.stopBluetoothSco(app)
            val shouldEmit = wasConnectedThisSession && !suppressDisconnectEvent
            wasConnectedThisSession = false
            suppressDisconnectEvent = false
            if (shouldEmit) {
                mainHandler.post {
                    emitStageEvent(mapOf("event" to "disconnected"))
                }
            }
        }
    }

    override fun onParticipantJoined(stage: Stage, participantInfo: ParticipantInfo) {
        if (participantInfo.isLocal) {
            if (!publishEnabled) return
            participantAdapter.ensureLocalParticipant()
            participantAdapter.updateLocalParticipant {
                it.participantId = participantInfo.participantId
            }
        } else {
            participantAdapter.participantJoined(
                StageParticipant(
                    participantInfo.isLocal,
                    participantInfo.participantId,
                ),
            )
        }
    }

    override fun onParticipantLeft(stage: Stage, participantInfo: ParticipantInfo) {
        if (participantInfo.isLocal) {
            if (publishEnabled) {
                participantAdapter.participantUpdated(participantInfo.participantId) {
                    it.participantId = null
                }
            }
        } else {
            participantAdapter.participantLeft(participantInfo.participantId)
        }
    }

    override fun onParticipantPublishStateChanged(
        stage: Stage,
        participantInfo: ParticipantInfo,
        publishState: Stage.PublishState,
    ) {
        participantAdapter.participantUpdated(participantInfo.participantId) {
            it.publishState = publishState
        }
    }

    override fun onParticipantSubscribeStateChanged(
        stage: Stage,
        participantInfo: ParticipantInfo,
        subscribeState: Stage.SubscribeState,
    ) {
        participantAdapter.participantUpdated(participantInfo.participantId) {
            it.subscribeState = subscribeState
        }
    }

    override fun onStreamsAdded(
        stage: Stage,
        participantInfo: ParticipantInfo,
        added: MutableList<StageStream>,
    ) {
        if (participantInfo.isLocal) return
        participantAdapter.participantUpdated(participantInfo.participantId) {
            it.streams.addAll(added)
        }
    }

    override fun onStreamsRemoved(
        stage: Stage,
        participantInfo: ParticipantInfo,
        removed: MutableList<StageStream>,
    ) {
        if (participantInfo.isLocal) return
        participantAdapter.participantUpdated(participantInfo.participantId) {
            it.streams.removeAll(removed.toSet())
        }
    }

    override fun onStreamsMutedChanged(
        stage: Stage,
        participantInfo: ParticipantInfo,
        changed: MutableList<StageStream>,
    ) {
        if (participantInfo.isLocal) return
        participantAdapter.participantUpdated(participantInfo.participantId) { }
    }

    companion object {
        private const val TAG = "IvsStageController"
        private const val REQUEST_JOIN_PERMISSIONS = 0x4956_5301
    }
}
