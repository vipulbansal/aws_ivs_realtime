package dev.aws.ivs_realtime

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class AwsIvsRealtimePlugin : FlutterPlugin, ActivityAware {

    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private var methodChannel: MethodChannel? = null
    private var stageEventChannel: EventChannel? = null
    private var stageEventSink: EventChannel.EventSink? = null
    private var controller: IvsStageController? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var permissionsListener: PluginRegistry.RequestPermissionsResultListener? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            IvsStageViewFactory { controller ?: error("Activity not attached yet") },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        stageEventChannel?.setStreamHandler(null)
        stageEventChannel = null
        stageEventSink = null
        flutterPluginBinding = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        val act = binding.activity
        val messenger = flutterPluginBinding!!.binaryMessenger

        stageEventChannel =
            EventChannel(messenger, EVENTS_CHANNEL).also { ec ->
                ec.setStreamHandler(
                    object : EventChannel.StreamHandler {
                        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                            stageEventSink = events
                        }

                        override fun onCancel(arguments: Any?) {
                            stageEventSink = null
                        }
                    },
                )
            }

        val c =
            IvsStageController(act) { map ->
                stageEventSink?.success(map)
            }
        controller = c
        val listener =
            PluginRegistry.RequestPermissionsResultListener { requestCode, permissions, grantResults ->
                c.onRequestPermissionsResult(requestCode, permissions, grantResults)
            }
        permissionsListener = listener
        binding.addRequestPermissionsResultListener(listener)
        methodChannel =
            MethodChannel(messenger, CHANNEL).also { ch ->
                ch.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "join" -> {
                            val args = call.arguments as? Map<*, *>
                            val token = args?.get("token") as? String ?: ""
                            val publish = channelBoolean(args?.get("publish"), default = true)
                            c.setPublishEnabled(publish)
                            c.joinOrLeave(token, result)
                        }
                        "leave" -> {
                            c.leave()
                            result.success(null)
                        }
                        "setPublish" -> {
                            val enabled = channelBoolean(call.arguments, default = true)
                            c.setPublishEnabled(enabled)
                            result.success(null)
                        }
                        "refreshStageBindings" -> {
                            c.refreshStageBindings()
                            result.success(null)
                        }
                        "setLocalStreamMuted" -> {
                            val m = call.arguments as? Map<*, *>
                            val mic = m?.get("micMuted") as? Boolean ?: false
                            val cam = m?.get("cameraMuted") as? Boolean ?: false
                            c.setLocalStreamMuted(micMuted = mic, cameraMuted = cam)
                            result.success(null)
                        }
                        "setShowParticipantStateOverlay" -> {
                            val m = call.arguments as? Map<*, *>
                            val visible = channelBoolean(m?.get("visible"), default = false)
                            c.setShowParticipantStateOverlay(visible)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        val binding = activityBinding
        val listener = permissionsListener
        if (binding != null && listener != null) {
            binding.removeRequestPermissionsResultListener(listener)
        }
        activityBinding = null
        permissionsListener = null
        controller?.release()
        controller = null
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        stageEventChannel?.setStreamHandler(null)
        stageEventChannel = null
        stageEventSink = null
    }

    private fun channelBoolean(value: Any?, default: Boolean): Boolean =
        when (value) {
            is Boolean -> value
            is Number -> value.toInt() != 0
            null -> default
            else -> default
        }

    companion object {
        const val CHANNEL = "aws_ivs_realtime/stage"
        const val EVENTS_CHANNEL = "aws_ivs_realtime/stage_events"
        const val VIEW_TYPE = "ivs_stage_view"
    }
}
