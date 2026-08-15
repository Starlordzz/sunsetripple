package host.msknet.sunsetripple.ui

object HomeRoomAvailability {
    val visibleRoomKinds: Set<RoomKind> = setOf(RoomKind.WIFI, RoomKind.BLUETOOTH)

    fun isVisible(kind: RoomKind): Boolean = kind in visibleRoomKinds
}
