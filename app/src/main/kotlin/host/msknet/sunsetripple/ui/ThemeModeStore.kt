package host.msknet.sunsetripple.ui

import android.content.Context

/**
 * 昼夜取向的落盘。用 SharedPreferences 而不是 DataStore：只存一个字符串，
 * 不值得为它多背一个依赖。
 */
class ThemeModeStore(context: Context) {

    private val preferences = context.applicationContext
        .getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun load(): ThemeMode = ThemeModeResolver.fromStoredValue(preferences.getString(KEY_MODE, null))

    fun save(mode: ThemeMode) {
        preferences.edit()
            .putString(KEY_MODE, ThemeModeResolver.toStoredValue(mode))
            .apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "sunset_ripple_appearance"
        const val KEY_MODE = "theme_mode"
    }
}
