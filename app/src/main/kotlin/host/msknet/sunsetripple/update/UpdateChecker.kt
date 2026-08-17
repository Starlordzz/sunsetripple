package host.msknet.sunsetripple.update

sealed interface UpdateState {
    data object Idle : UpdateState
    data object Checking : UpdateState
    data object UpToDate : UpdateState
    data class Available(val versionName: String) : UpdateState
    data class Failed(val message: String) : UpdateState
}

fun interface UpdateSource {
    fun check(): Result<String?>
}

class UpdateChecker(private val source: UpdateSource) {
    var state: UpdateState = UpdateState.Idle
        private set

    fun check(): UpdateState {
        if (state == UpdateState.Checking) return state
        state = UpdateState.Checking
        state = source.check().fold(
            onSuccess = { version ->
                version?.takeIf { it.isNotBlank() }?.let(UpdateState::Available) ?: UpdateState.UpToDate
            },
            onFailure = { error ->
                UpdateState.Failed(error.message ?: "Unable to check for updates")
            },
        )
        return state
    }
}
