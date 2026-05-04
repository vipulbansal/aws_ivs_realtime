package dev.aws.ivs_realtime

import android.content.Context
import android.view.View
import androidx.recyclerview.widget.RecyclerView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class IvsStageViewFactory(
    private val controllerProvider: () -> IvsStageController,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val recycler = RecyclerView(context)
        recycler.layoutManager = StageLayoutManager(context)
        recycler.adapter = controllerProvider().participantAdapter
        return object : PlatformView {
            override fun getView(): View = recycler

            override fun dispose() {
                // Stage lifecycle is owned by the plugin / activity.
            }
        }
    }
}
