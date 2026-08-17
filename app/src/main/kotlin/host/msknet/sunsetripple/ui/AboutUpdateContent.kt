package host.msknet.sunsetripple.ui

enum class AboutSection {
    CHANGELOG,
    LICENSE,
    PRIVACY,
}

data class AboutContentState(
    val expandedSection: AboutSection? = null,
) {
    fun toggle(section: AboutSection): AboutContentState =
        copy(expandedSection = section.takeUnless { it == expandedSection })
}
