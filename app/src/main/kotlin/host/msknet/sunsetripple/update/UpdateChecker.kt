package host.msknet.sunsetripple.update

sealed interface UpdateState {
    data object Idle : UpdateState
    data object Checking : UpdateState
    data object UpToDate : UpdateState
    data class Available(val versionName: String, val summary: String = "") : UpdateState
    data class Downloading(val versionName: String) : UpdateState
    data class ReadyToInstall(val versionName: String) : UpdateState
    data object InstallPermissionRequired : UpdateState
    data object InstallConfirmationOpened : UpdateState
    data object InstallCancelled : UpdateState
    data class Failed(val message: String) : UpdateState
}

fun interface UpdateSource {
    fun check(): Result<String?>
}

sealed interface UpdateActionResult {
    data object Started : UpdateActionResult
    data class Completed(val versionName: String) : UpdateActionResult
    data object PermissionRequired : UpdateActionResult
    data object ConfirmationOpened : UpdateActionResult
    data class Unsupported(val reason: String) : UpdateActionResult
    data class Failed(val message: String) : UpdateActionResult
}

interface UpdateService {
    fun check(): UpdateState
    fun download(): UpdateActionResult
    fun install(): UpdateActionResult
}

class CheckOnlyUpdateService(
    private val checker: UpdateChecker,
) : UpdateService {
    override fun check(): UpdateState = checker.check()

    override fun download(): UpdateActionResult =
        UpdateActionResult.Unsupported("更新下载尚未接入")

    override fun install(): UpdateActionResult =
        UpdateActionResult.Unsupported("更新安装尚未接入")
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
