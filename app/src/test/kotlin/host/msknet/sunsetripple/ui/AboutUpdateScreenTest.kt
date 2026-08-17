package host.msknet.sunsetripple.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AboutUpdateScreenTest {
    @Test
    fun sectionCanBeExpandedAndCollapsed() {
        val expanded = AboutContentState().toggle(AboutSection.CHANGELOG)

        assertEquals(AboutSection.CHANGELOG, expanded.expandedSection)
        assertNull(expanded.toggle(AboutSection.CHANGELOG).expandedSection)
    }

    @Test
    fun openingAnotherSectionClosesThePreviousOne() {
        val state = AboutContentState()
            .toggle(AboutSection.LICENSE)
            .toggle(AboutSection.PRIVACY)

        assertEquals(AboutSection.PRIVACY, state.expandedSection)
    }
}
