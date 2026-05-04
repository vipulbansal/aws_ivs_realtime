package dev.aws.ivs_realtime

import android.content.Context
import android.util.AttributeSet
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.amazonaws.ivs.broadcast.AudioLocalStageStream
import com.amazonaws.ivs.broadcast.AudioStageStream
import com.amazonaws.ivs.broadcast.StageStream
import kotlin.math.roundToInt

class ParticipantItem
@JvmOverloads
constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
    defStyleRes: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr, defStyleRes) {

    private lateinit var previewContainer: FrameLayout
    private lateinit var textViewParticipantId: TextView
    private lateinit var textViewPublish: TextView
    private lateinit var textViewSubscribe: TextView
    private lateinit var textViewVideoMuted: TextView
    private lateinit var textViewAudioMuted: TextView
    private lateinit var textViewAudioLevel: TextView

    private var boundVideoStream: StageStream? = null
    private var audioStreamIdentity: String? = null

    override fun onFinishInflate() {
        super.onFinishInflate()
        previewContainer = findViewById(R.id.participant_preview_container)
        textViewParticipantId = findViewById(R.id.participant_participant_id)
        textViewPublish = findViewById(R.id.participant_publishing)
        textViewSubscribe = findViewById(R.id.participant_subscribed)
        textViewVideoMuted = findViewById(R.id.participant_video_muted)
        textViewAudioMuted = findViewById(R.id.participant_audio_muted)
        textViewAudioLevel = findViewById(R.id.participant_audio_level)
    }

    fun bind(participant: StageParticipant) {
        val participantId =
            if (participant.isLocal) {
                "You (${participant.participantId ?: "Disconnected"})"
            } else {
                participant.participantId
            }
        textViewParticipantId.text = participantId
        textViewPublish.text = participant.publishState.name
        textViewSubscribe.text = participant.subscribeState.name

        val videoStream =
            participant.streams.firstOrNull { it.streamType == StageStream.Type.VIDEO }
        textViewVideoMuted.text =
            if (videoStream != null) {
                if (videoStream.muted) "Video muted" else "Video not muted"
            } else {
                "No video stream"
            }

        val audioStream =
            participant.streams.firstOrNull { it.streamType == StageStream.Type.AUDIO }
        textViewAudioMuted.text =
            if (audioStream != null) {
                if (audioStream.muted) "Audio muted" else "Audio not muted"
            } else {
                "No audio stream"
            }

        val mustRebindVideo =
            videoStream !== boundVideoStream ||
                previewContainer.childCount == 0
        if (videoStream == null) {
            previewContainer.removeAllViews()
            boundVideoStream = null
        } else if (mustRebindVideo) {
            previewContainer.removeAllViews()
            boundVideoStream = videoStream
            val preview = videoStream.preview
            previewContainer.addView(preview)
            preview.layoutParams =
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                )
            previewContainer.post {
                preview.requestLayout()
                preview.invalidate()
                (preview.parent as? View)?.requestLayout()
            }
        }

        val audioKey = audioStream?.device?.descriptor?.urn
        if (audioKey != audioStreamIdentity) {
            when (audioStream) {
                is AudioLocalStageStream ->
                    audioStream.setStatsCallback { _, rms ->
                        textViewAudioLevel.text = "Audio Level: ${rms.roundToInt()} dB"
                    }
                is AudioStageStream ->
                    audioStream.setStatsCallback { _, rms ->
                        textViewAudioLevel.text = "Audio Level: ${rms.roundToInt()} dB"
                    }
                else -> {}
            }
        }
        audioStreamIdentity = audioKey
    }
}
