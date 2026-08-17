package host.msknet.sunsetripple.update

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AboutUpdateCoordinator(
    private val checker: UpdateChecker,
) {
    private val _state = MutableStateFlow<UpdateState>(UpdateState.Idle)
    val state: StateFlow<UpdateState> = _state.asStateFlow()

    fun check() {
        _state.value = checker.check()
    }

    fun reportFailure(message: String) {
        _state.value = UpdateState.Failed(message)
    }
}
