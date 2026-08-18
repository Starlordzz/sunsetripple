package host.msknet.sunsetripple.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PendingActionQueueTest {
    @Test
    fun latestActionIsConsumedOnce() {
        val queue = PendingActionQueue<String>()
        queue.replace("old")
        queue.replace("new")

        assertEquals("new", queue.take())
        assertNull(queue.take())
    }
}
