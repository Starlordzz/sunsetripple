# SunsetRipple HarmonyOS NEXT（纯血鸿蒙）适配指南

本文档提供 SunsetRipple 在 HarmonyOS NEXT 原生环境下的音视频与近场网络适配实现规范。

---

## 1. 通话级音频采集与播放 (`AudioEngine.ets`)

在 HarmonyOS NEXT 中，通过 `@ohos.multimedia.audio` 模块创建 `AudioCapturer` 和 `AudioRenderer`，通过指定 `SOURCE_TYPE_VOICE_COMMUNICATION` 自动启用麒麟芯片与鸿蒙系统的硬件回声消除（AEC）与降噪：

```typescript
import audio from '@ohos.multimedia.audio';

export class HarmonyAudioEngine {
  private capturer: audio.AudioCapturer | null = null;
  private renderer: audio.AudioRenderer | null = null;
  private isRunning: boolean = false;
  public micMuted: boolean = false;
  public onPcmFrame: (pcm: Int16Array) => void = () => {};

  async start(): Promise<void> {
    const audioStreamInfo: audio.AudioStreamInfo = {
      samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    };

    // 1. 采集器配置：通话语音模式，自动开启硬件级 AEC 与 NS
    const capturerInfo: audio.AudioCapturerInfo = {
      source: audio.SourceType.SOURCE_TYPE_VOICE_COMMUNICATION,
      capturerFlags: 0
    };
    this.capturer = await audio.createAudioCapturer({
      streamInfo: audioStreamInfo,
      capturerInfo: capturerInfo
    });

    // 2. 渲染器配置：通话语音流
    const rendererInfo: audio.AudioRendererInfo = {
      usage: audio.StreamUsage.STREAM_USAGE_VOICE_COMMUNICATION,
      rendererFlags: 0
    };
    this.renderer = await audio.createAudioRenderer({
      streamInfo: audioStreamInfo,
      rendererInfo: rendererInfo
    });

    await this.capturer.start();
    await this.renderer.start();
    this.isRunning = true;

    // 循环采集 20ms (320 samples / 640 bytes)
    this.readLoop();
  }

  private async readLoop(): Promise<void> {
    const bufferSize = 640; // 320 samples * 2 bytes
    while (this.isRunning && this.capturer) {
      const buffer = await this.capturer.read(bufferSize, true);
      if (!this.micMuted && buffer.byteLength > 0) {
        const int16 = new Int16Array(buffer);
        this.onPcmFrame(int16);
      }
    }
  }

  playPcm(pcm: Int16Array): void {
    if (this.renderer && this.isRunning) {
      this.renderer.write(pcm.buffer);
    }
  }

  async stop(): Promise<void> {
    this.isRunning = false;
    if (this.capturer) {
      await this.capturer.stop();
      await this.capturer.release();
      this.capturer = null;
    }
    if (this.renderer) {
      await this.renderer.stop();
      await this.renderer.release();
      this.renderer = null;
    }
  }
}
```

---

## 2. 鸿蒙 Wi-Fi P2P 组网与 Socket 通信 (`WifiP2pTransport.ets`)

在 HarmonyOS NEXT 中通过 `@ohos.net.wifi` 进行 P2P 组建与连接：

```typescript
import wifi from '@ohos.net.wifi';
import socket from '@ohos.net.socket';

export class HarmonyWifiP2pTransport {
  private tcpSocket: socket.TCPSocket = socket.constructTCPSocketInstance();
  private udpSocket: socket.UDPSocket = socket.constructUDPSocketInstance();

  async initP2pGroup(): Promise<void> {
    // 创建 P2P 群组
    wifi.createGroup({
      passphrase: '',
      groupName: 'SunsetRipple_P2P'
    });
  }

  async connectToPeer(deviceAddress: string): Promise<void> {
    const config: wifi.WifiP2pConfig = {
      deviceAddress: deviceAddress,
      netId: -1,
      passphrase: '',
      groupName: '',
      goBand: wifi.GroupOwnerBand.GO_BAND_AUTO
    };
    wifi.p2pConnect(config);
  }
}
```

