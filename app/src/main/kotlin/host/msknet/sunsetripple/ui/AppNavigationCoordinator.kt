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
    fun restore(savedName: String?): Screen = when (savedName) {
        Screen.ABOUT_UPDATE.name -> Screen.ABOUT_UPDATE
        else -> Screen.HOME
    }

    fun save(screen: Screen): String = screen.name
}
