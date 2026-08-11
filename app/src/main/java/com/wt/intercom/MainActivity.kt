package com.wt.intercom

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.wt.intercom.audio.LoopbackController

class MainActivity : ComponentActivity() {
    private val controller = LoopbackController()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                LoopbackScreen(controller)
            }
        }
    }

    override fun onDestroy() {
        controller.stop()
        super.onDestroy()
    }
}

@Composable
fun LoopbackScreen(controller: LoopbackController) {
    var running by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val permLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            runCatching { controller.start() }
                .onSuccess { running = true }
                .onFailure { Toast.makeText(context, it.message ?: "启动失败", Toast.LENGTH_LONG).show() }
        } else {
            Toast.makeText(context, "需要录音权限才能使用回环测试", Toast.LENGTH_LONG).show()
        }
    }
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            if (running) "回环运行中：对麦克风说话，约 0.1~0.2 秒后应听到自己（建议戴耳机）"
            else "音频回环 Demo（M1）"
        )
        Spacer(Modifier.height(16.dp))
        Button(onClick = {
            if (running) {
                controller.stop()
                running = false
            } else if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED
            ) {
                runCatching { controller.start() }
                    .onSuccess { running = true }
                    .onFailure { Toast.makeText(context, it.message ?: "启动失败", Toast.LENGTH_LONG).show() }
            } else {
                permLauncher.launch(Manifest.permission.RECORD_AUDIO)
            }
        }) {
            Text(if (running) "停止" else "开始回环")
        }
    }
}
