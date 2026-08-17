package host.msknet.sunsetripple.ui

enum class AppLanguage {
    SIMPLIFIED_CHINESE,
    ENGLISH,
}

object LanguagePolicy {
    fun resolve(systemLanguageTags: List<String>): AppLanguage {
        val primary = systemLanguageTags.firstOrNull().orEmpty().lowercase()
        return if (primary == "en" || primary.startsWith("en-")) {
            AppLanguage.ENGLISH
        } else {
            AppLanguage.SIMPLIFIED_CHINESE
        }
    }
}
