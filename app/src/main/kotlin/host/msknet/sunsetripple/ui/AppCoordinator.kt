package host.msknet.sunsetripple.ui

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class AppUiState(
    val nickname: String,
    val status: String? = null,
    val roomRole: RoomRole = RoomRole.NONE,
    val isHost: Boolean = false,
    val speakerOn: Boolean = true,
)

class AppCoordinator(initialNickname: String) {
    private val _state = MutableStateFlow(AppUiState(nickname = initialNickname))
    val state: StateFlow<AppUiState> = _state.asStateFlow()

    fun setNickname(nickname: String) = update { copy(nickname = nickname.take(16)) }
    fun setStatus(status: String?) = update { copy(status = status) }
    fun setRoomRole(role: RoomRole) = update { copy(roomRole = role) }
    fun setHost(host: Boolean) = update { copy(isHost = host) }
    fun setSpeaker(on: Boolean) = update { copy(speakerOn = on) }

    fun resetRoom(status: String?) = update {
        copy(status = status, roomRole = RoomRole.NONE, isHost = false)
    }

    private fun update(transform: AppUiState.() -> AppUiState) {
        _state.value = _state.value.transform()
    }
}
