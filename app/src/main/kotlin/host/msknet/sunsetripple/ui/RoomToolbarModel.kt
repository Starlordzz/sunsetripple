package host.msknet.sunsetripple.ui

enum class RoomAction {
    MUTE,
    SPEAKER,
    LEAVE,
}

data class RoomToolbarItem(
    val action: RoomAction,
    val label: String,
    val selected: Boolean,
    val destructive: Boolean = false,
)

fun roomToolbarItems(
    pushToTalk: Boolean,
    micMuted: Boolean,
    speakerOn: Boolean,
): List<RoomToolbarItem> = buildList {
    if (!pushToTalk) {
        add(
            RoomToolbarItem(
                action = RoomAction.MUTE,
                label = "静音",
                selected = micMuted,
            ),
        )
    }
    add(
        RoomToolbarItem(
            action = RoomAction.SPEAKER,
            label = "扬声器",
            selected = speakerOn,
        ),
    )
    add(
        RoomToolbarItem(
            action = RoomAction.LEAVE,
            label = "离开",
            selected = false,
            destructive = true,
        ),
    )
}
