> 🌐 English | [简体中文](../HarmonyOS平台适配指南.md)

# SunsetRipple HarmonyOS NEXT (Pure HarmonyOS) Platform Guide

This document provides the specification for adapting SunsetRipple's audio and near-field networking to the native HarmonyOS NEXT environment.

---

## 1. Call-Grade Audio Capture and Playback (`AudioEngine.ets`)

In HarmonyOS NEXT, an `AudioCapturer` and an `AudioRenderer` are created through the `@ohos.multimedia.audio` module. Specifying `SOURCE_TYPE_VOICE_COMMUNICATION` automatically enables the hardware echo cancellation (AEC) and noise suppression of Kirin chipsets and the HarmonyOS system:

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

## 2. HarmonyOS Wi-Fi P2P Networking and Socket Communication (`WifiP2pTransport.ets`)

In HarmonyOS NEXT, P2P group creation and connection are performed via `@ohos.net.wifi`:

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
