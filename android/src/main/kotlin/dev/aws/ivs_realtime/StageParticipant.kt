package dev.aws.ivs_realtime

import com.amazonaws.ivs.broadcast.Stage
import com.amazonaws.ivs.broadcast.StageStream

class StageParticipant(
    val isLocal: Boolean,
    var participantId: String?,
) {
    var publishState: Stage.PublishState = Stage.PublishState.NOT_PUBLISHED
    var subscribeState: Stage.SubscribeState = Stage.SubscribeState.NOT_SUBSCRIBED
    val streams: MutableList<StageStream> = mutableListOf()

    val stableID: String
        get() = if (isLocal) "LocalUser" else requireNotNull(participantId)
}
