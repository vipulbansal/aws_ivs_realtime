package dev.aws.ivs_realtime

import android.content.Context
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

/**
 * Vertical list of stage tiles; each visible child gets an equal share of the
 * [RecyclerView] height (matches the iOS “stacked” layout behavior).
 */
class StageLayoutManager(
    context: Context,
) : LinearLayoutManager(context, VERTICAL, false) {

    override fun onLayoutChildren(recycler: RecyclerView.Recycler?, state: RecyclerView.State?) {
        super.onLayoutChildren(recycler, state)
        applyEqualTileHeights()
    }

    private fun applyEqualTileHeights() {
        if (itemCount == 0 || height <= 0) return
        val itemHeight = height / itemCount
        var changed = false
        for (i in 0 until childCount) {
            val child = getChildAt(i) ?: continue
            val lp = child.layoutParams as RecyclerView.LayoutParams
            if (lp.height != itemHeight) {
                lp.height = itemHeight
                child.layoutParams = lp
                changed = true
            }
        }
        if (changed) {
            requestLayout()
        }
    }

    override fun canScrollVertically(): Boolean = false
}
