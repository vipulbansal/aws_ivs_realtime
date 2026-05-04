package dev.aws.ivs_realtime

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView

class ParticipantAdapter : RecyclerView.Adapter<ParticipantAdapter.ViewHolder>() {

    private val participants = mutableListOf<StageParticipant>()
    private var showParticipantStateOverlay: Boolean = false

    init {
        setHasStableIds(true)
    }

    fun setShowParticipantStateOverlay(show: Boolean) {
        if (showParticipantStateOverlay == show) return
        showParticipantStateOverlay = show
        notifyDataSetChanged()
    }

    fun ensureLocalParticipant() {
        if (participants.any { it.isLocal }) return
        participants.add(0, StageParticipant(true, null))
        notifyItemInserted(0)
    }

    fun removeLocalParticipant() {
        val index = participants.indexOfFirst { it.isLocal }
        if (index == -1) return
        participants.removeAt(index)
        notifyItemRemoved(index)
    }

    fun updateLocalParticipant(update: (StageParticipant) -> Unit) {
        val index = participants.indexOfFirst { it.isLocal }
        if (index == -1) return
        update(participants[index])
        notifyItemChanged(index)
    }

    fun participantJoined(participant: StageParticipant) {
        participants.add(participant)
        notifyItemInserted(participants.size - 1)
    }

    fun participantLeft(participantId: String) {
        val index = participants.indexOfFirst { it.participantId == participantId }
        if (index == -1) return
        participants.removeAt(index)
        notifyItemRemoved(index)
    }

    fun participantUpdated(participantId: String?, update: (StageParticipant) -> Unit) {
        val index =
            if (participantId != null) {
                participants.indexOfFirst { it.participantId == participantId }
            } else {
                participants.indexOfFirst { it.isLocal }
            }
        if (index == -1) return
        update(participants[index])
        notifyItemChanged(index)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val item =
            LayoutInflater.from(parent.context)
                .inflate(R.layout.item_stage_participant, parent, false) as ParticipantItem
        return ViewHolder(item)
    }

    override fun getItemCount(): Int = participants.size

    override fun getItemId(position: Int): Long =
        participants[position].stableID.hashCode().toLong()

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.participantItem.bind(participants[position], showParticipantStateOverlay)
    }

    class ViewHolder(
        val participantItem: ParticipantItem,
    ) : RecyclerView.ViewHolder(participantItem)
}
