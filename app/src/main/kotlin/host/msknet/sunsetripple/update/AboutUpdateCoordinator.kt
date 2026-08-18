package host.msknet.sunsetripple.update

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AboutUpdateCoordinator(
    private val updateService: UpdateService,
    private val execute: ((() -> Unit) -> Unit) = { task -> task() },
    private val isCallActive: () -> Boolean = { false },
) {
    private val _state = MutableStateFlow<UpdateState>(UpdateState.Idle)
    val state: StateFlow<UpdateState> = _state.asStateFlow()

    fun check() {
        if (isCallActive()) {
            _state.value = UpdateState.Failed("通话期间不会检查更新")
            return
        }
        _state.value = UpdateState.Checking
        execute { _state.value = updateService.check() }
    }

    fun download() {
        val available = _state.value as? UpdateState.Available ?: return
        if (isCallActive()) {
            _state.value = UpdateState.Failed("通话期间不会下载更新")
            return
        }
        _state.value = UpdateState.Downloading(available.versionName)
        execute {
            _state.value = when (val result = updateService.download()) {
                is UpdateActionResult.Completed -> UpdateState.ReadyToInstall(result.versionName)
                is UpdateActionResult.Failed -> UpdateState.Failed(result.message)
                is UpdateActionResult.Unsupported -> UpdateState.Failed(result.reason)
                UpdateActionResult.Started -> UpdateState.Downloading(available.versionName)
                UpdateActionResult.PermissionRequired -> UpdateState.InstallPermissionRequired
                UpdateActionResult.ConfirmationOpened -> UpdateState.InstallConfirmationOpened
            }
        }
    }

    fun install() {
        execute {
            _state.value = when (val result = updateService.install()) {
                UpdateActionResult.PermissionRequired -> UpdateState.InstallPermissionRequired
                UpdateActionResult.ConfirmationOpened -> UpdateState.InstallConfirmationOpened
                is UpdateActionResult.Failed -> UpdateState.Failed(result.message)
                is UpdateActionResult.Unsupported -> UpdateState.Failed(result.reason)
                is UpdateActionResult.Completed -> UpdateState.ReadyToInstall(result.versionName)
                UpdateActionResult.Started -> _state.value
            }
        }
    }

    fun reportInstallCancelled() {
        _state.value = UpdateState.InstallCancelled
    }

    fun reportFailure(message: String) {
        _state.value = UpdateState.Failed(message)
    }
}
