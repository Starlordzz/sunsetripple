package host.msknet.sunsetripple.ui

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AppNavigationCoordinator(initialScreen: Screen = Screen.HOME) {
    private val _screen = MutableStateFlow(initialScreen)
    val screen: StateFlow<Screen> = _screen.asStateFlow()

    fun navigateTo(screen: Screen) {
        _screen.value = screen
    }
}

object ScreenRestoration {
    data class RestoredState(
        val screen: Screen,
        val message: String? = null,
    )

    const val TRANSIENT_SCREEN_MESSAGE = "上次页面依赖的连接已结束，请重新进入房间"

    fun restore(savedName: String?): Screen = when (savedName) {
        Screen.ABOUT_UPDATE.name -> Screen.ABOUT_UPDATE
        else -> Screen.HOME
    }

    fun restoreState(savedName: String?): RestoredState {
        val savedScreen = Screen.entries.firstOrNull { it.name == savedName }
        val message = TRANSIENT_SCREEN_MESSAGE.takeIf {
            savedScreen != null && savedScreen != Screen.HOME && savedScreen != Screen.ABOUT_UPDATE
        }
        return RestoredState(restore(savedName), message)
    }

    fun save(screen: Screen): String = screen.name
}
