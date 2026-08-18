package host.msknet.sunsetripple.diagnostics

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

class DiagnosticExporter(private val context: Context) {
    fun share(report: DiagnosticReport) {
        val directory = File(context.cacheDir, "diagnostics").apply { mkdirs() }
        val reportFile = File(directory, "sunset-ripple-diagnostics.json")
        reportFile.writeText(report.encode())
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", reportFile)
        val intent = Intent(Intent.ACTION_SEND)
            .setType("application/json")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    fun openIssue(report: DiagnosticReport) {
        val uri = Uri.parse("https://github.com/Starlordzz/sunsetripple/issues/new").buildUpon()
            .appendQueryParameter("title", "[Android] Connection issue")
            .appendQueryParameter("body", report.issueSummary())
            .build()
        context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
