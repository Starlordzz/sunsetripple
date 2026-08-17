package host.msknet.sunsetripple.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class LanguagePolicyTest {
    @Test
    fun englishSystemLanguageUsesEnglish() {
        assertEquals(AppLanguage.ENGLISH, LanguagePolicy.resolve(listOf("en-US")))
    }

    @Test
    fun unsupportedOrMissingLanguageFallsBackToChinese() {
        assertEquals(AppLanguage.SIMPLIFIED_CHINESE, LanguagePolicy.resolve(listOf("ja-JP")))
        assertEquals(AppLanguage.SIMPLIFIED_CHINESE, LanguagePolicy.resolve(emptyList()))
    }
}
