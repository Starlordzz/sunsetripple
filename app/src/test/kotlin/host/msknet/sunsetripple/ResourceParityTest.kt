package host.msknet.sunsetripple

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test

class ResourceParityTest {
    @Test
    fun chineseAndEnglishStringsHaveMatchingKeysAndPlaceholders() {
        val chinese = readStrings(File("src/main/res/values/strings.xml"))
        val english = readStrings(File("src/main/res/values-en/strings.xml"))

        assertEquals(chinese.keys, english.keys)
        chinese.forEach { (key, value) ->
            assertEquals("Placeholder mismatch for $key", placeholders(value), placeholders(english.getValue(key)))
        }
    }

    private fun readStrings(file: File): Map<String, String> {
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        return (0 until document.getElementsByTagName("string").length).associate { index ->
            val node = document.getElementsByTagName("string").item(index)
            node.attributes.getNamedItem("name").nodeValue to node.textContent
        }
    }

    private fun placeholders(value: String): List<String> =
        Regex("%\\d+\\$[a-zA-Z]").findAll(value).map { it.value }.toList()
}
